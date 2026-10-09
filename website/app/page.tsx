import Link from 'next/link';
import Image from 'next/image';
import {
  Activity,
  ArrowRight,
  Clock3,
  HeartPulse,
  LockKeyhole,
  ShieldCheck,
  Smartphone,
} from 'lucide-react';

import { FeatureCard } from '@/components/feature-card';
import { FlowSummary } from '@/components/flow-summary';
import { Badge } from '@/components/ui/badge';
import { buttonVariants } from '@/components/ui/button';
import { cn } from '@/lib/utils';

const features = [
  {
    title: 'Choose what moves',
    description:
      'Select the Apple Health types you want to export and configure only the Home Assistant values you want to import.',
    icon: <HeartPulse aria-hidden="true" />,
  },
  {
    title: 'Stay in control',
    description:
      'Run a sync manually, from Shortcuts, or let iOS offer background opportunities when conditions allow.',
    icon: <Clock3 aria-hidden="true" />,
  },
  {
    title: 'See status, not readings',
    description:
      'Diagnostics show counts, timestamps, and issue categories without exposing health values or credentials.',
    icon: <Activity aria-hidden="true" />,
  },
];

export default function Home() {
  return (
    <main id="main-content">
      <section className="hero-shell overflow-hidden">
        <div className="site-container relative grid gap-14 py-16 sm:py-24 lg:grid-cols-[1.08fr_0.92fr] lg:items-center lg:py-32">
          <div className="hero-glow hero-glow-health" aria-hidden="true" />
          <div className="hero-glow hero-glow-assistant" aria-hidden="true" />

          <div className="relative z-10 max-w-3xl">
            <Badge
              className="border border-white/10 bg-white/7 text-slate-100"
              variant="outline"
            >
              Version 1.0 · iPhone
            </Badge>
            <h1 className="mt-7 text-balance text-5xl font-semibold tracking-[-0.045em] text-white sm:text-6xl lg:text-7xl">
              Your health data.{' '}
              <span className="gradient-text">Your home.</span>
            </h1>
            <p className="mt-7 max-w-2xl text-pretty text-lg leading-8 text-slate-300 sm:text-xl">
              Vital Relay connects selected Apple Health data directly with
              the Home Assistant you control—without a developer cloud in the
              middle.
            </p>

            <div className="mt-9 flex flex-wrap gap-3">
              <Link
                className={cn(
                  buttonVariants({ size: 'lg' }),
                  'h-11 rounded-xl bg-white px-5 text-slate-950 hover:bg-slate-100',
                )}
                href="/privacy"
              >
                Read the privacy policy
                <ArrowRight aria-hidden="true" />
              </Link>
              <Link
                className={cn(
                  buttonVariants({ size: 'lg', variant: 'outline' }),
                  'h-11 rounded-xl border-white/15 bg-white/5 px-5 text-white hover:bg-white/10 hover:text-white',
                )}
                href="/support"
              >
                Get support
              </Link>
            </div>

            <div className="mt-10 flex flex-wrap gap-x-7 gap-y-3 text-sm text-slate-400">
              <span className="inline-flex items-center gap-2">
                <ShieldCheck
                  className="size-4 text-cyan-300"
                  aria-hidden="true"
                />
                No analytics or advertising
              </span>
              <span className="inline-flex items-center gap-2">
                <LockKeyhole
                  className="size-4 text-rose-300"
                  aria-hidden="true"
                />
                Credentials stay in Keychain
              </span>
            </div>
          </div>

          <div className="relative z-10 mx-auto w-full max-w-[520px] lg:ml-auto">
            <div className="icon-stage">
              <div className="icon-stage-ring" aria-hidden="true" />
              <Image
                alt="Vital Relay app icon, showing Apple Health and Home Assistant connected by two arrows"
                className="relative size-full rounded-[28%] shadow-2xl shadow-black/40"
                height="1024"
                priority
                src="/app-icon.png"
                width="1024"
              />
            </div>
            <div className="mt-6 rounded-2xl border border-white/10 bg-slate-950/60 p-5 shadow-xl backdrop-blur-xl">
              <p className="text-sm font-medium text-white">Direct by design</p>
              <p className="mt-1 text-sm leading-6 text-slate-400">
                Your health data goes directly between this iPhone and the Home
                Assistant you configure. It is not sent to the developer.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section
        className="site-container py-20 sm:py-28"
        aria-labelledby="flow-title"
      >
        <div className="max-w-2xl">
          <p className="eyebrow">One private bridge</p>
          <h2 id="flow-title" className="section-title">
            Apple Health and Home Assistant, in both directions.
          </h2>
          <p className="section-copy">
            Export selected HealthKit readings to Health Bridge or import
            supported Home Assistant entity values into Apple Health. Each
            direction stays explicit and user-controlled.
          </p>
        </div>
        <FlowSummary />
      </section>

      <section className="border-y border-white/8 bg-white/[0.025]">
        <div className="site-container py-20 sm:py-28">
          <div className="max-w-2xl">
            <p className="eyebrow">Built around consent</p>
            <h2 className="section-title">
              Useful automation without invisible collection.
            </h2>
          </div>
          <div className="mt-10 grid gap-5 md:grid-cols-3">
            {features.map((feature) => (
              <FeatureCard key={feature.title} {...feature} />
            ))}
          </div>
        </div>
      </section>

      <section
        className="site-container py-20 sm:py-28"
        aria-labelledby="requirements-title"
      >
        <div className="requirements-panel">
          <div>
            <p className="eyebrow">Before you begin</p>
            <h2 id="requirements-title" className="section-title mt-3">
              Bring the home you already run.
            </h2>
            <p className="section-copy max-w-2xl">
              Requires iOS 18 or later, Home Assistant, and the Health Bridge
              integration. You choose the server, credentials, health
              permissions, and synchronized data.
            </p>
          </div>
          <div className="grid gap-3 text-sm text-slate-300 sm:grid-cols-2 lg:grid-cols-1">
            <div className="requirement-row">
              <Smartphone aria-hidden="true" />
              iPhone with iOS 18 or later
            </div>
            <div className="requirement-row">
              <ShieldCheck aria-hidden="true" />
              Your own Home Assistant and Health Bridge
            </div>
          </div>
        </div>
        <p className="mx-auto mt-8 max-w-3xl text-center text-sm leading-6 text-slate-500">
          Background synchronization is best effort and controlled by iOS.
          Force-quitting the app can prevent later background delivery.
        </p>
      </section>
    </main>
  );
}
