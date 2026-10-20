import { Global, Module } from '@nestjs/common';
import { AppEnv, ENV } from '../config';
import { LocalDiskDriver } from './local.driver';
import { S3Driver } from './s3.driver';
import { STORAGE } from './storage.driver';

@Global()
@Module({
  providers: [{
    provide: STORAGE,
    inject: [ENV],
    useFactory: (env: AppEnv) => (env.storage.driver === 's3' ? new S3Driver(env.storage.s3) : new LocalDiskDriver(env.storage.localDir)),
  }],
  exports: [STORAGE],
})
export class StorageModule {}
