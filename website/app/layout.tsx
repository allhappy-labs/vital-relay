import type { Metadata } from 'next';

import { SiteFooter } from '@/components/site-footer';
import { SiteHeader } from '@/components/site-header';

import './globals.css';

const title = 'Vital Relay — Apple Health and Home Assistant';
const description =
  'Private, direct synchronization between Apple Health and your Home Assistant.';

export const metadata: Metadata = {
  metadataBase: new URL('https://health-sync.olhapi.com'),
  title,
  description,
  alternates: { canonical: '/' },
  icons: { icon: '/app-icon.png', apple: '/app-icon.png' },
  openGraph: {
    type: 'website',
    url: '/',
    title,
    description,
    siteName: 'Vital Relay',
    images: [
      {
        url: '/og.png',
        width: 1200,
        height: 630,
        alt: 'Vital Relay connects Apple Health and Home Assistant',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title,
    description,
    images: ['/og.png'],
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        <SiteHeader />
        {children}
        <SiteFooter />
      </body>
    </html>
  );
}
