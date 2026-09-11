import { test } from 'node:test';
import assert from 'node:assert/strict';

import { HOUR_MS } from '../../entry/src/main/ets/common/Time';
import {
  MediaState,
  NO_EXPIRY,
  keepItem,
  materialize,
} from '../../entry/src/main/ets/domain/MediaItem';
import { TrashService } from '../../entry/src/main/ets/domain/TrashService';
import { FakeClock, FakeFileStore, FakeRepo, bufferItem } from './fakes';

const T0 = 1700000000000;

function setup() {
  const repo = new FakeRepo();
  const files = new FakeFileStore();
  const clock = new FakeClock(T0);
  const service = new TrashService(repo, files, clock);
  return { repo, files, clock, service };
}

/** 造一条已进入待删除的条目，并让它在文件仓里真实存在 */
function seedPending(repo: FakeRepo, files: FakeFileStore, id: string) {
  const item = bufferItem(id, T0, 1);
  item.state = MediaState.PENDING_DELETE;
  repo.seed(item);
  files.seed(item.filePath, 4096);
  files.seed(item.thumbPath, 64);
  return item;
}

test('用例9：删除待删除条目 → 文件消失、状态 DELETED、deletedAt 写入', async () => {
  const { repo, files, clock, service } = setup();
  const item = seedPending(repo, files, 'p1');

  clock.set(T0 + 3 * HOUR_MS);
  const result = await service.deleteItems(['p1']);

  assert.equal(result.requested, 1);
  assert.equal(result.deleted, 1);
  assert.equal(result.rejected, 0);
  assert.equal(result.failed, 0);
  assert.equal(files.has(item.filePath), false);
  assert.equal(files.has(item.thumbPath), false);

  const stored = repo.get('p1');
  assert.equal(stored?.state, MediaState.DELETED);
  assert.equal(stored?.deletedAt, T0 + 3 * HOUR_MS);
});

test('用例10：缓冲/已保留条目拒绝删除（不变量 2）', async () => {
  const { repo, files, clock, service } = setup();
  const buffered = bufferItem('b1', T0, 24);
  const kept = bufferItem('k1', T0, 0);
  repo.seed(buffered);
  repo.seed(kept);
  files.seed(buffered.filePath, 10);
  files.seed(kept.filePath, 10);

  clock.set(T0 + 1000);
  const result = await service.deleteItems(['b1', 'k1']);

  assert.equal(result.deleted, 0);
  assert.equal(result.rejected, 2);
  assert.equal(repo.get('b1')?.state, MediaState.BUFFER);
  assert.equal(repo.get('k1')?.state, MediaState.KEPT);
  assert.equal(files.has(buffered.filePath), true);
  assert.equal(files.has(kept.filePath), true);
});

test('补充：不存在的 id 计入 rejected，不影响其余条目', async () => {
  const { repo, files, clock, service } = setup();
  const item = seedPending(repo, files, 'p2');

  clock.set(T0 + 3 * HOUR_MS);
  const result = await service.deleteItems(['p2', 'ghost']);

  assert.equal(result.deleted, 1);
  assert.equal(result.rejected, 1);
  assert.equal(files.has(item.filePath), false);
});

test('用例11：部分文件删除失败 → 该条 failed，其余照常完成，不整体回滚', async () => {
  const { repo, files, clock, service } = setup();
  const a = seedPending(repo, files, 'fa');
  const b = seedPending(repo, files, 'fb');
  files.failOn(b.filePath);

  clock.set(T0 + 3 * HOUR_MS);
  const result = await service.deleteItems(['fa', 'fb']);

  assert.equal(result.deleted, 1);
  assert.equal(result.failed, 1);
  assert.equal(files.has(a.filePath), false);
  assert.equal(files.has(b.filePath), true, '失败条目的文件仍在，等待孤儿清理');
  assert.equal(repo.get('fa')?.state, MediaState.DELETED);
  assert.equal(
    repo.get('fb')?.state,
    MediaState.DELETED,
    '状态先改：崩溃/失败只会留下可回收的孤儿文件，不会留下悬空记录',
  );
});

test('用例12：保留 → 状态 KEPT 且清空到期时间，文件保留', async () => {
  const { repo, files, clock, service } = setup();
  const item = seedPending(repo, files, 'kp');

  clock.set(T0 + 3 * HOUR_MS);
  const kept = await service.keep(['kp']);

  assert.equal(kept, 1);
  const stored = repo.get('kp');
  assert.equal(stored?.state, MediaState.KEPT);
  assert.equal(stored?.expireAt, NO_EXPIRY);
  assert.equal(files.has(item.filePath), true);
});

test('补充：对缓冲条目调用 keep 无效', async () => {
  const { repo, clock, service } = setup();
  repo.seed(bufferItem('kb', T0, 24));

  clock.set(T0 + 1);
  assert.equal(await service.keep(['kb']), 0);
  assert.equal(repo.get('kb')?.state, MediaState.BUFFER);
});

test('用例13：DELETED 为终态，任何转换均无效', async () => {
  const { repo, files, clock, service } = setup();
  const item = seedPending(repo, files, 'dead');

  clock.set(T0 + 3 * HOUR_MS);
  await service.deleteItems(['dead']);
  const deletedAt = repo.get('dead')?.deletedAt;

  // 领域转换函数层面
  const copy = repo.get('dead');
  assert.ok(copy);
  clock.set(T0 + 10 * HOUR_MS);
  assert.equal(materialize(copy, T0 + 10 * HOUR_MS), false);
  assert.equal(keepItem(copy, T0 + 10 * HOUR_MS), false);

  // 服务层面：重复删除被拒绝，deletedAt 不被改写
  const again = await service.deleteItems(['dead']);
  assert.equal(again.deleted, 0);
  assert.equal(again.rejected, 1);
  assert.equal(await service.keep(['dead']), 0);
  assert.equal(repo.get('dead')?.state, MediaState.DELETED);
  assert.equal(repo.get('dead')?.deletedAt, deletedAt);
});

test('补充：删除使用注入时钟，且只取一次时间', async () => {
  const { repo, files, clock, service } = setup();
  seedPending(repo, files, 'x1');
  seedPending(repo, files, 'x2');

  clock.set(T0 + HOUR_MS);
  clock.calls = 0;
  await service.deleteItems(['x1', 'x2']);

  assert.equal(clock.calls, 1);
  assert.equal(repo.get('x1')?.updatedAt, T0 + HOUR_MS);
});
