/**
 * 真机缺陷回归（PLAN.md A5）：**调用方（UI）的数组不能原样透传给 native RDB。**
 *
 * 真机实测（`TrashPage` 的「诊断：@State 数组直传 RDB」按钮，A/B 对照，2026-09-11）：
 *   A 直传 ArkUI 的 `@State` 数组 → `THROW 401 Parameter error. The value must be a ValueType array.`
 *   B 同一批 id 逐元素复制成普通数组 → `OK(rows=1)`
 * 即：**ArkUI 的 `@State` 数组不能直接交给 native `predicates.in()`**。修复前
 * `TrashPage.confirmKeep` 把 `this.selectedIds` 原样传下去，所以「保留所选」在真机上无效。
 *
 * ⚠️ 关于本文件的探针：真机上的裸 JS `Proxy` 包普通数组**不复现**（`storageSmoke` 的
 * `proxyProbe=isProxy no-throw`），所以 `util.types.isProxy` 不是根因的同义探针 ——
 * Node 里造不出 ArkUI 的包装对象。这里用它是作为「**调用方数组被原样透传**」这一行为的
 * **近似探针**，锁住的是「领域层/数据层必须先复制再交给仓储」这条契约本身；
 * 根因的真机证据是上面那组 A/B 对照，不是本文件。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { types } from 'node:util';

import { MediaState, NO_EXPIRY } from '../../entry/src/main/ets/domain/MediaItem';
import { TrashService } from '../../entry/src/main/ets/domain/TrashService';
import { targetIds } from '../../entry/src/main/ets/domain/TrashStats';
import { FakeClock, FakeFileStore, FakeRepo, bufferItem } from './fakes';

const T0 = 1700000000000;

/** 在主机侧模拟「调用方给的数组不是普通数组」：Proxy 包着一个真数组 */
function observedLike(ids: string[]): string[] {
  return new Proxy(ids, {});
}

/** 在替身里放一条「已到期、待删除」的条目（原图与缩略图都在） */
function seedPending(repo: FakeRepo, files: FakeFileStore, id: string): void {
  const item = bufferItem(id, T0 - 7200000, 1);
  item.state = MediaState.PENDING_DELETE;
  item.expireAt = T0 - 3600000;
  repo.seed(item);
  files.seed(item.filePath, item.sizeBytes);
  files.seed(item.thumbPath, 64);
}

function newService(): { repo: FakeRepo; files: FakeFileStore; svc: TrashService } {
  const repo = new FakeRepo();
  const files = new FakeFileStore();
  const clock = new FakeClock(T0);
  return { repo: repo, files: files, svc: new TrashService(repo, files, clock) };
}

test('前置事实：本文件的探针在主机侧有效（否则回归是假证据）', () => {
  assert.equal(types.isProxy(observedLike(['a'])), true);
  assert.equal(types.isProxy(['a']), false);
});

test('keep：调用方数组不得原样透传给仓储（A5 回归）', async () => {
  const env = newService();
  seedPending(env.repo, env.files, 'a');
  seedPending(env.repo, env.files, 'b');

  const kept: number = await env.svc.keep(observedLike(['a']));

  assert.equal(env.repo.sawProxyIds, false,
    '仓储收到了非普通数组（出现在 ' + env.repo.proxyCallSite + '）→ 真机 RDB 会抛 401');
  assert.equal(kept, 1);
  assert.equal(env.repo.get('a')?.state, MediaState.KEPT);
  assert.equal(env.repo.get('a')?.expireAt, NO_EXPIRY);
  assert.equal(env.repo.get('b')?.state, MediaState.PENDING_DELETE, '未选中的条目不能被动到');
  assert.equal(env.files.has('files/media/a.jpg'), true, '保留不是删除，文件必须还在');
});

test('deleteItems：调用方数组同样不得透传（有选中的一键删除也中招）', async () => {
  const env = newService();
  seedPending(env.repo, env.files, 'a');
  seedPending(env.repo, env.files, 'b');

  const result = await env.svc.deleteItems(observedLike(['a']));

  assert.equal(env.repo.sawProxyIds, false,
    '仓储收到了非普通数组（出现在 ' + env.repo.proxyCallSite + '）→ 真机 RDB 会抛 401');
  assert.equal(result.deleted, 1);
  assert.equal(env.repo.get('a')?.state, MediaState.DELETED);
  assert.equal(env.files.has('files/media/a.jpg'), false);
  assert.equal(env.repo.get('b')?.state, MediaState.PENDING_DELETE, '未选中的条目不能被动到');
});

test('deleteItems：走 updateState 那条路也不得透传', async () => {
  const env = newService();
  seedPending(env.repo, env.files, 'a');

  // 全部删除的路径：listByIds 拿到的仍是调用方数组，updateState 必须收到普通数组
  const result = await env.svc.deleteItems(observedLike(['a']));

  assert.equal(env.repo.sawProxyIds, false, '出现在 ' + env.repo.proxyCallSite);
  assert.equal(result.deleted, 1);
});

test('targetIds：有选中时必须返回副本，不得把调用方的数组原样交出去', () => {
  const selected = observedLike(['a', 'b']);
  const items = [bufferItem('a', T0, 1), bufferItem('b', T0, 1)];

  const out = targetIds(items, selected);

  assert.equal(types.isProxy(out), false, 'targetIds 把调用方的数组原样返回了 → 会一路漏到 napi');
  assert.deepEqual(out, ['a', 'b']);
});

test('targetIds：无选中时返回全部（原本就是新数组）', () => {
  const items = [bufferItem('a', T0, 1), bufferItem('b', T0, 1)];
  const out = targetIds(items, []);
  assert.equal(types.isProxy(out), false);
  assert.deepEqual(out, ['a', 'b']);
});
