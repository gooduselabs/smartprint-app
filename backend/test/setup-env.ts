process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ??= 'postgresql://smartprint:smartprint@localhost:5432/smartprint_test?schema=public';
process.env.JWT_SECRET ??= 'test-secret-test-secret-test-secret';
process.env.UPLOAD_DIR = require('path').join(require('os').tmpdir(), 'smartprint-test-uploads');
process.env.MAX_UPLOAD_MB = '5';
