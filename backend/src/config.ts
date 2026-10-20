export interface AppEnv {
  isProd: boolean;
  port: number;
  jwtSecret: string;
  jwtTtl: string;
  sofficePath: string;
  chromePath?: string;
  convertTimeoutMs: number;
  storage: {
    driver: 'local' | 's3';
    localDir: string;
    maxUploadBytes: number;
    s3: { bucket?: string; region: string; endpoint?: string; accessKeyId?: string; secretAccessKey?: string; forcePathStyle: boolean };
  };
}

const num = (v: string | undefined, d: number) => (v && !Number.isNaN(Number(v)) ? Number(v) : d);

export function loadEnv(src: NodeJS.ProcessEnv = process.env): AppEnv {
  const isProd = src.NODE_ENV === 'production';
  if (!src.DATABASE_URL || !src.JWT_SECRET) throw new Error('Missing env: DATABASE_URL, JWT_SECRET');
  if (isProd && src.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must be >= 32 chars in production');
  return {
    isProd,
    port: num(src.PORT, 3000),
    jwtSecret: src.JWT_SECRET,
    jwtTtl: src.JWT_TTL ?? '30d',
    sofficePath: src.SOFFICE_PATH ?? 'soffice',
    chromePath: src.CHROME_PATH || undefined,
    convertTimeoutMs: num(src.CONVERT_TIMEOUT_MS, 60000),
    storage: {
      driver: src.STORAGE_DRIVER === 's3' ? 's3' : 'local',
      localDir: src.UPLOAD_DIR ?? './uploads',
      maxUploadBytes: num(src.MAX_UPLOAD_MB, 25) * 1024 * 1024,
      s3: {
        bucket: src.S3_BUCKET,
        region: src.S3_REGION ?? 'auto',
        endpoint: src.S3_ENDPOINT,
        accessKeyId: src.S3_ACCESS_KEY_ID,
        secretAccessKey: src.S3_SECRET_ACCESS_KEY,
        forcePathStyle: src.S3_FORCE_PATH_STYLE === 'true',
      },
    },
  };
}

export const ENV = Symbol('ENV');
