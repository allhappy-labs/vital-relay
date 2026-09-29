import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';

import { buttonVariants } from '@/components/ui/button';
import { cn } from '@/lib/utils';

export default function NotFound() {
  return (
    <main
      id="main-content"
      className="site-container flex min-h-[70vh] items-center py-20"
    >
      <div className="max-w-2xl">
        <p className="eyebrow">404 · Page not found</p>
        <h1 className="section-title mt-4">
          This route is not part of the bridge.
        </h1>
        <p className="section-copy">
          Return home, review the Privacy Policy, or visit Support for setup and
          troubleshooting guidance.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link
            className={cn(
              buttonVariants({ size: 'lg' }),
              'h-11 rounded-xl px-5',
            )}
            href="/"
          >
            <ArrowLeft aria-hidden="true" />
            Home
          </Link>
          <Link
            className={cn(
              buttonVariants({ size: 'lg', variant: 'outline' }),
              'h-11 rounded-xl px-5',
            )}
            href="/privacy"
          >
            Privacy
          </Link>
          <Link
            className={cn(
              buttonVariants({ size: 'lg', variant: 'outline' }),
              'h-11 rounded-xl px-5',
            )}
            href="/support"
          >
            Support
          </Link>
        </div>
      </div>
    </main>
  );
}
