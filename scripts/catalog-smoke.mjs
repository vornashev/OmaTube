#!/usr/bin/env node
import { spawn } from 'node:child_process';
import readline from 'node:readline';

const child = spawn(process.execPath, ['catalog/worker.mjs'], { stdio: ['pipe', 'pipe', 'ignore'] });
const lines = readline.createInterface({ input: child.stdout });
let serial = 0;
const pending = new Map();
lines.on('line', line => {
  const response = JSON.parse(line);
  const waiter = pending.get(response.id);
  if (!waiter) return;
  pending.delete(response.id);
  response.ok ? waiter.resolve(response.result) : waiter.reject(new Error(`${response.error.code}: ${response.error.message}`));
});
function request(method, params = {}) {
  const id = ++serial;
  child.stdin.write(`${JSON.stringify({ id, method, params })}\n`);
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}
function requireItems(label, page) {
  const items = page.items ?? Object.values(page.sections ?? {}).flatMap(section => section.items ?? []);
  if (!items.length) throw new Error(`${label}: empty normalized result`);
  console.log(`${label}: ${items.length} items; first=${items[0].kind}:${items[0].videoId ?? items[0].id}`);
  return items;
}
try {
  await request('ping');
  const searches = [
    ['YouTube video', 'youtube', 'video', 'lofi hip hop'],
    ['YouTube playlist', 'youtube', 'playlist', 'lofi hip hop'],
    ['YouTube channel', 'youtube', 'channel', 'lofi hip hop'],
    ['Music song', 'music', 'song', 'Daft Punk'],
    ['Music video', 'music', 'video', 'Daft Punk'],
    ['Music playlist', 'music', 'playlist', 'Daft Punk'],
    ['Music artist', 'music', 'artist', 'Daft Punk']
  ];
  const results = {};
  for (const [label, source, kind, query] of searches) {
    const page = await request('search', { source, kind, query });
    results[`${source}:${kind}`] = requireItems(label, page);
    if (page.nextCursor) {
      const continuation = await request('next', { cursor: page.nextCursor });
      const nextItems = requireItems(`${label} continuation`, continuation);
      const firstIds = new Set(results[`${source}:${kind}`].map(item => item.videoId ?? item.id));
      if (nextItems.every(item => firstIds.has(item.videoId ?? item.id))) throw new Error(`${label}: continuation repeated first page`);
      await request('release', { cursor: page.nextCursor });
    }
  }
  const playlist = results['youtube:playlist'][0];
  requireItems('YouTube playlist open', await request('open', { entity: playlist }));
  const channel = results['youtube:channel'][0];
  const openedChannel = await request('open', { entity: channel });
  console.log(`YouTube channel open: ${openedChannel.entity?.title ?? channel.title}`);
  const musicPlaylist = results['music:playlist'][0];
  requireItems('Music playlist open', await request('open', { entity: musicPlaylist }));
  const artist = results['music:artist'][0];
  const openedArtist = await request('open', { entity: artist });
  console.log(`Music artist open: ${openedArtist.entity?.title ?? artist.title}`);
  console.log('CATALOG_SMOKE_OK');
} finally {
  child.kill('SIGTERM');
}
