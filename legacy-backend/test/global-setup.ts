import { execSync } from 'child_process';
import './setup-env';

export default async function globalSetup() {
  execSync('npx prisma migrate reset --force --skip-seed --skip-generate', {
    stdio: 'ignore',
    env: { ...process.env, PRISMA_USER_CONSENT_FOR_DANGEROUS_AI_ACTION: 'yes' },
  });
}
