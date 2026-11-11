// Budgets count retained JS data (an estimate), not process RSS or shared client objects.
export function estimateBytes(value, limit = Infinity) {
  const seen = new WeakSet();
  const pending = [value];
  let bytes = 0;
  while (pending.length && bytes <= limit) {
    const current = pending.pop();
    if (typeof current === 'string') { bytes += current.length * 2 + 16; continue; }
    if (!current || typeof current !== 'object') { bytes += 8; continue; }
    if (seen.has(current)) continue;
    seen.add(current);
    bytes += 64;
    if (current instanceof Map) {
      for (const [key, entry] of current) pending.push(key, entry);
    } else if (current instanceof Set) {
      for (const entry of current) pending.push(entry);
    } else {
      for (const key of Object.keys(current)) {
        // youtubei clients/actions are shared independently of the cached page.
        if (key === 'actions' || key === 'session') continue;
        bytes += key.length * 2 + 16;
        pending.push(current[key]);
      }
    }
  }
  return bytes;
}

export class BoundedCache extends Map {
  constructor({ maxBytes, maxEntries, ttl, clock = Date.now, sizeOf = estimateBytes,
    pinned = () => false, expiresAt = null, keepOversized = false }) {
    super();
    Object.assign(this, { maxBytes, maxEntries, ttl, clock, sizeOf, pinned, expiresAt, keepOversized });
    this.weights = new Map();
    this.expiry = new Map();
    this.byteLength = 0;
  }
  delete(key) {
    this.byteLength -= this.weights.get(key) ?? 0;
    this.weights.delete(key);
    this.expiry.delete(key);
    return super.delete(key);
  }
  get(key) {
    const value = super.get(key);
    if (value === undefined) return undefined;
    if (this.expiry.get(key) <= this.clock() && !this.pinned(value)) {
      this.delete(key); return undefined;
    }
    super.delete(key);
    super.set(key, value);
    return value;
  }
  set(key, value) {
    this.delete(key);
    const bytes = this.sizeOf(value);
    if (bytes > this.maxBytes && !this.pinned(value) && !this.keepOversized) return this;
    super.set(key, value);
    this.weights.set(key, bytes);
    this.expiry.set(key, this.expiresAt ? this.expiresAt(value) : this.clock() + this.ttl);
    this.byteLength += bytes;
    this.prune();
    return this;
  }
  prune() {
    const now = this.clock();
    for (const [key, value] of this) {
      if (this.expiry.get(key) <= now && !this.pinned(value)) this.delete(key);
    }
    for (const [key, value] of this) {
      if (this.size <= this.maxEntries && this.byteLength <= this.maxBytes) break;
      if (this.size === 1 && this.keepOversized) break;
      if (!this.pinned(value)) this.delete(key);
    }
  }
}
