import type { Metadata } from 'next';
import Link from 'next/link';
import {
  KeyRound,
  LockKeyhole,
  RefreshCw,
  Router,
  ShieldCheck,
} from 'lucide-react';

import { SupportCard } from '@/components/support-card';

export const metadata: Metadata = {
  title: 'Support — HA Health Sync',
  description:
    'Setup, connection, Health permission, background synchronization, and local-data guidance for HA Health Sync.',
  alternates: { canonical: '/support' },
  openGraph: {
    url: '/support',
    title: 'Support — HA Health Sync',
    description:
      'Setup, connection, Health permission, background synchronization, and local-data guidance for HA Health Sync.',
  },
};

const supportTopics = [
  {
    icon: <RefreshCw aria-hidden="true" />,
    title: 'Free sync and lifetime unlock',
    copy: 'Manual sync is free. A one-time lifetime unlock enables automatic background sync, all Shortcuts sync, and historical imports. Open Settings → Lifetime Unlock to see your App Store price or use Restore Purchases with the purchasing Apple Account. There is no subscription. Pending purchases remain locked until verified; cancellation is not a purchase. Purchase does not grant Health permissions or guarantee background delivery.',
  },
  {
    icon: <ShieldCheck aria-hidden="true" />,
    title: 'Historical imports and your archive',
    copy: 'Original-sample import requires iOS 27, a compatible Health Bridge fork, Health permissions, and approved phone ownership. It creates a durable copy in your Home Assistant archive with no automatic expiration. Local reset, permission changes, and purchase revocation do not delete it. Manage archive export, deletion, and backups in Home Assistant. Refund or revocation stops future paid work while preserving existing archived data.',
  },
  {
    icon: <Router aria-hidden="true" />,
    title: 'Connection tests',
    copy: 'Confirm that Home Assistant and Health Bridge are running, then test the Home Assistant token and Health Bridge secret separately in the app. Remote addresses must use trusted HTTPS.',
  },
  {
    icon: <ShieldCheck aria-hidden="true" />,
    title: 'Health permissions',
    copy: 'Open Apple Health or iOS Settings to review access. HA Health Sync cannot infer a denied read permission from an empty result, and it requests only the types you select.',
  },
  {
    icon: <RefreshCw aria-hidden="true" />,
    title: 'Background delivery',
    copy: 'Background synchronization is best effort and scheduled by iOS. Keep Background App Refresh enabled; force-quitting the app can prevent later background delivery.',
  },
  {
    icon: <LockKeyhole aria-hidden="true" />,
    title: 'Locked iPhone',
    copy: 'Apple Health can be unavailable while the iPhone is locked. The app preserves synchronization progress and waits for a later opportunity after protected data becomes available.',
  },
];

export default function SupportPage() {
  return (
    <main id="main-content">
      <div className="site-container py-16 sm:py-24">
        <div className="max-w-3xl">
          <p className="eyebrow">Help without sharing private data</p>
          <h1 className="section-title mt-4">Support</h1>
          <p className="section-copy">
            HA Health Sync requires an iPhone with iOS 18 or later, your own
            Home Assistant, and the Health Bridge integration. Start with the
            focused checks below.
          </p>
        </div>

        <section
          className="mt-12 grid gap-5 md:grid-cols-2"
          aria-label="Troubleshooting topics"
        >
          {supportTopics.map((topic) => (
            <article
              className="rounded-2xl border border-white/8 bg-slate-900/55 p-6"
              key={topic.title}
            >
              <div className="flex size-10 items-center justify-center rounded-xl bg-cyan-300/8 text-cyan-300 [&_svg]:size-5">
                {topic.icon}
              </div>
              <h2 className="mt-5 text-lg font-semibold text-white">
                {topic.title}
              </h2>
              <p className="mt-2 text-sm leading-6 text-slate-400">
                {topic.copy}
              </p>
            </article>
          ))}
        </section>

        <section className="mt-16 grid gap-8 lg:grid-cols-[1fr_340px] lg:items-start">
          <div className="rounded-3xl border border-white/8 bg-white/[0.025] p-7 sm:p-9">
            <div className="flex size-11 items-center justify-center rounded-xl bg-rose-300/8 text-rose-300">
              <KeyRound aria-hidden="true" />
            </div>
            <h2 className="mt-6 text-2xl font-semibold tracking-tight text-white">
              Reset and deletion are different
            </h2>
            <div className="mt-4 space-y-4 text-sm leading-6 text-slate-400">
              <p>
                <strong className="text-slate-200">
                  Reset Synchronization State
                </strong>{' '}
                clears checkpoints and status but keeps your configuration,
                pairings, and credentials.
              </p>
              <p>
                <strong className="text-slate-200">
                  Delete All Local App Data
                </strong>{' '}
                removes configuration, pairings, checkpoints, status, and both
                Keychain credentials from this iPhone. It does not delete Apple
                Health samples or Home Assistant data.
              </p>
              <p>
                Read the <Link href="/privacy">Privacy Policy</Link> for the
                complete data-flow and retention explanation.
              </p>
            </div>
          </div>

          <SupportCard name="Oleh Vdovenko" email="o@olhapi.com" />
        </section>
      </div>
    </main>
  );
}
