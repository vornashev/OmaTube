#!/usr/bin/env node
import { readFile, writeFile } from 'node:fs/promises';

const path = new URL('../node_modules/youtubei.js/dist/src/parser/youtube/Search.js', import.meta.url);
const source = await readFile(path, 'utf8');
const broken = 'this.page.on_response_received_commands.as(ReloadContinuationItemsCommand).find(';
const fixed = 'this.page.on_response_received_commands.filter((command) => command.is(ReloadContinuationItemsCommand)).find(';
if (source.includes(fixed)) process.exit(0);
if (!source.includes(broken)) throw new Error('youtubei.js Search parser changed; review continuation patch');
await writeFile(path, source.replace(broken, fixed));
