import test from 'node:test';
import assert from 'node:assert/strict';
import { BoundedCache, estimateBytes } from './cache.mjs';

test('byte budget evicts the least recently used entry', () => {
  const cache = new BoundedCache({ maxBytes: 10, maxEntries: 5, ttl: 100, sizeOf: v => v.length });
  cache.set('a', '1234').set('b', '5678');
  cache.get('a');
  cache.set('c', '9012');
  assert.equal(cache.get('b'), undefined);
  assert.equal(cache.byteLength, 8);
  cache.set('large', 'x'.repeat(11));
  assert.equal(cache.get('large'), undefined);
});

test('expired cache data is released without a cache hit', () => {
  let now = 0;
  const cache = new BoundedCache({ maxBytes: 100, maxEntries: 5, ttl: 30, clock: () => now });
  cache.set('a', 1);
  now = 31;
  cache.prune();
  assert.equal(cache.size, 0);
  assert.equal(cache.byteLength, 0);
});

test('in-flight cursor stays alive until its operation completes', () => {
  let now = 0;
  const cache = new BoundedCache({ maxBytes: 8, maxEntries: 1, ttl: 30,
    clock: () => now, pinned: v => v.inFlight, sizeOf: () => 8 });
  const cursor = { inFlight: true };
  cache.set('active', cursor).set('other', { inFlight: false });
  assert.equal(cache.get('active'), cursor);
  now = 31;
  cache.prune();
  assert.equal(cache.size, 1);
  cursor.inFlight = false;
  cache.prune();
  assert.equal(cache.size, 0);
});

test('size estimator handles shared data and cycles', () => {
  const value = { title: 'video' };
  value.parent = value;
  assert.ok(estimateBytes(value) < 1000);
  assert.ok(estimateBytes([value, value]) < estimateBytes([value, { title: 'video' }]));
});

test('one oversized cursor remains usable, while old pages are released', () => {
  const cache = new BoundedCache({ maxBytes: 10, maxEntries: 3, ttl: 100,
    sizeOf: value => value.length, keepOversized: true });
  cache.set('old', 'small');
  cache.set('large', 'x'.repeat(20));
  assert.equal(cache.size, 1);
  assert.equal(cache.get('large').length, 20);
});
