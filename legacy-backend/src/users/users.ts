import { Body, Controller, Get, Module, Patch } from '@nestjs/common';
import { IsOptional, IsString, MaxLength } from 'class-validator';
import { UserId } from '../common/auth';
import { PrismaService } from '../prisma/prisma.service';

class UpdateMeDto {
  @IsOptional() @IsString() @MaxLength(60) displayName?: string;
}
const select = { id: true, email: true, displayName: true, plan: true, premiumUntil: true, createdAt: true };

@Controller('me')
export class UsersController {
  constructor(private readonly db: PrismaService) {}
  @Get() me(@UserId() id: string) { return this.db.user.findUniqueOrThrow({ where: { id }, select }); }
  @Patch() update(@UserId() id: string, @Body() dto: UpdateMeDto) { return this.db.user.update({ where: { id }, data: dto, select }); }
}

/** Billing stub: no real store verification yet. */
@Controller('subscription')
export class SubscriptionController {
  constructor(private readonly db: PrismaService) {}

  @Get()
  async status(@UserId() id: string) {
    const u = await this.db.user.findUniqueOrThrow({ where: { id } });
    const active = u.plan === 'premium' && (!u.premiumUntil || u.premiumUntil > new Date());
    return { plan: active ? 'premium' : 'free', active, premiumUntil: u.premiumUntil, products: [
      { id: 'smartprint.weekly', period: 'P1W', trialDays: 3 },
      { id: 'smartprint.yearly', period: 'P1Y', trialDays: 0 },
    ], billing: 'stub' };
  }
}

@Module({ controllers: [UsersController, SubscriptionController] })
export class UsersModule {}
