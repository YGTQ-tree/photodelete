import { test } from 'node:test';
import assert from 'node:assert/strict';

import { HOUR_MS, MINUTE_MS } from '../../entry/src/main/ets/common/Time';
import { MediaState, NO_EXPIRY } from '../../entry/src/main/ets/domain/MediaItem';
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

test('用例3：已到期 → 物化为待删除，且不删文件', async () => {
  const { repo, files, clock, service } = setup();
  const item = bufferItem('a', T0, 1);
  repo.seed(item);
  files.seed(item.filePath, 1024);
  files.seed(item.thumbPath, 32);

  clock.set(T0 + HOUR_MS + 1);
  const result = await service.normalize();

  assert.equal(result.scanned, 1, 'scanned = listExpired 返回的候选数');
  assert.equal(result.moved, 1);
  assert.equal(repo.get('a')?.state, MediaState.PENDING_DELETE);
  assert.equal(files.has(item.filePath), true, '物化绝不能删除文件');
  assert.equal(files.has(item.thumbPath), true);
});

test('用例4：now === expireAt 视为到期（闭区间）', async () => {
  const { repo, files, clock, service } = setup();
  const item = bufferItem('edge', T0, 1);
  repo.seed(item);
  files.seed(item.filePath, 1);

  clock.set(T0 + HOUR_MS);
  const result = await service.normalize();

  assert.equal(result.moved, 1);
  assert.equal(repo.get('edge')?.state, MediaState.PENDING_DELETE);
});

test('用例5：未到期保持缓冲', async () => {
  const { repo, clock, service } = setup();
  const item = bufferItem('b', T0, 24);
  repo.seed(item);

  clock.set(T0 + 23 * HOUR_MS);
  const result = await service.normalize();

  assert.equal(result.moved, 0);
  assert.equal(repo.get('b')?.state, MediaState.BUFFER);
});

test('用例6：无到期时间（永久保留）永不被物化', async () => {
  const { repo, clock, service } = setup();
  const item = bufferItem('forever', T0, 0);
  repo.seed(item);
  assert.equal(item.state, MediaState.KEPT);
  assert.equal(item.expireAt, NO_EXPIRY);

  clock.set(T0 + 1000 * 24 * HOUR_MS);
  const result = await service.normalize();

  assert.equal(result.moved, 0);
  assert.equal(repo.get('forever')?.state, MediaState.KEPT);
});

test('用例7：normalize 幂等——第二次 moved 为 0 且状态不变', async () => {
  const { repo, files, clock, service } = setup();
  const item = bufferItem('c', T0, 1);
  repo.seed(item);
  files.seed(item.filePath, 10);

  clock.set(T0 + 2 * HOUR_MS);
  const first = await service.normalize();
  const second = await service.normalize();

  assert.equal(first.moved, 1);
  assert.equal(second.moved, 0);
  assert.equal(second.scanned, 0);
  assert.equal(repo.get('c')?.state, MediaState.PENDING_DELETE);
  assert.equal(repo.get('c')?.updatedAt, T0 + 2 * HOUR_MS, '状态未被二次改写');
});

test('用例8：时钟回拨不误判、不回滚', async () => {
  const { repo, clock, service } = setup();
  const done = bufferItem('done', T0, 1);
  const later = bufferItem('later', T0, 24);
  repo.seed(done);
  repo.seed(later);

  clock.set(T0 + 2 * HOUR_MS);
  assert.equal((await service.normalize()).moved, 1);
  assert.equal(repo.get('done')?.state, MediaState.PENDING_DELETE);

  // 时钟回拨到拍摄之前
  clock.set(T0 - 5 * HOUR_MS);
  const afterRollback = await service.normalize();

  assert.equal(afterRollback.moved, 0);
  assert.equal(repo.get('done')?.state, MediaState.PENDING_DELETE, '已物化的不得回滚');
  assert.equal(repo.get('later')?.state, MediaState.BUFFER, '未到期的不得误判');
});

test('用例14：单次 normalize 只取一次 now', async () => {
  const { repo, clock, service } = setup();
  repo.seed(bufferItem('d1', T0, 1));
  repo.seed(bufferItem('d2', T0, 1));
  repo.seed(bufferItem('d3', T0, 24));

  clock.set(T0 + 3 * HOUR_MS);
  clock.calls = 0;
  await service.normalize();

  assert.equal(clock.calls, 1);
});

test('补充：多条目批量物化，一条记录只更新一次', async () => {
  const { repo, files, clock, service } = setup();
  for (const id of ['m1', 'm2', 'm3']) {
    const item = bufferItem(id, T0, 1);
    repo.seed(item);
    files.seed(item.filePath, 1);
  }
  clock.set(T0 + 2 * HOUR_MS);
  const result = await service.normalize();

  assert.equal(result.moved, 3);
  assert.equal((await repo.listByState(MediaState.PENDING_DELETE)).length, 3);
  assert.equal((await repo.listByState(MediaState.BUFFER)).length, 0);
});

test('补充：一分钟级时长同样按闭区间到期', async () => {
  const { repo, clock, service } = setup();
  const item = bufferItem('quick', T0, 1 / 60);
  repo.seed(item);

  clock.set(T0 + MINUTE_MS - 1);
  assert.equal((await service.normalize()).moved, 0);

  clock.set(T0 + MINUTE_MS);
  assert.equal((await service.normalize()).moved, 1);
});
