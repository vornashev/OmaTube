#!/usr/bin/env node
import { Innertube, UniversalCache, Log } from 'youtubei.js';
import { randomUUID } from 'node:crypto';
import readline from 'node:readline';
Log.setLevel(Log.Level.ERROR);

const MAX_LINE = 8 * 1024 * 1024;
const CURSOR_TTL_MS = 15 * 60 * 1000;
const MAX_IDLE_CURSORS = 32;
const cursors = new Map();
let client;
let clientPromise;

class ProviderError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const text = value => {
  if (value == null) return '';
  if (typeof value === 'string') return value;
  if (typeof value.text === 'string') return value.text;
  if (typeof value.toString === 'function') {
    const rendered = value.toString();
    if (rendered !== '[object Object]') return rendered;
  }
  return '';
};

const thumbnails = value => {
  const rows = value?.thumbnails ?? value ?? [];
  if (!Array.isArray(rows)) return [];
  return rows.filter(row => row?.url).sort((a, b) => (a.width ?? 0) - (b.width ?? 0));
};

const bestThumbnail = node => {
  const candidates = [
    node?.thumbnails, node?.thumbnail, node?.thumbnail_renderer?.thumbnails,
    node?.thumbnail_renderer?.thumbnail, node?.author?.thumbnails, node?.channel_thumbnail,
    node?.content_image?.primary_thumbnail?.image,
    node?.content_image?.primary_thumbnail?.image?.sources,
    node?.content_image?.image, node?.content_image?.image?.sources,
    node?.content_image?.sources, node?.banner?.thumbnails, node?.banner?.thumbnail,
    node?.metadata?.image?.avatar?.image, node?.metadata?.image?.avatar?.image?.sources,
    node?.metadata?.image, node?.metadata?.image?.sources
  ];
  for (const candidate of candidates) {
    const choices = thumbnails(candidate);
    if (choices.length) return choices.at(-1)?.url ?? null;
  }
  return null;
};

const durationSeconds = node => {
  const direct = node?.duration?.seconds ?? node?.duration_seconds ?? node?.length_seconds;
  if (Number.isFinite(Number(direct))) return Number(direct);
  const label = text(node?.duration?.text ?? node?.duration);
  if (!/^\d+(?::\d+){1,2}$/.test(label)) return null;
  return label.split(':').reduce((total, part) => total * 60 + Number(part), 0);
};

const countNumber = value => {
  if (value == null || value === '') return null;
  if (Number.isFinite(Number(value))) return Math.max(0, Math.trunc(Number(value)));
  const rendered = text(value).trim().toLowerCase();
  if (!rendered) return null;
  const exact = rendered.replace(/[,\s]/g, '').match(/^(\d+)(?:views?)?$/);
  if (exact) return Number(exact[1]);
  const abbreviated = rendered.replace(',', '.').match(/(\d+(?:\.\d+)?)\s*([kmb])/);
  if (!abbreviated) return null;
  const scale = { k: 1e3, m: 1e6, b: 1e9 }[abbreviated[2]];
  return Math.round(Number(abbreviated[1]) * scale);
};

const viewCount = node => {
  for (const candidate of [node?.view_count, node?.views, node?.short_view_count]) {
    const count = countNumber(candidate);
    if (count !== null) return count;
  }
  return null;
};

const typeName = node => String(node?.type ?? node?.constructor?.name ?? '').toLowerCase();

function normalizeNode(node, source, requestedKind = null) {
  if (!node || typeof node !== 'object') return null;
  const type = typeName(node);
  const lockupType = String(node.content_type ?? '').toLowerCase();
  const itemType = String(node.item_type ?? '').toLowerCase();
  const contentId = node.content_id ?? null;
  const videoId = node.video_id ?? node.id?.video_id ?? node.endpoint?.payload?.videoId ??
    (['video', 'song', 'non_music_track'].includes(itemType) ? node.id : null) ??
    (['video', 'short'].includes(lockupType) ? contentId : null);
  const playlistId = node.playlist_id ?? node.id?.playlist_id ?? node.endpoint?.payload?.playlistId ??
    (itemType === 'playlist' ? node.id : null) ?? (playlistType(lockupType) ? contentId : null);
  const channelId = node.channel_id ?? node.author?.id ?? node.owner?.id ??
    node.artists?.[0]?.channel_id ?? node.authors?.[0]?.channel_id ??
    node.endpoint?.payload?.browseId ?? (itemType === 'artist' ? node.id : null) ??
    (lockupType === 'channel' ? contentId : null);
  const browseId = node.browse_id ?? node.id ?? node.endpoint?.payload?.browseId ?? contentId ?? null;
  const title = text(node.title ?? node.name ?? node.author?.name ?? node.header?.title ?? node.metadata?.title);
  const metadataText = text(node.metadata?.metadata);
  const author = text(node.author?.name ?? node.author ?? node.owner?.name ??
    node.artists?.[0]?.name ?? node.authors?.[0]?.name ?? node.subtitle) ||
    metadataText.split('·')[0]?.trim() || '';
  const authorId = node.author?.id ?? node.owner?.id ?? node.artists?.[0]?.channel_id ?? node.authors?.[0]?.channel_id ?? null;
  function playlistType(value) { return value === 'playlist' || value === 'album'; }

  if (videoId || type.includes('video') || type.includes('song') || ['video', 'short'].includes(lockupType)) {
    if (!videoId || !title) return null;
    return {
      kind: source === 'music' && (requestedKind === 'song' || type.includes('song')) ? 'song' : 'video',
      videoId: String(videoId), source, title, author: author || 'Автор неизвестен',
      authorId: authorId ? String(authorId) : null,
      duration: durationSeconds(node),
      thumbnailUrl: bestThumbnail(node) ?? `https://i.ytimg.com/vi/${encodeURIComponent(videoId)}/hqdefault.jpg`,
      canonicalUrl: `https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`,
      viewCount: viewCount(node),
      likeCount: countNumber(node?.like_count ?? node?.likes),
      unavailable: Boolean(node.is_unavailable ?? node.unplayable)
    };
  }
  if (playlistId || type.includes('playlist') || playlistType(lockupType)) {
    const id = playlistId ?? browseId;
    if (!id || !title) return null;
    return { kind: 'playlist', id: String(id), source, title, author: author || '',
      thumbnailUrl: bestThumbnail(node), canonicalUrl: `https://www.youtube.com/playlist?list=${encodeURIComponent(id)}` };
  }
  if (type.includes('channel') || type.includes('artist') || lockupType === 'channel' || (browseId && requestedKind && ['channel', 'artist'].includes(requestedKind))) {
    const kind = source === 'music' || type.includes('artist') ? 'artist' : 'channel';
    const id = channelId ?? browseId;
    if (!id || !title) return null;
    return { kind, id: String(id), source, title, author: '', thumbnailUrl: bestThumbnail(node),
      canonicalUrl: kind === 'channel' ? `https://www.youtube.com/channel/${encodeURIComponent(id)}` : null };
  }
  return null;
}

function contentRows(page) {
  const candidates = [page?.results, page?.contents, page?.contents?.contents, page?.videos, page?.items,
    page?.page?.contents, page?.content?.contents, page?.header?.contents];
  for (const rows of candidates) if (Array.isArray(rows)) return rows;
  return [];
}
function expandRows(rows, depth = 0) {
  if (depth > 4) return [];
  const expanded = [];
  for (const node of rows) {
    expanded.push(node);
    for (const nested of [node?.contents, node?.items, node?.results]) {
      if (Array.isArray(nested)) expanded.push(...expandRows(nested, depth + 1));
    }
  }
  return expanded;
}

function normalizeRows(page, source, kind, preserveDuplicates = false) {
  const items = [];
  const seen = new Set();
  for (const node of expandRows(contentRows(page))) {
    const item = normalizeNode(node, source, kind);
    if (!item) continue;
    const key = item.videoId ? `${item.kind}:${item.videoId}` : `${item.kind}:${item.id}`;
    if (!preserveDuplicates && seen.has(key)) continue;
    seen.add(key);
    items.push(item);
  }
  return items;
}

function hasContinuation(page) {
  if (typeof page?.has_continuation === 'boolean') return page.has_continuation;
  if (typeof page?.has_continuation === 'function') return Boolean(page.has_continuation());
  return typeof page?.getContinuation === 'function';
}

function storeCursor(page, context) {
  if (!hasContinuation(page)) return null;
  const cursor = randomUUID();
  cursors.set(cursor, { page, context, touched: Date.now(), inFlight: null, lastResult: null });
  pruneCursors();
  return cursor;
}

function pruneCursors() {
  const now = Date.now();
  for (const [id, state] of cursors) if (!state.inFlight && now - state.touched > CURSOR_TTL_MS) cursors.delete(id);
  const idle = [...cursors.entries()].filter(([, state]) => !state.inFlight).sort((a, b) => a[1].touched - b[1].touched);
  while (idle.length > MAX_IDLE_CURSORS) cursors.delete(idle.shift()[0]);
}

function pageResult(page, context, cursor = null) {
  const items = normalizeRows(page, context.source, context.kind, context.preserveDuplicates);
  const nextCursor = cursor ?? storeCursor(page, context);
  return { items, nextCursor, exhausted: !nextCursor };
}

async function ensureClient() {
  if (client) return client;
  if (!clientPromise) {
    clientPromise = Innertube.create({
      lang: 'en', location: 'US', retrieve_player: false, cache: new UniversalCache(false)
    }).then(instance => {
      client = instance;
      return instance;
    });
  }
  try {
    return await clientPromise;
  } finally {
    if (!client) clientPromise = null;
  }
}

async function search({ source, kind, query }) {
  if (!['youtube', 'music'].includes(source)) throw new ProviderError('invalid_request', 'Неизвестный источник каталога');
  if (typeof query !== 'string' || !query.trim()) throw new ProviderError('invalid_request', 'Введите поисковый запрос');
  const yt = await ensureClient();
  if (kind === 'all') {
    const kinds = source === 'youtube' ? ['video', 'playlist', 'channel'] : ['song', 'video', 'playlist', 'artist'];
    const pages = await Promise.all(kinds.map(typedKind => search({ source, kind: typedKind, query })));
    return { sections: Object.fromEntries(kinds.map((typedKind, index) => [typedKind, pages[index]])) };
  }
  const allowed = source === 'youtube' ? ['video', 'playlist', 'channel'] : ['song', 'video', 'playlist', 'artist'];
  if (!allowed.includes(kind)) throw new ProviderError('invalid_request', 'Неподдерживаемый фильтр поиска');
  const page = source === 'youtube'
    ? await yt.search(query.trim(), { type: kind })
    : await yt.music.search(query.trim(), { type: kind });
  return pageResult(page, { source, kind, query: query.trim(), preserveDuplicates: false });
}

async function next({ cursor }) {
  const state = cursors.get(cursor);
  if (!state) throw new ProviderError('cursor_expired', 'Страница устарела; обновите выдачу');
  state.touched = Date.now();
  if (state.inFlight) return state.inFlight;
  state.inFlight = (async () => {
    try {
      if (typeof state.page.getContinuation !== 'function') {
        cursors.delete(cursor);
        return { items: [], nextCursor: null, exhausted: true };
      }
      const page = await state.page.getContinuation();
      state.page = page;
      const result = pageResult(page, state.context, hasContinuation(page) ? cursor : null);
      if (!result.nextCursor) cursors.delete(cursor);
      state.lastResult = result;
      return result;
    } finally {
      state.inFlight = null;
    }
  })();
  return state.inFlight;
}

async function open({ entity }) {
  if (!entity || !['youtube', 'music'].includes(entity.source)) throw new ProviderError('invalid_request', 'Некорректная сущность каталога');
  const yt = await ensureClient();
  let page;
  if (entity.kind === 'playlist') {
    page = entity.source === 'music' ? await yt.music.getPlaylist(entity.id) : await yt.getPlaylist(entity.id);
  } else if (entity.kind === 'artist' && entity.source === 'music') {
    page = await yt.music.getArtist(entity.id);
  } else if (entity.kind === 'channel' && entity.source === 'youtube') {
    page = await yt.getChannel(entity.id);
  } else {
    throw new ProviderError('invalid_request', 'Тип страницы не поддерживается');
  }
  const header = normalizeNode(page?.header ?? page?.metadata ?? entity, entity.source, entity.kind) ?? entity;
  if (entity.kind === 'playlist') {
    const context = { source: entity.source, kind: entity.source === 'music' ? 'song' : 'video', preserveDuplicates: true };
    const result = pageResult(page, context);
    const resolvedHeader = header.thumbnailUrl || !result.items[0]?.thumbnailUrl
      ? header : { ...header, thumbnailUrl: result.items[0].thumbnailUrl };
    return { entity: resolvedHeader, ...result };
  }
  const sections = {};
  if (entity.kind === 'channel') {
    const tabs = [
      ['videos', 'has_videos', 'getVideos', 'video'],
      ['shorts', 'has_shorts', 'getShorts', 'video'],
      ['live', 'has_live_streams', 'getLiveStreams', 'video'],
      ['playlists', 'has_playlists', 'getPlaylists', 'playlist']
    ];
    for (const [name, available, getter, kind] of tabs) {
      if (!page[available] || typeof page[getter] !== 'function') continue;
      try {
        const tab = await page[getter]();
        sections[name] = pageResult(tab, { source: 'youtube', kind, preserveDuplicates: false });
      } catch {
        sections[name] = { items: [], nextCursor: null, exhausted: true,
          error: { code: 'provider_error', message: 'Раздел канала временно недоступен' } };
      }
    }
  } else {
    for (const shelf of page.sections ?? []) {
      const label = text(shelf.title) || `section-${Object.keys(sections).length + 1}`;
      const rows = shelf.contents ?? [];
      const items = normalizeRows({ contents: rows }, 'music', null, false);
      if (items.length) sections[label] = { items, nextCursor: null, exhausted: true };
    }
  }
  return { entity: header, sections, items: [], nextCursor: null, exhausted: true };
}

async function suggestions({ source, query }) {
  if (!['youtube', 'music'].includes(source) || typeof query !== 'string' || query.trim().length < 2) return { items: [] };
  const yt = await ensureClient();
  const clientForSource = source === 'music' ? yt.music : yt;
  const result = await clientForSource.getSearchSuggestions(query.trim());
  return { items: (result ?? []).map(text).filter(Boolean).slice(0, 10) };
}

async function dispatch(method, params) {
  pruneCursors();
  if (method === 'ping') return { ready: Boolean(await ensureClient()), version: '18.0.0' };
  if (method === 'search') return search(params);
  if (method === 'next') return next(params);
  if (method === 'open') return open(params);
  if (method === 'suggestions') return suggestions(params);
  if (method === 'release') return { released: cursors.delete(params.cursor) };
  throw new ProviderError('invalid_request', 'Неизвестный метод каталога');
}
function publicError(error) {
  if (error instanceof ProviderError) return { code: error.code, message: error.message };
  const details = `${error?.message ?? ''} ${error?.cause?.message ?? ''} ${error?.cause?.code ?? ''}`.toLowerCase();
  if (details.includes('fetch failed') || details.includes('timeout') || details.includes('econn')
      || details.includes('network') || details.includes('dns')) {
    return { code: 'network_error', message: 'Нет связи с каталогом YouTube' };
  }
  if (details.includes('sign in') || details.includes('authentication') || details.includes('login')) {
    return { code: 'unavailable', message: 'YouTube требует авторизацию для этого содержимого' };
  }
  return { code: 'provider_error', message: 'Формат ответа YouTube не поддерживается' };
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('line', async line => {
  if (Buffer.byteLength(line) > MAX_LINE) {
    process.stdout.write(`${JSON.stringify({ id: null, ok: false, error: { code: 'invalid_request', message: 'Ответ превышает допустимый размер' } })}\n`);
    return;
  }
  let request;
  try {
    request = JSON.parse(line);
    const result = await dispatch(request.method, request.params ?? {});
    const response = JSON.stringify({ id: request.id, ok: true, result });
    if (Buffer.byteLength(response) > MAX_LINE) throw new ProviderError('provider_error', 'Ответ каталога слишком велик');
    process.stdout.write(`${response}\n`);
  } catch (error) {
    const failure = publicError(error);
    process.stdout.write(`${JSON.stringify({ id: request?.id ?? null, ok: false, error: failure })}\n`);
    console.error(`[catalog] ${error?.stack ?? error}`);
  }
});

process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT', () => process.exit(0));
