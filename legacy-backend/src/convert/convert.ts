import { BadRequestException, Body, Controller, HttpCode, Inject, Injectable, Module, Post, Res, ServiceUnavailableException, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { execFile } from 'child_process';
import type { Response } from 'express';
import { mkdtemp, readdir, readFile, rm, writeFile } from 'fs/promises';
import { tmpdir } from 'os';
import { extname, join } from 'path';
import { promisify } from 'util';
import { IsUrl } from 'class-validator';
import { AppEnv, ENV } from '../config';
import { assertPublicUrl } from './url-guard';

const run = promisify(execFile);
const MAX = Number(process.env.MAX_UPLOAD_MB ?? 25) * 1024 * 1024;
export const OFFICE_EXT = ['.doc', '.docx', '.odt', '.rtf', '.txt', '.csv', '.xls', '.xlsx', '.ods', '.ppt', '.pptx', '.odp', '.html', '.htm'];

class WebDto {
  @IsUrl({ require_protocol: true, protocols: ['http', 'https'] }) url: string;
}

@Injectable()
export class ConvertService {
  constructor(@Inject(ENV) private readonly env: AppEnv) {}

  /** LibreOffice headless; isolated profile per call so conversions can run in parallel. */
  async officeToPdf(name: string, data: Buffer): Promise<Buffer> {
    const ext = extname(name).toLowerCase();
    if (!OFFICE_EXT.includes(ext)) throw new BadRequestException(`Unsupported file type: ${ext || 'none'}`);
    const dir = await mkdtemp(join(tmpdir(), 'sp-conv-'));
    try {
      const input = join(dir, `input${ext}`);
      await writeFile(input, data);
      await run(this.env.sofficePath, [`-env:UserInstallation=file://${dir}/profile`, '--headless', '--norestore', '--convert-to', 'pdf', '--outdir', join(dir, 'out'), input], { timeout: this.env.convertTimeoutMs });
      const out = (await readdir(join(dir, 'out'))).find((f) => f.endsWith('.pdf'));
      if (!out) throw new Error('no output');
      return await readFile(join(dir, 'out', out));
    } catch (e) {
      if (e instanceof BadRequestException) throw e;
      throw new ServiceUnavailableException('Conversion failed');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }

  /** Headless Chrome if CHROME_PATH is set (best fidelity), else fetch HTML and render with LibreOffice. */
  async webToPdf(raw: string): Promise<Buffer> {
    const url = await assertPublicUrl(raw);
    if (this.env.chromePath) {
      const dir = await mkdtemp(join(tmpdir(), 'sp-web-'));
      try {
        const out = join(dir, 'page.pdf');
        await run(this.env.chromePath, ['--headless=new', '--no-sandbox', '--disable-gpu', `--user-data-dir=${dir}/p`, '--no-pdf-header-footer', `--print-to-pdf=${out}`, url.toString()], { timeout: this.env.convertTimeoutMs });
        return await readFile(out);
      } catch {
        throw new ServiceUnavailableException('Web conversion failed');
      } finally {
        await rm(dir, { recursive: true, force: true });
      }
    }
    const res = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(15000) }).catch(() => { throw new BadRequestException('Could not fetch URL'); });
    if (!res.ok) throw new BadRequestException(`URL returned ${res.status}`);
    let html = await res.text();
    if (!/<base /i.test(html)) html = html.replace(/<head[^>]*>/i, (m) => `${m}<base href="${url.toString()}">`);
    return this.officeToPdf('page.html', Buffer.from(html));
  }
}

@Controller('convert')
export class ConvertController {
  constructor(private readonly svc: ConvertService) {}

  @Post('office') @HttpCode(200)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX } }))
  async office(@UploadedFile() file: Express.Multer.File | undefined, @Res() res: Response) {
    if (!file) throw new BadRequestException('file is required');
    this.send(res, await this.svc.officeToPdf(file.originalname, file.buffer));
  }

  @Post('web') @HttpCode(200)
  async web(@Body() dto: WebDto, @Res() res: Response) {
    this.send(res, await this.svc.webToPdf(dto.url));
  }

  private send(res: Response, pdf: Buffer) {
    res.setHeader('Content-Type', 'application/pdf');
    res.send(pdf);
  }
}

@Module({ controllers: [ConvertController], providers: [ConvertService] })
export class ConvertModule {}
