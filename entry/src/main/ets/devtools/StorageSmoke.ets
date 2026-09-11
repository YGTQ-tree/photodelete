/**
 * 真实存储链路的真机自检（T02 验收雏形）。
 *
 * 与 DomainSmoke 的区别：这里用**真的** RDB、**真的**沙箱文件、**真的** preferences，
 * 而不是内存替身。它验证的是「领域契约在鸿蒙实现上成立」。
 *
 * 首次运行需要已授予权限吗？不需要 —— 全部操作都在应用自己的沙箱与数据库里。
 */

import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { RdbMediaRepo } from '../data/RdbMediaRepo';
import { SandboxFileStore } from '../data/SandboxFileStore';
import { SettingsRepo } from '../data/SettingsRepo';
import { SystemClock } from '../infra/ClockImpl';
import { MediaItem, MediaState, NO_EXPIRY } from '../domain/MediaItem';
import { DEFAULT_KEEP_HOURS, expireAtOf } from '../domain/RetentionPolicy';
import { TrashService } from '../domain/TrashService';

/** 空代理处理器：ArkTS 禁止 `{}` 这种无类型对象字面量（arkts-no-untyped-obj-literals），故显式声明一个类。 */
class ProxyHandler {
}

/** 在沙箱里真实写一个占位图片文件 */
function writePlaceholder(store: SandboxFileStore, relPath: string, sizeBytes: number): void {
  const file = fileIo.openSync(
    store.absolutePath(relPath),
    fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
  );
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(sizeBytes);
    fileIo.writeSync(file.fd, buffer);
  } finally {
    fileIo.closeSync(file);
  }
}

export async function runStorageSmoke(context: common.Context): Promise<string> {
  const repo: RdbMediaRepo = await RdbMediaRepo.open(context);
  const files: SandboxFileStore = new SandboxFileStore(context.filesDir);
  files.ensureDirs();
  const settings: SettingsRepo = await SettingsRepo.open(context);
  const clock: SystemClock = new SystemClock();
  const service: TrashService = new TrashService(repo, files, clock);

  const keepHours: number = await settings.defaultKeepHours();
  const now: number = clock.nowMs();
  const id: string = 'smoke-' + now.toString();
  const relPath: string = 'files/media/' + id + '.jpg';
  const thumbRel: string = 'files/thumb/' + id + '.jpg';

  const checks: string[] = [];

  // 1) 真实写文件 + 真实落库（顺序：先文件后记录）
  writePlaceholder(files, relPath, 2048);
  writePlaceholder(files, thumbRel, 128);
  const item: MediaItem = new MediaItem(id, relPath, now);
  item.thumbPath = thumbRel;
  item.displayName = id + '.jpg';
  item.sizeBytes = await files.size(relPath);
  item.state = MediaState.BUFFER;
  // 注意：这里必须直接给「已过去 1 分钟」的 expireAt。
  // 早前写成 expireAtOf(now - 60000, 1) 是**夹具算错**——那是 now-1分钟+1小时=未来 59 分钟，
  // 于是 listExpired 返回空、normalize 不动、删除被拒，自检报 FAIL，而实现其实是对的。
  item.expireAt = now - 60000;
  item.policyKeepHours = 1;
  await repo.insert(item);
  checks.push('insert=' + (item.sizeBytes === 2048 ? 'ok' : 'size?' + item.sizeBytes));

  // 2) SQL 层下推查询
  const expired: MediaItem[] = await repo.listExpired(now);
  let found: boolean = false;
  for (const it of expired) {
    if (it.id === id) {
      found = true;
    }
  }
  checks.push('listExpired=' + (found ? 'ok' : 'MISS'));

  // 3) 物化（幂等）
  const moved1: number = (await service.normalize()).moved;
  const moved2: number = (await service.normalize()).moved;
  const pending: MediaItem[] = await repo.listByState(MediaState.PENDING_DELETE);
  let isPending: boolean = false;
  for (const it of pending) {
    if (it.id === id) {
      isPending = true;
    }
  }
  checks.push('normalize=' + moved1 + '/' + moved2 + (isPending ? ' ok' : ' MISS'));

  // 4) 一键删除：状态先改、文件后删
  const deleted: number = (await service.deleteItems([id])).deleted;
  const fileGone: boolean = !(await files.exists(relPath));
  const thumbGone: boolean = !(await files.exists(thumbRel));
  const row: MediaItem | undefined = (await repo.listByIds([id])).length > 0
    ? (await repo.listByIds([id]))[0]
    : undefined;
  const stateDeleted: boolean = row !== undefined && row.state === MediaState.DELETED;
  checks.push('delete=' + deleted + (fileGone ? ' file✓' : ' file✗')
    + (thumbGone ? ' thumb✓' : ' thumb✗') + (stateDeleted ? ' state✓' : ' state✗'));

  // 5) 保留（keep）真机契约用例：这一条是 A5 缺陷的**对照实验**。
  //    这里传进去的是普通数组，实测 PASS —— 说明 markKept 的 ValuesBucket
  //    （含 expire_at = -1）本身没问题，401 只可能来自「传进去的数组类型」。
  //    A5 的根因最终由 TrashPage 的 A/B 诊断按钮量出：直传 @State 数组 401、复制后 OK。
  const keepId: string = id + '-keep';
  const keepRel: string = 'files/media/' + keepId + '.jpg';
  writePlaceholder(files, keepRel, 512);
  const keeper: MediaItem = new MediaItem(keepId, keepRel, now);
  keeper.displayName = keepId + '.jpg';
  keeper.sizeBytes = 512;
  keeper.state = MediaState.BUFFER;
  keeper.expireAt = now - 60000;
  keeper.policyKeepHours = 1;
  await repo.insert(keeper);
  await service.normalize();
  const keptCount: number = await service.keep([keepId]);
  const keptRows: MediaItem[] = await repo.listByIds([keepId]);
  const keptRow: MediaItem | undefined = keptRows.length > 0 ? keptRows[0] : undefined;
  const keptState: boolean = keptRow !== undefined && keptRow.state === MediaState.KEPT;
  const keptExpire: boolean = keptRow !== undefined && keptRow.expireAt === NO_EXPIRY;
  const keptFile: boolean = await files.exists(keepRel);
  checks.push('keep=' + keptCount + (keptState ? ' state✓' : ' state✗')
    + (keptExpire ? ' expire✓' : ' expire✗') + (keptFile ? ' file✓' : ' file✗'));

  // 6) 附带实验（真机）：裸 JS Proxy 包一个普通数组，会不会也被 native 拒绝？
  //    结论：**不会**（`proxyProbe=isProxy no-throw`）。所以 A5 的根因**不能**写成「因为是 Proxy」
  //    —— ArkUI 的 @State 数组是它自己的包装对象，与 Proxy 不是一回事。
  //    先确认 Proxy 真的生效（`proxied !== plain`），否则这条探针就是「无牙齿」的假证据。
  let proxyProbe: string = 'n/a';
  try {
    const plain: string[] = [id];
    const proxied: string[] = new Proxy(plain, new ProxyHandler());
    // 关键：先确认 Proxy 真的生效（否则探针是「无牙齿」的——ArkTS 若静默返回原数组，
    // 「没抛错」就成了假证据）。
    const isRealProxy: boolean = proxied !== plain;
    const hit: MediaItem[] = await repo.listByIds(proxied);
    proxyProbe = (isRealProxy ? 'isProxy' : 'NOT-A-PROXY')
      + ' no-throw(' + hit.length.toString() + ')';
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    proxyProbe = 'threw:' + e.code.toString() + ' ' + e.message;
  }
  checks.push('proxyProbe=' + proxyProbe);

  // 7) 清理本次探针数据，避免反复运行堆积
  await repo.deleteRows([id]);
  await repo.deleteRows([keepId]);
  try {
    await files.remove(keepRel);
  } catch (err) {
    // 清理是尽力而为，失败不影响自检结论
  }

  const ok: boolean = item.sizeBytes === 2048 && found && moved1 === 1 && moved2 === 0
    && isPending && deleted === 1 && fileGone && thumbGone && stateDeleted
    && keptCount === 1 && keptState && keptExpire && keptFile;
  return 'storageSmoke=' + (ok ? 'PASS' : 'FAIL')
    + ' keepHours=' + keepHours + '(default ' + DEFAULT_KEEP_HOURS + ') | ' + checks.join(' | ');
}
