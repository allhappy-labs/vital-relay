import type { Metadata } from 'next';
import Link from 'next/link';

import { SupportCard } from '@/components/support-card';

export const metadata: Metadata = {
  title: 'Privacy Policy — HA Health Sync',
  description:
    'How HA Health Sync handles Apple Health data, Home Assistant credentials, local storage, diagnostics, and deletion.',
  alternates: { canonical: '/privacy' },
  openGraph: {
    url: '/privacy',
    title: 'Privacy Policy — HA Health Sync',
    description:
      'How HA Health Sync handles Apple Health data, Home Assistant credentials, local storage, diagnostics, and deletion.',
  },
};

const sections = [
  {
    title: 'Original-sample archive',
    body: (
      <>
        <p>
          Optional original-sample import on iOS 27 makes a durable copy of selected
          originals in your compatible Home Assistant Health Bridge archive.
          This archive has no automatic expiration. Administrators and configuration
          backups can access it. Export is plaintext and needs separate protection.
        </p>
        <p>
          The phone retains protected, backup-excluded checkpoints and one bounded
          pending raw batch with samples, provenance, and deletions for exact retries.
          The batch is removed after verified acknowledgement or local reset.
          Local reset, Health permission revocation, and purchase revocation do not
          erase archived data. Manage archive deletion and backup retention separately
          in Home Assistant.
        </p>
      </>
    ),
  },
  {
    title: 'Purchases',
    body: (
      <p>
        Apple handles the one-time lifetime unlock and Restore Purchases through
        StoreKit. The app verifies entitlements on device and does not send
        transaction payloads to a developer server or include them in diagnostics.
        The app does not handle payment-card data. Purchase does not grant Health
        permissions. Privacy controls and management of existing archived data
        remain available without a purchase.
      </p>
    ),
  },
  {
    title: 'What the app accesses',
    body: (
      <>
        <p>
          HA Health Sync requests read access only to the Apple Health data
          types you select. It requests write access only for supported
          HealthKit destinations you explicitly configure from Home Assistant.
          On supported iOS versions, medication access uses Apple&apos;s
          separate per-object authorization flow and remains read-only.
        </p>
        <p>
          You can change Health permissions at any time in the Health app or iOS
          Settings. Revoking access stops the affected synchronization but does
          not delete data already present in Apple Health or Home Assistant.
        </p>
      </>
    ),
  },
  {
    title: 'Where data goes',
    body: (
      <>
        <p>
          HA Health Sync does not send health data, credentials, diagnostics, or
          usage information to Oleh Vdovenko or to project-operated
          infrastructure. When you enable synchronization, the app sends
          selected data directly to the Home Assistant destination you
          configure.
        </p>
        <p>
          The developer has no account system, analytics, advertising, remote
          logging, external backend, or cloud database for this app. There are
          no analytics SDKs or tracking technologies in the app or this website.
        </p>
      </>
    ),
  },
  {
    title: 'Credentials and network security',
    body: (
      <>
        <p>
          Your Health Bridge webhook secret and Home Assistant long-lived access
          token are stored as separate, device-only records in the iOS Keychain.
          They are used only for requests to the Home Assistant destination you
          configure and are never included in diagnostics.
        </p>
        <p>
          Remote connections require HTTPS. Plain HTTP is limited to explicitly
          confirmed local or private-network destinations. TLS certificate
          validation is never disabled.
        </p>
      </>
    ),
  },
  {
    title: 'Local storage and diagnostics',
    body: (
      <>
        <p>
          Configuration, selections, pairings, synchronization checkpoints, and
          bounded status events are stored locally with iOS file protection and
          backup exclusion. Ordinary synchronization does not persist raw health
          readings, Home Assistant response bodies, medication names, or
          imported entity values.
        </p>
        <p>
          Diagnostics are deliberately limited to app/build/OS versions, feature
          states, counts, timestamps, and issue categories. They exclude health
          values, credentials, URLs, IP addresses, and entity identifiers.
        </p>
      </>
    ),
  },
  {
    title: 'Retention and deletion',
    body: (
      <>
        <p>
          Reset Synchronization State clears local checkpoints and status while
          preserving configuration, pairings, and credentials. Delete All Local
          App Data removes the app&apos;s configuration, pairings, checkpoints,
          status, and both Keychain records.
        </p>
        <p>
          These controls do not delete samples from Apple Health or data from
          your Home Assistant. Manage those environments using their own
          controls. Because the developer does not receive or retain your data,
          there is no developer-held user record to request or delete.
        </p>
      </>
    ),
  },
  {
    title: 'Third-party environments and children',
    body: (
      <>
        <p>
          Apple Health, iOS, Home Assistant, and any integrations you install
          are governed by their own terms and privacy practices. HA Health Sync
          does not use health data for advertising, marketing, profiling, or
          data mining and does not share it with data brokers.
        </p>
        <p>
          The app is not directed to children and does not knowingly collect
          personal information from children. Family or managed-device use
          remains subject to the permissions and policies of the relevant Apple
          and Home Assistant environments.
        </p>
      </>
    ),
  },
];

export default function PrivacyPage() {
  return (
    <main id="main-content">
      <div className="site-container grid gap-12 py-16 sm:py-24 lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start">
        <article className="legal-copy max-w-3xl">
          <p className="eyebrow">Effective 27 September 2026</p>
          <h1 className="section-title mt-4">Privacy Policy</h1>
          <p className="section-copy">
            HA Health Sync is designed so the developer does not receive your
            health data. This policy explains the app&apos;s direct data flow
            and the controls available to you.
          </p>

          <section>
            <h2>Developer and contact</h2>
            <p>
              HA Health Sync is developed by Oleh Vdovenko. Questions about this
              policy can be sent to{' '}
              <a href="mailto:o@olhapi.com">o@olhapi.com</a>.
            </p>
          </section>

          {sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.body}
            </section>
          ))}

          <section>
            <h2>Changes to this policy</h2>
            <p>
              Material changes will be published on this page with a new
              effective date. If the app later introduces a service that the
              developer can access, the App Store privacy disclosure and this
              policy will be updated before that version is released.
            </p>
          </section>

          <p className="mt-12 text-sm text-slate-500">
            Need help with the controls described here? Visit the{' '}
            <Link href="/support">Support page</Link>.
          </p>
        </article>

        <aside className="lg:sticky lg:top-24" aria-label="Privacy contact">
          <SupportCard name="Oleh Vdovenko" email="o@olhapi.com" />
        </aside>
      </div>
    </main>
  );
}
