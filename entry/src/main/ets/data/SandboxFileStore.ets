/**
 * FileStore 的沙箱实现。
 *
 * 目录布局（相对 filesDir）：
 *   files/media/<id>.jpg   原图
 *   files/thumb/<id>.jpg   缩略图
 *
 * remove 契约：**幂等** —— 文件不存在时视为成功；其它错误如实抛出，
 * 由 TrashService 记为 failed（状态先改，孤儿文件交给启动时的清理兜底）。
 */

import { fileIo } from '@kit.CoreFileKit';

import type { FileStore } from '../domain/ports';

export class SandboxFileStore implements FileStore {
  private root: string;

  constructor(filesDir: string) {
    this.root = filesDir;
  }

  /** 建立 media/ 与 thumb/ 两个目录（启动时调用一次） */
  ensureDirs(): void {
    this.mkdirIfMissing(this.root + '/files');
    this.mkdirIfMissing(this.mediaDir());
    this.mkdirIfMissing(this.thumbDir());
  }

  mediaDir(): string {
    return this.root + '/files/media';
  }

  thumbDir(): string {
    return this.root + '/files/thumb';
  }

  /** 领域层传入的是相对路径，这里拼成沙箱绝对路径 */
  absolutePath(relPath: string): string {
    return this.root + '/' + relPath;
  }

  private mkdirIfMissing(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path);
      }
    } catch (err) {
      // accessSync 在目录不存在时抛错，属预期路径
      fileIo.mkdirSync(path);
    }
  }

  async exists(relPath: string): Promise<boolean> {
    try {
      return fileIo.accessSync(this.absolutePath(relPath));
    } catch (err) {
      return false;
    }
  }

  async remove(relPath: string): Promise<void> {
    const path: string = this.absolutePath(relPath);
    if (!(await this.exists(relPath))) {
      return;
    }
    fileIo.unlinkSync(path);
  }

  async size(relPath: string): Promise<number> {
    try {
      const stat: fileIo.Stat = fileIo.statSync(this.absolutePath(relPath));
      return stat.size;
    } catch (err) {
      return 0;
    }
  }

  /** 列出某个绝对目录下的文件名 */
  listDir(absDir: string): string[] {
    try {
      return fileIo.listFileSync(absDir);
    } catch (err) {
      return [];
    }
  }

  /** FileStore 端口实现：按**相对路径**列目录，目录不存在时返回空数组 */
  async listFiles(relDir: string): Promise<string[]> {
    return this.listDir(this.absolutePath(relDir));
  }
}
