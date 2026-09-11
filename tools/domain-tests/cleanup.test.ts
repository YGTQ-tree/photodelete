import { test } from 'node:test';
import assert from 'node:assert/strict';

import { HOUR_MS } from '../../entry/src/main/ets/common/Time';
import { MediaItem, MediaState } from '../../entry/src/main/ets/domain/MediaItem';
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

/** 造一条「有记录也有文件」的正常条目 */
function seedHealthy(repo: FakeRepo, files: FakeFileStore, id: string, state: number) {
  const item = bufferItem(id, T0, 24);
  item.state = state;
  repo.seed(item);
  files.seed(item.filePath, 2048);
  files.seed(item.thumbPath, 64);
  return item;
}

test('孤儿清理：没有记录认领的文件被删除（含缩略图目录）', async () => {
  const { repo, files, service } = setup();
  seedHealthy(repo, files, 'alive', MediaState.BUFFER);

  files.seed('files/media/orphan1.jpg', 100);
  files.seed('files/thumb/orphan2.jpg', 100);

  const result = await service.cleanupOrphans();

  assert.equal(result.orphanFilesRemoved, 2);
  assert.equal(files.has('files/media/orphan1.jpg'), false);
  assert.equal(files.has('files/thumb/orphan2.jpg'), false);
  assert.equal(result.danglingRecordsMarked, 0);
});

test('孤儿清理：有记录且文件在 → 一个都不动', async () => {
  const { repo, files, service } = setup();
  const item = seedHealthy(repo, files, 'keepme', MediaState.PENDING_DELETE);

  const result = await service.cleanupOrphans();

  assert.equal(result.orphanFilesRemoved, 0);
  assert.equal(result.danglingRecordsMarked, 0);
  assert.equal(files.has(item.filePath), true);
  assert.equal(files.has(item.thumbPath), true);
  assert.equal(repo.get('keepme')?.state, MediaState.PENDING_DELETE);
});

test('孤儿清理：记录在但文件缺失 → 标记为 DELETED（悬空记录收敛）', async () => {
  const { repo, files, service } = setup();
  const item = bufferItem('dangling', T0, 24);
  repo.seed(item); // 故意不 seed 文件

  const result = await service.cleanupOrphans();

  assert.equal(result.danglingRecordsMarked, 1);
  assert.equal(repo.get('dangling')?.state, MediaState.DELETED);
});

test('孤儿清理：已 DELETED 的记录不再参与判定，重复清理是幂等的', async () => {
  const { repo, files, service } = setup();
  seedHealthy(repo, files, 'alive', MediaState.BUFFER);
  files.seed('files/media/leftover.jpg', 10);
  const dangling = bufferItem('gone', T0, 24);
  repo.seed(dangling);

  const first = await service.cleanupOrphans();
  assert.equal(first.orphanFilesRemoved, 1);
  assert.equal(first.danglingRecordsMarked, 1);

  const second = await service.cleanupOrphans();
  assert.equal(second.orphanFilesRemoved, 0, '第二次不应再删任何文件');
  assert.equal(second.danglingRecordsMarked, 0, '第二次不应再改任何记录');
  assert.equal(second.scannedRecords, 2, '两次都应扫到全部记录');
});

test('孤儿清理：单次调用只取一次 now', async () => {
  const { repo, files, clock, service } = setup();
  seedHealthy(repo, files, 'a', MediaState.BUFFER);
  files.seed('files/media/x.jpg', 1);

  clock.calls = 0;
  await service.cleanupOrphans();
  assert.equal(clock.calls, 1);
});

test('孤儿清理：条目为空时也不报错', async () => {
  const { service } = setup();
  const result = await service.cleanupOrphans();
  assert.equal(result.scannedRecords, 0);
  assert.equal(result.scannedFiles, 0);
  assert.equal(result.orphanFilesRemoved, 0);
  assert.equal(result.danglingRecordsMarked, 0);
});

test('孤儿清理：不误删仍在缓冲期的条目文件', async () => {
  const { repo, files, service } = setup();
  const buffered = seedHealthy(repo, files, 'buffered', MediaState.BUFFER);
  const kept = seedHealthy(repo, files, 'kept', MediaState.KEPT);
  repo.get('x'); // 触发一次读取，确保仓储可正常工作

  await service.cleanupOrphans();

  assert.equal(files.has(buffered.filePath), true);
  assert.equal(files.has(buffered.thumbPath), true);
  assert.equal(files.has(kept.filePath), true);
  assert.equal(repo.get('buffered')?.state, MediaState.BUFFER);
  assert.equal(repo.get('kept')?.state, MediaState.KEPT);
});

test('补：删除失败留下的文件会被下一次孤儿清理回收', async () => {
  const { repo, files, clock, service } = setup();
  const item = bufferItem('stuck', T0, 1);
  item.state = MediaState.PENDING_DELETE;
  repo.seed(item);
  files.seed(item.filePath, 4096);
  files.seed(item.thumbPath, 64);
  files.failOn(item.filePath); // 模拟删除时 IO 失败

  clock.set(T0 + HOUR_MS);
  const del = await service.deleteItems(['stuck']);
  assert.equal(del.failed, 1);
  assert.equal(files.has(item.filePath), true, '失败后文件仍在');
  assert.equal(repo.get('stuck')?.state, MediaState.DELETED, '状态已先改为 DELETED');

  // 故障解除后，孤儿清理应把残留收掉。
  // 注意是 2 个：deleteItems 的 try 块在「原图删除失败」处即中断，缩略图那次 remove 根本没被调用，
  // 所以原图与缩略图都成了无主文件。
  files.recoverOn(item.filePath);
  const recovered = await service.cleanupOrphans();
  assert.equal(recovered.orphanFilesRemoved, 2, '孤儿清理回收了原图与缩略图两个残留');
  assert.equal(files.has(item.filePath), false);
  assert.equal(files.has(item.thumbPath), false, '缩略图同样被回收');
});
