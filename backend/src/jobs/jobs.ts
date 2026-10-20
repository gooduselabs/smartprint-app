import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsDateString, IsIn, IsInt, IsOptional, IsString, MaxLength, Min, ValidateNested } from 'class-validator';
import { UserId } from '../common/auth';
import { PrismaService } from '../prisma/prisma.service';

export class JobDto {
  @IsString() @MaxLength(64) clientId: string;
  @IsString() @MaxLength(200) title: string;
  @IsIn(['document', 'photo', 'web', 'scan']) kind: string;
  @IsOptional() @IsInt() @Min(1) pages?: number;
  @IsOptional() @IsInt() @Min(1) copies?: number;
  @IsOptional() @IsString() @MaxLength(200) printer?: string;
  @IsOptional() @IsIn(['done', 'failed', 'cancelled']) status?: string;
  @IsDateString() printedAt: string;
}
class SyncDto {
  @IsArray() @ArrayMaxSize(500) @ValidateNested({ each: true }) @Type(() => JobDto) jobs: JobDto[];
}

@Controller('jobs')
export class JobsController {
  constructor(private readonly db: PrismaService) {}

  @Get()
  list(@UserId() userId: string, @Query('since') since?: string) {
    return this.db.printJob.findMany({
      where: { userId, ...(since ? { createdAt: { gt: new Date(since) } } : {}) },
      orderBy: { printedAt: 'desc' }, take: 500,
    });
  }

  /** Idempotent bulk upsert keyed by the device-generated clientId. */
  @Post('sync') @HttpCode(200)
  async sync(@UserId() userId: string, @Body() dto: SyncDto) {
    await this.db.$transaction(dto.jobs.map((j) => {
      const data = { ...j, printedAt: new Date(j.printedAt) };
      return this.db.printJob.upsert({ where: { userId_clientId: { userId, clientId: j.clientId } }, create: { ...data, userId }, update: data });
    }));
    return { synced: dto.jobs.length };
  }

  @Delete(':id') @HttpCode(204)
  async remove(@UserId() userId: string, @Param('id', ParseUUIDPipe) id: string) {
    await this.db.printJob.deleteMany({ where: { id, userId } });
  }
}

@Module({ controllers: [JobsController] })
export class JobsModule {}
