import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';

const hasSoffice = (() => { try { require('child_process').execFileSync(process.env.SOFFICE_PATH ?? 'soffice', ['--version'], { stdio: 'ignore', timeout: 20000 }); return true; } catch { return false; } })();

describe('SmartPrint API', () => {
  let app: INestApplication;
  let http: any;
  let token: string;
  let other: string;

  beforeAll(async () => {
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    configureApp(app, { swagger: false });
    await app.init();
    http = app.getHttpServer();
    token = (await request(http).post('/auth/register').send({ email: 'Hai@Example.com', password: 'password123', displayName: 'Hải' }).expect(201)).body.accessToken;
    other = (await request(http).post('/auth/register').send({ email: 'b@example.com', password: 'password123' }).expect(201)).body.accessToken;
  });
  afterAll(() => app.close());
  const auth = (t = token) => ({ Authorization: `Bearer ${t}` });

  it('health is public', () => request(http).get('/health').expect(200, { ok: true }));

  describe('auth', () => {
    it('rejects duplicate email (case-insensitive)', () => request(http).post('/auth/register').send({ email: 'hai@example.com', password: 'password123' }).expect(409));
    it('rejects short password', () => request(http).post('/auth/register').send({ email: 'c@example.com', password: 'short' }).expect(400));
    it('logs in', async () => {
      const r = await request(http).post('/auth/login').send({ email: 'hai@example.com', password: 'password123' }).expect(200);
      expect(r.body.user).toMatchObject({ email: 'hai@example.com', plan: 'free' });
    });
    it('rejects wrong password', () => request(http).post('/auth/login').send({ email: 'hai@example.com', password: 'nope-nope' }).expect(401));
    it('requires token', () => request(http).get('/me').expect(401));
    it('rejects bad token', () => request(http).get('/me').set({ Authorization: 'Bearer x.y.z' }).expect(401));
  });

  it('profile get/update', async () => {
    await request(http).patch('/me').set(auth()).send({ displayName: 'Đức Hải' }).expect(200);
    const r = await request(http).get('/me').set(auth()).expect(200);
    expect(r.body.displayName).toBe('Đức Hải');
    expect(r.body.passwordHash).toBeUndefined();
  });

  it('subscription stub', async () => {
    const r = await request(http).get('/subscription').set(auth()).expect(200);
    expect(r.body).toMatchObject({ plan: 'free', active: false, billing: 'stub' });
  });

  describe('print jobs', () => {
    const job = { clientId: 'dev-1', title: 'invoice.pdf', kind: 'document', pages: 2, printedAt: new Date().toISOString() };
    it('syncs idempotently and isolates users', async () => {
      await request(http).post('/jobs/sync').set(auth()).send({ jobs: [job, { ...job, clientId: 'dev-2', kind: 'scan' }] }).expect(200, { synced: 2 });
      await request(http).post('/jobs/sync').set(auth()).send({ jobs: [{ ...job, title: 'renamed.pdf' }] }).expect(200);
      const r = await request(http).get('/jobs').set(auth()).expect(200);
      expect(r.body).toHaveLength(2);
      expect(r.body.find((j: any) => j.clientId === 'dev-1').title).toBe('renamed.pdf');
      expect((await request(http).get('/jobs').set(auth(other))).body).toHaveLength(0);
      await request(http).delete(`/jobs/${r.body[0].id}`).set(auth(other)).expect(204);
      expect((await request(http).get('/jobs').set(auth())).body).toHaveLength(2);
      await request(http).delete(`/jobs/${r.body[0].id}`).set(auth()).expect(204);
      expect((await request(http).get('/jobs').set(auth())).body).toHaveLength(1);
    });
    it('validates kind', () => request(http).post('/jobs/sync').set(auth()).send({ jobs: [{ ...job, kind: 'fax' }] }).expect(400));
  });

  describe('documents', () => {
    it('upload, list, download, delete; private to owner', async () => {
      const up = await request(http).post('/documents').set(auth()).attach('file', Buffer.from('%PDF-1.4 hello'), { filename: 'a.pdf', contentType: 'application/pdf' }).expect(201);
      expect((await request(http).get('/documents').set(auth())).body).toHaveLength(1);
      const dl = await request(http).get(`/documents/${up.body.id}/content`).set(auth()).buffer(true).expect(200);
      expect(dl.headers['content-type']).toContain('application/pdf');
      await request(http).get(`/documents/${up.body.id}/content`).set(auth(other)).expect(404);
      await request(http).delete(`/documents/${up.body.id}`).set(auth()).expect(204);
      expect((await request(http).get('/documents').set(auth())).body).toHaveLength(0);
    });
    it('rejects oversize', () => request(http).post('/documents').set(auth()).attach('file', Buffer.alloc(6 * 1024 * 1024), 'big.bin').expect(413));
  });

  describe('convert', () => {
    it('rejects unsupported type', () => request(http).post('/convert/office').set(auth()).attach('file', Buffer.from('x'), 'a.exe').expect(400));
    it('blocks private URLs', () => request(http).post('/convert/web').set(auth()).send({ url: 'http://127.0.0.1:3000/health' }).expect(400));
    it('rejects bad URL', () => request(http).post('/convert/web').set(auth()).send({ url: 'javascript:alert(1)' }).expect(400));
    (hasSoffice ? it : it.skip)('converts txt to PDF with LibreOffice', async () => {
      const r = await request(http).post('/convert/office').set(auth()).attach('file', Buffer.from('Xin chào SmartPrint'), 'note.txt').buffer(true).parse((res, cb) => { const c: Buffer[] = []; res.on('data', (d: Buffer) => c.push(d)); res.on('end', () => cb(null, Buffer.concat(c))); }).expect(200);
      expect(r.headers['content-type']).toContain('application/pdf');
      expect((r.body as Buffer).subarray(0, 4).toString()).toBe('%PDF');
    });
  });
});
