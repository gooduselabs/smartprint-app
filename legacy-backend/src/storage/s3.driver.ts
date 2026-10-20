import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { Readable } from 'stream';
import { AppEnv } from '../config';
import { StorageDriver } from './storage.driver';

/** Works with AWS S3, Cloudflare R2, MinIO, Backblaze B2, DigitalOcean Spaces… */
export class S3Driver implements StorageDriver {
  readonly name = 's3';
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(cfg: AppEnv['storage']['s3']) {
    if (!cfg.bucket) throw new Error('S3_BUCKET is required when STORAGE_DRIVER=s3');
    this.bucket = cfg.bucket;
    this.client = new S3Client({
      region: cfg.region,
      endpoint: cfg.endpoint,
      forcePathStyle: cfg.forcePathStyle,
      credentials: cfg.accessKeyId && cfg.secretAccessKey ? { accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey } : undefined,
    });
  }

  async put(key: string, body: Buffer, contentType: string) {
    await this.client.send(new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: body, ContentType: contentType }));
  }

  async get(key: string) {
    const r = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return { stream: r.Body as Readable, size: r.ContentLength };
  }

  async delete(key: string) {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }
}
