import { Readable } from 'stream';

/** Blob storage abstraction: local disk in dev, any S3-compatible service in prod. */
export interface StorageDriver {
  readonly name: string;
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  get(key: string): Promise<{ stream: Readable; size?: number }>;
  delete(key: string): Promise<void>;
}

export const STORAGE = Symbol('STORAGE');
