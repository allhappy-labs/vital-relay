import Link from 'next/link';
import Image from 'next/image';

import { cn } from '@/lib/utils';

export function BrandLockup({ compact = false }: { compact?: boolean }) {
  return (
    <Link
      aria-label="Vital Relay home"
      className="group inline-flex items-center gap-3 no-underline"
      href="/"
    >
      <Image
        alt=""
        aria-hidden="true"
        className={cn(
          'rounded-[28%] shadow-lg shadow-black/25 transition-transform group-hover:scale-[1.03]',
          compact ? 'size-8' : 'size-10',
        )}
        height="48"
        src="/app-icon.png"
        width="48"
      />
      <span
        className={cn(
          'font-semibold tracking-[-0.02em] text-white',
          compact ? 'text-sm' : 'text-base',
        )}
      >
        Vital Relay
      </span>
    </Link>
  );
}
