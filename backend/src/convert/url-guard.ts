import { BadRequestException } from '@nestjs/common';
import { lookup } from 'dns/promises';
import { isIP } from 'net';

/** Blocks SSRF: only public http(s) hosts are allowed. */
export function isPrivateIp(ip: string): boolean {
  if (ip.startsWith('::ffff:')) ip = ip.slice(7);
  if (isIP(ip) === 4) {
    const [a, b] = ip.split('.').map(Number);
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127) || a >= 224;
  }
  const l = ip.toLowerCase();
  return l === '::1' || l === '::' || l.startsWith('fc') || l.startsWith('fd') || l.startsWith('fe80');
}

export async function assertPublicUrl(raw: string): Promise<URL> {
  let url: URL;
  try { url = new URL(raw); } catch { throw new BadRequestException('Invalid URL'); }
  if (!['http:', 'https:'].includes(url.protocol)) throw new BadRequestException('Only http(s) URLs are allowed');
  if (process.env.ALLOW_PRIVATE_URLS === 'true') return url;
  const addrs = await lookup(url.hostname, { all: true }).catch(() => { throw new BadRequestException('Host not found'); });
  if (addrs.some((a) => isPrivateIp(a.address))) throw new BadRequestException('Private addresses are not allowed');
  return url;
}
