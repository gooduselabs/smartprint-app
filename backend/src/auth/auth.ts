import { Body, ConflictException, Controller, HttpCode, Injectable, Module, Post, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { hash, verify } from '@node-rs/argon2';
import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { Public } from '../common/auth';
import { PrismaService } from '../prisma/prisma.service';

export class RegisterDto {
  @IsEmail() email: string;
  @IsString() @MinLength(8) @MaxLength(128) password: string;
  @IsOptional() @IsString() @MaxLength(60) displayName?: string;
}
export class LoginDto {
  @IsEmail() email: string;
  @IsString() password: string;
}

@Injectable()
export class AuthService {
  constructor(private readonly db: PrismaService, private readonly jwt: JwtService) {}

  private async issue(user: { id: string; email: string; displayName: string | null; plan: string }) {
    return { accessToken: await this.jwt.signAsync({ sub: user.id }), user: { id: user.id, email: user.email, displayName: user.displayName, plan: user.plan } };
  }

  async register(dto: RegisterDto) {
    const email = dto.email.toLowerCase().trim();
    if (await this.db.user.findUnique({ where: { email } })) throw new ConflictException('Email already registered');
    const user = await this.db.user.create({ data: { email, passwordHash: await hash(dto.password), displayName: dto.displayName } });
    return this.issue(user);
  }

  async login(dto: LoginDto) {
    const user = await this.db.user.findUnique({ where: { email: dto.email.toLowerCase().trim() } });
    if (!user || !(await verify(user.passwordHash, dto.password))) throw new UnauthorizedException('Invalid email or password');
    return this.issue(user);
  }
}

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  @Public() @Post('register') register(@Body() dto: RegisterDto) { return this.auth.register(dto); }
  @Public() @Post('login') @HttpCode(200) login(@Body() dto: LoginDto) { return this.auth.login(dto); }
}

@Module({ controllers: [AuthController], providers: [AuthService] })
export class AuthModule {}
