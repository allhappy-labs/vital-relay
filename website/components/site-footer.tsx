import Link from 'next/link';

import { BrandLockup } from '@/components/brand-lockup';

export function SiteFooter() {
  return (
    <footer className="border-t border-white/8 bg-black/10">
      <div className="site-container flex flex-col gap-7 py-10 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <BrandLockup compact />
          <p className="mt-3 text-sm text-slate-500">© 2026 Oleh Vdovenko</p>
        </div>
        <nav
          aria-label="Legal and support"
          className="flex flex-wrap gap-x-6 gap-y-3 text-sm"
        >
          <Link className="text-slate-400 hover:text-white" href="/privacy">
            Privacy Policy
          </Link>
          <Link className="text-slate-400 hover:text-white" href="/support">
            Support
          </Link>
          <a
            className="text-slate-400 hover:text-white"
            href="mailto:o@olhapi.com"
          >
            o@olhapi.com
          </a>
        </nav>
      </div>
    </footer>
  );
}
