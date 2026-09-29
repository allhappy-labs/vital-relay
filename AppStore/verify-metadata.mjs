import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';

const metadataURL = new URL('./metadata/en-US.json', import.meta.url);
const metadata = JSON.parse(await readFile(metadataURL, 'utf8'));

const requiredKeys = [
  'name',
  'subtitle',
  'version',
  'description',
  'keywords',
  'primaryCategory',
  'secondaryCategory',
  'marketingURL',
  'supportURL',
  'privacyPolicyURL',
  'copyright',
];

assert.deepEqual(Object.keys(metadata), requiredKeys);
assert.ok(metadata.name.length >= 2 && metadata.name.length <= 30);
assert.ok(metadata.subtitle.length >= 2 && metadata.subtitle.length <= 30);
assert.ok(metadata.description.length >= 10 && metadata.description.length <= 4000);
assert.ok(Buffer.byteLength(metadata.keywords, 'utf8') <= 100);
assert.equal(metadata.version, '1.0.0');
assert.equal(metadata.primaryCategory, 'Health & Fitness');
assert.equal(metadata.secondaryCategory, 'Utilities');
assert.equal(metadata.marketingURL, 'https://health-sync.olhapi.com/');
assert.equal(metadata.supportURL, 'https://health-sync.olhapi.com/support');
assert.equal(
  metadata.privacyPolicyURL,
  'https://health-sync.olhapi.com/privacy',
);
assert.match(metadata.description, /Requires iOS 18 or later/);
assert.match(metadata.description, /Background synchronization is best effort/);

for (const file of [
  'app-privacy.md',
  'review-notes.md',
  'release-checklist.md',
]) {
  await access(new URL(`./${file}`, import.meta.url));
}

const source = async (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const project = await source('HAHealthSync.xcodeproj/project.pbxproj');
for (const suffix of ['', 'Tests', 'UITests']) {
  assert.equal(project.split(`PRODUCT_BUNDLE_IDENTIFIER = com.marynavdovenko.HAHealthSync${suffix};`).length - 1, 2);
}
assert.equal(project.split('DEVELOPMENT_TEAM = 9XN7WN8JN2;').length - 1, 6);
assert.match(await source('HAHealthSync/Adapters/Purchases/StoreKitLifetimeUnlock.swift'), /com\.marynavdovenko\.HAHealthSync\.lifetimeUnlock/);
for (const path of ['HAHealthSync/Resources/Info.plist', 'HAHealthSync/Adapters/Background/AppRefreshManager.swift']) {
  assert.ok((await source(path)).includes('com.marynavdovenko.HAHealthSync.refresh'));
}
for (const [path, namespace] of [
  ['HAHealthSync/Adapters/HealthKit/HealthKitOriginMetadata.swift', 'com.olhapi.HAHealthSync.origin'],
  ['HAHealthSync/Adapters/Keychain/KeychainCredentialStore.swift', 'com.olhapi.HAHealthSync.credentials'],
  ['HAHealthSync/Adapters/Persistence/ProtectedArchiveCheckpointStore.swift', 'com.olhapi.HAHealthSync'],
  ['HAHealthSync/Adapters/Background/BackgroundLog.swift', 'com.olhapi.HAHealthSync'],
  ['HAHealthSync/Adapters/HomeAssistant/URLSessionTransport.swift', 'com.olhapi.HAHealthSync'],
]) assert.ok((await source(path)).includes(namespace), `preserve internal namespace: ${path}`);
for (const name of ['PairingStore', 'BackfillCheckpointStore', 'SyncCheckpointStore', 'ConfigurationStore', 'MedicationCheckpointStore', 'PairingCheckpointStore', 'MetricFreshnessStore', 'SyncStatusStore']) {
  const path = `HAHealthSync/Adapters/Persistence/Protected${name}.swift`;
  assert.ok((await source(path)).includes('com.olhapi.HAHealthSync'), `preserve storage namespace: ${path}`);
}
assert.match(metadata.description, /Manual sync is free/);
assert.match(metadata.description, /lifetime unlock.*automatic.*Shortcuts.*historical/);
assert.match(metadata.description, /durable copy.*Home Assistant/);
for (const path of ['AppStore/review-notes.md', 'website/app/support/page.tsx']) {
  const copy = await source(path);
  assert.match(copy, /Manual sync is free/);
  assert.match(copy, /Restore Purchases/);
}
for (const path of ['AppStore/app-privacy.md', 'docs/privacy.md', 'website/app/privacy/page.tsx']) {
  const copy = await source(path);
  assert.match(copy, /StoreKit/);
  assert.match(copy, /durable copy/);
}
console.log('App Store metadata, release identity, purchase copy, and preserved namespaces verified');
