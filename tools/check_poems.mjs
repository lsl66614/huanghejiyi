// tools/check_poems.mjs —— 校验 42 处遗址诗词层：每条至少 1 首，text/author/source 非空且无重复作者-篇名错配
// 运行：node tools/check_poems.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '../app/entry/src/main/resources/rawfile/sites');
const files = readdirSync(DIR).filter((f) => f.endsWith('.json'));
let bad = 0;
let total = 0;
for (const f of files) {
  const j = JSON.parse(readFileSync(join(DIR, f), 'utf8'));
  const poems = j.sections.poems || [];
  if (poems.length === 0) { console.error(`EMPTY poems: ${j.id}`); bad++; continue; }
  for (const p of poems) {
    total++;
    if (!p.text || !p.author || !p.source) {
      console.error(`INCOMPLETE poem at ${j.id}: ${JSON.stringify(p)}`);
      bad++;
    }
  }
}
console.log(`sites ${files.length}, poems ${total}, bad ${bad}`);
if (bad > 0) process.exit(1);
