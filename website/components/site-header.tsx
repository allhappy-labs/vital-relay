import Link from 'next/link';

import { BrandLockup } from '@/components/brand-lockup';

const navigation = [
  { href: '/', label: 'Home' },
  { href: '/privacy', label: 'Privacy' },
  { href: '/support', label: 'Support' },
];

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-50 border-b border-white/8 bg-[#07111f]/85 backdrop-blur-xl">
      <div className="site-container flex min-h-16 items-center justify-between gap-6 py-3">
        <BrandLockup compact />
        <nav aria-label="Primary" className="flex items-center gap-1 sm:gap-2">
          {navigation.map((item) => (
            <Link
              className="rounded-lg px-3 py-2 text-sm font-medium text-slate-400 transition-colors hover:bg-white/6 hover:text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
              href={item.href}
              key={item.href}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </div>
    </header>
  );
}
