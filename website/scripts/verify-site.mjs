import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';

const requiredRoutes = [
  'app/page.tsx',
  'app/privacy/page.tsx',
  'app/support/page.tsx',
  'app/not-found.tsx',
];

for (const route of requiredRoutes) {
  await access(new URL(`../${route}`, import.meta.url));
}

const sourceFiles = [
  'app/layout.tsx',
  'app/page.tsx',
  'app/privacy/page.tsx',
  'app/support/page.tsx',
  'app/not-found.tsx',
  'components/support-card.tsx',
];
const source = (
  await Promise.all(
    sourceFiles.map((file) =>
      readFile(new URL(`../${file}`, import.meta.url), 'utf8'),
    ),
  )
).join('\n');

for (const requiredCopy of [
  'https://health-sync.olhapi.com',
  'Oleh Vdovenko',
  'o@olhapi.com',
  'iOS 18',
  'no analytics',
  'mailto:o@olhapi.com',
  'Delete All Local App Data',
]) {
  assert.ok(
    source.includes(requiredCopy),
    `Missing required copy: ${requiredCopy}`,
  );
}

assert.match(source, /developer does not receive\s+your\s+health data/);

for (const asset of ['public/app-icon.png', 'public/og.png']) {
  await access(new URL(`../${asset}`, import.meta.url));
}

const layout = await readFile(
  new URL('../app/layout.tsx', import.meta.url),
  'utf8',
);
assert.match(
  layout,
  /metadataBase:\s*new URL\(['"]https:\/\/health-sync\.olhapi\.com['"]\)/,
);
assert.match(layout, /images:\s*\[.*?['"]\/og\.png['"]/s);

for (const [route, canonical] of [
  ['app/page.tsx', '/'],
  ['app/privacy/page.tsx', '/privacy'],
  ['app/support/page.tsx', '/support'],
]) {
  const routeSource = await readFile(
    new URL(`../${route}`, import.meta.url),
    'utf8',
  );
  const canonicalPattern = new RegExp(
    `canonical:\\s*['"]${canonical.replaceAll('/', '\\/')}['"]`,
  );
  assert.ok(
    canonicalPattern.test(routeSource) ||
      (canonical === '/' && canonicalPattern.test(layout)),
    `Missing canonical for ${canonical}`,
  );
}

for (const forbidden of [
  /<form\b/i,
  /google-analytics/i,
  /gtag\s*\(/i,
  /segment\.com/i,
]) {
  assert.doesNotMatch(
    source,
    forbidden,
    `Forbidden website behavior: ${forbidden}`,
  );
}

console.log('Website source verified');
