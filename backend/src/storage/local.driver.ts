import { createReadStream } from 'fs';
import { mkdir, rm, stat, writeFile } from 'fs/promises';
import { dirname, resolve, sep } from 'path';
import { StorageDriver } from './storage.driver';

export class LocalDiskDriver implements StorageDriver {
  readonly name = 'local';
  private readonly root: string;

  constructor(dir: string) {
    this.root = resolve(dir);
  }

  /** Keys are server-generated, but still refuse anything escaping the root. */
  private path(key: string) {
    const p = resolve(this.root, key);
    if (!p.startsWith(this.root + sep)) throw new Error('Invalid storage key');
    return p;
  }

  async put(key: string, body: Buffer) {
    const p = this.path(key);
    await mkdir(dirname(p), { recursive: true });
    await writeFile(p, body, { flag: 'wx' });
  }

  async get(key: string) {
    const p = this.path(key);
    const st = await stat(p);
    return { stream: createReadStream(p), size: st.size };
  }

  async delete(key: string) {
    await rm(this.path(key), { force: true });
  }
}
