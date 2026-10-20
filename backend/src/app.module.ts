import { Controller, Get, Global, Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { AuthModule } from './auth/auth';
import { JwtAuthGuard, Public } from './common/auth';
import { ENV, loadEnv } from './config';
import { ConvertModule } from './convert/convert';
import { DocumentsModule } from './documents/documents';
import { JobsModule } from './jobs/jobs';
import { PrismaModule } from './prisma/prisma.service';
import { StorageModule } from './storage/storage.module';
import { UsersModule } from './users/users';

@Controller('health')
class HealthController {
  @Public() @Get() ok() { return { ok: true }; }
}

@Global()
@Module({ providers: [{ provide: ENV, useFactory: loadEnv }], exports: [ENV] })
class ConfigModule {}

@Module({
  imports: [
    ConfigModule,
    JwtModule.registerAsync({ global: true, useFactory: () => { const e = loadEnv(); return { secret: e.jwtSecret, signOptions: { expiresIn: e.jwtTtl as any } }; } }),
    PrismaModule, StorageModule, AuthModule, UsersModule, JobsModule, DocumentsModule, ConvertModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }],
})
export class AppModule {}
