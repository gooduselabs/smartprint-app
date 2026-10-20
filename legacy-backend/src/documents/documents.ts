import { BadRequestException, Controller, Delete, Get, HttpCode, Inject, Module, NotFoundException, Param, ParseUUIDPipe, Post, Res, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { randomUUID } from 'crypto';
import type { Response } from 'express';
import { UserId } from '../common/auth';
import { PrismaService } from '../prisma/prisma.service';
import { STORAGE, StorageDriver } from '../storage/storage.driver';

const MAX = Number(process.env.MAX_UPLOAD_MB ?? 25) * 1024 * 1024;

@Controller('documents')
export class DocumentsController {
  constructor(private readonly db: PrismaService, @Inject(STORAGE) private readonly storage: StorageDriver) {}

  @Get()
  list(@UserId() userId: string) {
    return this.db.document.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, select: { id: true, name: true, contentType: true, size: true, createdAt: true } });
  }

  @Post()
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX } }))
  async upload(@UserId() userId: string, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('file is required');
    const key = `docs/${userId}/${randomUUID()}`;
    await this.storage.put(key, file.buffer, file.mimetype);
    const doc = await this.db.document.create({ data: { userId, name: file.originalname.slice(0, 200), contentType: file.mimetype, size: file.size, storageKey: key } });
    return { id: doc.id, name: doc.name, contentType: doc.contentType, size: doc.size, createdAt: doc.createdAt };
  }

  @Get(':id/content')
  async download(@UserId() userId: string, @Param('id', ParseUUIDPipe) id: string, @Res() res: Response) {
    const doc = await this.db.document.findFirst({ where: { id, userId } });
    if (!doc) throw new NotFoundException();
    const { stream } = await this.storage.get(doc.storageKey);
    res.setHeader('Content-Type', doc.contentType);
    res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(doc.name)}`);
    stream.pipe(res);
  }

  @Delete(':id') @HttpCode(204)
  async remove(@UserId() userId: string, @Param('id', ParseUUIDPipe) id: string) {
    const doc = await this.db.document.findFirst({ where: { id, userId } });
    if (!doc) throw new NotFoundException();
    await this.storage.delete(doc.storageKey);
    await this.db.document.delete({ where: { id } });
  }
}

@Module({ controllers: [DocumentsController] })
export class DocumentsModule {}
