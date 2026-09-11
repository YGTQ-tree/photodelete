/**
 * L2 设备侧契约测试：验证「领域契约在鸿蒙真实实现上成立」。
 *
 * 与 L1（tools/domain-tests，内存替身）的分工：
 *   L1 用假实现锁业务规则；这里用**真实 RDB + 真实沙箱 + 真实 preferences** 锁实现契约。
 *
 * 运行：hvigorw onDeviceTest --mode module -p module=entry@ohosTest -p product=default
 * 结果：DevEco 下看测试报告；本仓库用 `hdc shell aa test` 或 IDE 查看（见 docs/ENVIRONMENT.md）。
 */

import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

import { RdbMediaRepo } from '../../../main/ets/data/RdbMediaRepo';
import { SandboxFileStore } from '../../../main/ets/data/SandboxFileStore';
import { SettingsRepo } from '../../../main/ets/data/SettingsRepo';
import { SystemClock } from '../../../main/ets/infra/ClockImpl';
import { MediaItem, MediaState, NO_EXPIRY } from '../../../main/ets/domain/MediaItem';
import { DEFAULT_KEEP_HOURS, expireAtOf } from '../../../main/ets/domain/RetentionPolicy';
import { TrashService } from '../../../main/ets/domain/TrashService';

const DOMAIN: number = 0x0000;

/** 每次运行用独立前缀，避免与历史数据互相干扰 */
const RUN: string = 't' + new Date().getTime().toString();

function writePlaceholder(files: SandboxFileStore, relPath: string, sizeBytes: number): void {
  const file = fileIo.openSync(
    files.absolutePath(relPath),
    fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
  );
  try {
    fileIo.writeSync(file.fd, new ArrayBuffer(sizeBytes));
  } finally {
    fileIo.closeSync(file);
  }
}

export default function storageContractTest() {
  describe('StorageContract', () => {
    let context: common.Context;
    let repo: RdbMediaRepo;
    let files: SandboxFileStore;
    let settings: SettingsRepo;
    let service: TrashService;
    const createdIds: string[] = [];

    /** 造一条真实文件 + 真实记录，返回条目
     *  ArkTS 禁止嵌套函数声明（arkts-no-nested-funcs），因此用箭头函数 */
    const seed = async (
      key: string,
      state: number,
      capturedAt: number,
      expireAt: number,
      sizeBytes: number
    ): Promise<MediaItem> => {
      const id: string = RUN + '-' + key;
      const relPath: string = 'files/media/' + id + '.jpg';
      const thumbRel: string = 'files/thumb/' + id + '.jpg';
      writePlaceholder(files, relPath, sizeBytes);
      writePlaceholder(files, thumbRel, 64);
      const item: MediaItem = new MediaItem(id, relPath, capturedAt);
      item.thumbPath = thumbRel;
      item.displayName = id + '.jpg';
      item.mimeType = 'image/jpeg';
      item.sizeBytes = await files.size(relPath);
      item.state = state;
      item.expireAt = expireAt;
      item.policyKeepHours = 1;
      await repo.insert(item);
      createdIds.push(id);
      return item;
    };

    beforeAll(async () => {
      context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      repo = await RdbMediaRepo.open(context);
      files = new SandboxFileStore(context.filesDir);
      files.ensureDirs();
      settings = await SettingsRepo.open(context);
      service = new TrashService(repo, files, new SystemClock());
    });

    afterAll(async () => {
      for (const id of createdIds) {
        const items: MediaItem[] = await repo.listByIds([id]);
        for (const item of items) {
          try {
            await files.remove(item.filePath);
            await files.remove(item.thumbPath);
          } catch (err) {
            // 忽略：清理阶段尽力而为
          }
        }
      }
      await repo.deleteRows(createdIds);
    });

    it('沙箱文件仓：写入可见、remove 幂等', 0, async () => {
      const rel: string = 'files/media/' + RUN + '-fs.bin';
      writePlaceholder(files, rel, 1024);
      expect(await files.exists(rel)).assertTrue();
      expect(await files.size(rel)).assertEqual(1024);

      await files.remove(rel);
      expect(await files.exists(rel)).assertFalse();
      // 再删一次不得抛错（幂等契约）
      await files.remove(rel);
      expect(await files.exists(rel)).assertFalse();
    });

    it('仓储：插入后可按状态与 id 查回，字段不丢失', 0, async () => {
      const now: number = new Date().getTime();
      const item: MediaItem = await seed('insert', MediaState.BUFFER, now, expireAtOf(now, 1), 2048);

      const byId: MediaItem[] = await repo.listByIds([item.id]);
      expect(byId.length).assertEqual(1);
      expect(byId[0].filePath).assertEqual(item.filePath);
      expect(byId[0].mimeType).assertEqual('image/jpeg');
      expect(byId[0].sizeBytes).assertEqual(2048);
      expect(byId[0].expireAt).assertEqual(item.expireAt);
    });

    it('listExpired：过期缓冲命中、未到期与永久不命中', 0, async () => {
      const now: number = new Date().getTime();
      const expired: MediaItem = await seed('exp', MediaState.BUFFER, now - 7200000, now - 60000, 100);
      const future: MediaItem = await seed('fut', MediaState.BUFFER, now, expireAtOf(now, 24), 100);
      const forever: MediaItem = await seed('kept', MediaState.KEPT, now, NO_EXPIRY, 100);

      const hit: MediaItem[] = await repo.listExpired(now);
      let sawExpired: boolean = false;
      let sawFuture: boolean = false;
      let sawForever: boolean = false;
      for (const it of hit) {
        if (it.id === expired.id) {
          sawExpired = true;
        }
        if (it.id === future.id) {
          sawFuture = true;
        }
        if (it.id === forever.id) {
          sawForever = true;
        }
      }
      expect(sawExpired).assertTrue();
      expect(sawFuture).assertFalse();
      expect(sawForever).assertFalse();
    });

    it('物化：到期进入 PENDING_DELETE 且幂等，文件不被删除', 0, async () => {
      const now: number = new Date().getTime();
      const item: MediaItem = await seed('norm', MediaState.BUFFER, now - 7200000, now - 60000, 512);

      const first: number = (await service.normalize()).moved;
      const second: number = (await service.normalize()).moved;
      expect(first > 0).assertTrue();
      expect(second).assertEqual(0);

      const after: MediaItem[] = await repo.listByIds([item.id]);
      expect(after[0].state).assertEqual(MediaState.PENDING_DELETE);
      expect(await files.exists(item.filePath)).assertTrue();
    });

    it('一键删除：文件消失、状态 DELETED、deletedAt 写入', 0, async () => {
      const now: number = new Date().getTime();
      const item: MediaItem = await seed('del', MediaState.PENDING_DELETE, now, now - 1000, 4096);

      const result = await service.deleteItems([item.id]);
      expect(result.deleted).assertEqual(1);
      expect(result.failed).assertEqual(0);
      expect(await files.exists(item.filePath)).assertFalse();
      expect(await files.exists(item.thumbPath)).assertFalse();

      const after: MediaItem[] = await repo.listByIds([item.id]);
      expect(after[0].state).assertEqual(MediaState.DELETED);
      expect(after[0].deletedAt === NO_EXPIRY).assertFalse();
    });

    it('保留：清空到期时间且文件仍在；缓冲条目不可删', 0, async () => {
      const now: number = new Date().getTime();
      const pending: MediaItem = await seed('keep', MediaState.PENDING_DELETE, now, now - 1000, 256);
      const buffered: MediaItem = await seed('buf', MediaState.BUFFER, now, expireAtOf(now, 24), 256);

      expect(await service.keep([pending.id])).assertEqual(1);
      const kept: MediaItem[] = await repo.listByIds([pending.id]);
      expect(kept[0].state).assertEqual(MediaState.KEPT);
      expect(kept[0].expireAt).assertEqual(NO_EXPIRY);
      expect(await files.exists(pending.filePath)).assertTrue();

      // 不变量 2：缓冲条目拒绝删除
      const rejected = await service.deleteItems([buffered.id]);
      expect(rejected.deleted).assertEqual(0);
      expect(rejected.rejected).assertEqual(1);
      expect(await files.exists(buffered.filePath)).assertTrue();
    });

    it('设置：默认时长可读、写入后读回一致，且非法负数归零', 0, async () => {
      const original: number = await settings.defaultKeepHours();
      expect(original).assertEqual(DEFAULT_KEEP_HOURS);

      await settings.setDefaultKeepHours(6);
      expect(await settings.defaultKeepHours()).assertEqual(6);

      await settings.setDefaultKeepHours(-3);
      expect(await settings.defaultKeepHours()).assertEqual(0);

      await settings.setDefaultKeepHours(original);
      expect(await settings.defaultKeepHours()).assertEqual(original);
    });

    it('孤儿清理：真实沙箱无主文件被回收、悬空记录被标记为 DELETED', 0, async () => {
      const now: number = new Date().getTime();

      // 1) 无主文件：文件真实存在，但没有任何记录认领
      const orphanRel: string = 'files/media/' + RUN + '-orphan.jpg';
      writePlaceholder(files, orphanRel, 128);
      expect(await files.exists(orphanRel)).assertTrue();

      // 2) 悬空记录：记录存在，但文件缺失
      const danglingId: string = RUN + '-dangling';
      const dangling: MediaItem = new MediaItem(
        danglingId, 'files/media/' + danglingId + '.jpg', now);
      dangling.state = MediaState.BUFFER;
      dangling.expireAt = expireAtOf(now, 24);
      await repo.insert(dangling);
      createdIds.push(danglingId);

      const result = await service.cleanupOrphans();

      expect(result.orphanFilesRemoved >= 1).assertTrue();
      expect(await files.exists(orphanRel)).assertFalse();
      const after: MediaItem[] = await repo.listByIds([danglingId]);
      expect(after[0].state).assertEqual(MediaState.DELETED);

      // 幂等：再清一次不应再有改动
      const again = await service.cleanupOrphans();
      expect(again.orphanFilesRemoved).assertEqual(0);
      expect(again.danglingRecordsMarked).assertEqual(0);
    });
  });
}
