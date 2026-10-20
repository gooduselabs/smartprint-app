import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { configureApp } from './bootstrap';
import { loadEnv } from './config';

async function main() {
  const app = await NestFactory.create(AppModule);
  configureApp(app);
  await app.listen(loadEnv().port, '0.0.0.0');
}
void main();
