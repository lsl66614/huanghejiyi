# 黄河记忆 · 核心代码层（地基层）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已建好的 API 26 工程骨架上实现数据模型、MergeEngine 合并算法、RDB 仓储、Loopback 传输仿真与内容数据校验流水线，使后续 UI 九屏计划可以直接调用领域层。

**Architecture:** 三层落位（设计方案 §3）：model（纯类型）→ service（MergeEngine/SyncScheduler 纯函数，可被 Node 直接跑单测）→ repository（IDataRepository/ITransport 接口 + LocalRdbImpl/LoopbackAdapter 实现）。同步域 = favorite/note/note_tag/tag/progress 五表，LWW-Element-Set 语义（§6.2）。

**Tech Stack:** ArkTS（Stage 模型）、@ohos.data.relationalStore、hvigor（经 `build-oh.bat` shim）、Node 24（type-stripping 跑 .ets 派生 .ts 单测）、Python 3（内容校验）。

**Spec:** `E:\ .stepclaw\huanghe-memory\设计方案.md`（v1.0，本计划实现其 §3/§4.3/§6/§7 的数据与领域部分；§4.1/§4.2/§4.5/§4.6/§5 的 UI 属下一份计划）

## Global Constraints

- SDK：OpenHarmony API 26；`build-profile.json5` 已含 `compileSdkVersion/targetSdkVersion/compatibleSdkVersion = "26.0.0"`、`runtimeOS: "OpenHarmony"`；`module.json5` deviceTypes 为 `["default"]`。不得改回 HarmonyOS。
- 构建命令一律用 `E:\ .stepclaw\huanghe-memory\app\build-oh.bat`（内部走 `E:\hvigor_shim\bin\hvigorw.js`；直接跑 `devecocli build` 必挂，原因见记忆 deveco-toolchain-integration）。cwd 必须在 `app\`。
- **纯函数文件**（model/、service/merge、service/sync、service/content 的 parse、repository 的接口与 LoopbackAdapter）**禁止 import 任何 `@kit.*`**，必须能被 Node 24 type-stripping 直接执行（无 enum、无 namespace、无装饰器、无 `Resource` 类型）。
- 匿名评审：任何新建文件不得出现学校、师生姓名；内容 JSON 的 `source` 字段仅存于 `tools/` 母本，进 rawfile 前由 validate_sites.py 剥离。
- DDL 逐字采用设计方案 §6.1（见本计划 Task 3 代码块）。
- 冲突策略逐字采用 §6.2：`updateTime` 大者胜；相等取 `deviceId` 字典序大者；墓碑按时间戳参与裁决；冲突历史滚动上限 50 条。
- 年代色板（§7.2）：仰韶 `#9C4A2F`｜龙山 `#3B3531`｜夏商 `#5C7153`｜周 `#7A8B8F`｜汉唐 `#B98A44`｜宋 `#77909E`；底 `#F5F1E8`、字墨色。
- 提交规范：`feat(huanghe-memory): …` / `test(huanghe-memory): …`，每个 Task 结束提交一次。

---

### Task 0: Git 基线与分支

**Files:**
- Modify: `huanghe-memory/设计方案.md`（§2 表格 API 口径行）

**Interfaces:**
- Produces: 分支 `feat/huanghe-foundation`，首个提交包含工程骨架 + 设计方案 v1.0

- [ ] **Step 1: 摸清 git 现状**

```bash
cd "E:\ .stepclaw" && git status --porcelain -- huanghe-memory | head -20 && git log --oneline -3 -- huanghe-memory
```
预期：huanghe-memory 大多为 untracked（骨架、设计方案）。若 `app/entry/build`、`oh_modules`、`.hvigor` 出现在 untracked 列表，先确认 `app/.gitignore`（模板自带）已覆盖；未覆盖则在 `huanghe-memory/.gitignore` 追加：
```
app/entry/build/
app/build/
app/oh_modules/
app/.hvigor/
app/.cxx/
```

- [ ] **Step 2: 从 master 开分支（untracked 文件会跟随 checkout）**

```bash
cd "E:\ .stepclaw" && git checkout -b feat/huanghe-foundation master
```
若报 `already used by worktree`，改用 `feat/huanghe-foundation-2` 并在执行日志中记录。

- [ ] **Step 3: 更新设计方案 API 口径**

把 §2 表中两行：
`| 开发工具 | DevEco Studio 5.0.x（当前稳定版） | 赛题统一要求 |` → `| 开发工具 | DevEco Studio 26.0.0.821 | 赛题统一要求 |`
`| 系统/SDK | OpenHarmony 5.0 Release，**API 12 及以上** | 赛题要求 |` → `| 系统/SDK | OpenHarmony 26.0.0（API 26，26.0.0.38），满足 API≥12 | 赛题要求；开源鸿蒙最新正式版 |`
§5.5 运行环境行的 `（API 12+ 镜像）` → `（API 26 镜像）`。

- [ ] **Step 4: 提交基线**

```bash
cd "E:\ .stepclaw" && git add huanghe-memory && git commit -m "chore(huanghe-memory): API26 工程骨架与设计方案基线" && git log --oneline -1
```
预期：`huanghe-memory/` 全部跟踪，工作树对该目录干净。

---

### Task 1: 模型层 + 年代主题常量

**Files:**
- Create: `app/entry/src/main/ets/model/SyncModels.ets`
- Create: `app/entry/src/main/ets/model/UserDataModels.ets`
- Create: `app/entry/src/main/ets/model/ContentModels.ets`
- Create: `app/entry/src/main/ets/common/EraTheme.ets`
- Test: 编译门（无设备时唯一可行测试）+ Node 可加载性由 Task 2 harness 覆盖

**Interfaces:**
- Produces: `SyncRecord`、`ConflictVersion`、`ConflictEntry`、`MergeResult`、`SYNC_TABLES`、`FavoriteDO`、`NoteDO`、`TagDO`、`ProgressDO`、`SiteInfo`、`RelicInfo`、`PoemRef`、`Era`、`City`、`SiteType`、`ERAS/CITIES/SITE_TYPES` 枚举数组、`eraColor(era: string): string` —— 后续所有 Task 按这些名字引用。

- [ ] **Step 1: 写 SyncModels.ets**

```ts
// entry/src/main/ets/model/SyncModels.ets —— 纯类型，禁止 @kit 导入
export interface SyncRecord {
  key: string;
  updateTime: number;
  deviceId: string;
  isDeleted: boolean;
  payload: Record<string, string | number | boolean>;
}

export interface ConflictVersion {
  updateTime: number;
  deviceId: string;
  isDeleted: boolean;
  payload: Record<string, string | number | boolean>;
}

export interface ConflictEntry {
  key: string;
  winner: ConflictVersion;
  loser: ConflictVersion;
  reason: string; // 'updateTime' | 'tie_break_deviceId'
}

export interface MergeResult {
  finalRecords: SyncRecord[];
  conflicts: ConflictEntry[];
}

export const SYNC_TABLES: string[] = ['favorite', 'note', 'note_tag', 'tag', 'progress'];
```

- [ ] **Step 2: 写 UserDataModels.ets**

```ts
// entry/src/main/ets/model/UserDataModels.ets
export class FavoriteDO {
  targetKey: string = '';   // 'site:{id}' | 'relic:{id}'
  createTime: number = 0;
  updateTime: number = 0;
  deviceId: string = '';
  isDeleted: boolean = false;
}

export class NoteDO {
  noteId: string = '';
  targetKey: string = '';   // 'site:{id}:intro' | 'site:{id}' | 'relic:{id}' …
  text: string = '';
  createTime: number = 0;
  updateTime: number = 0;
  deviceId: string = '';
  isDeleted: boolean = false;
}

export class TagDO {
  tagId: string = '';
  name: string = '';
  isPreset: boolean = false;
  updateTime: number = 0;
  isDeleted: boolean = false;
}

export class ProgressDO {
  targetKey: string = '';
  section: string = '';     // 'intro'|'arch'|'events'|'poems'|'tourism'
  done: boolean = false;
  updateTime: number = 0;
  deviceId: string = '';
}

export const PRESET_TAGS: string[] = ['待实地探访', '已去过', '研究资料'];
export const SECTIONS: string[] = ['intro', 'arch', 'events', 'poems', 'tourism'];
```

- [ ] **Step 3: 写 ContentModels.ets**

```ts
// entry/src/main/ets/model/ContentModels.ets
export const ERAS: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
export const CITIES: string[] = ['sanmenxia', 'luoyang', 'zhengzhou', 'kaifeng', 'puyang'];
export const SITE_TYPES: string[] = ['capital', 'burial', 'kiln', 'ancient_arch'];

export class PoemRef {
  text: string = '';
  author: string = '';
  source: string = '';
}

export class RelicInfo {
  id: string = '';
  siteId: string = '';
  name: string = '';
  era: string = '';
  summary: string = '';
  material: string = '';
  images: string[] = [];
}

export class SiteInfo {
  id: string = '';
  name: string = '';
  city: string = '';
  era: string = '';
  siteType: string = '';
  summary: string = '';
  tags: string[] = [];
  intro: string = '';
  archaeology: string = '';
  events: string = '';
  poems: PoemRef[] = [];
  tourism: string = '';
  images: string[] = [];
  relics: RelicInfo[] = [];
}
```

- [ ] **Step 4: 写 EraTheme.ets（色值逐字取自 §7.2）**

```ts
// entry/src/main/ets/common/EraTheme.ets
const ERA_COLORS: Map<string, string> = new Map([
  ['yangshao', '#9C4A2F'],
  ['longshan', '#3B3531'],
  ['xiashang', '#5C7153'],
  ['zhou', '#7A8B8F'],
  ['hantang', '#B98A44'],
  ['song', '#77909E']
]);

const ERA_NAMES: Map<string, string> = new Map([
  ['yangshao', '仰韶'], ['longshan', '龙山'], ['xiashang', '夏商'],
  ['zhou', '周'], ['hantang', '汉唐'], ['song', '宋']
]);

export function eraColor(era: string): string {
  const c = ERA_COLORS.get(era);
  return c !== undefined ? c : '#3B3531';
}

export function eraName(era: string): string {
  const n = ERA_NAMES.get(era);
  return n !== undefined ? n : era;
}

export const THEME_BG: string = '#F5F1E8';
export const THEME_INK: string = '#2B2622';
```

- [ ] **Step 5: 编译门**

Run: `cd "E:\ .stepclaw\huanghe-memory\app" && ./build-oh.bat`
Expected: `BUILD SUCCESSFUL`（ArkTS 编译对 4 个新文件零报错；若 ArkTS lint 报 `arkts-no-…` 规则，按报错改语法，不得引入 any）

- [ ] **Step 6: Commit**

```bash
cd "E:\ .stepclaw" && git add huanghe-memory/app/entry/src/main/ets && git commit -m "feat(huanghe-memory): 数据模型层与年代主题色板"
```

---

### Task 2: MergeEngine 纯函数 + Node 本地单测（TDD）

**Files:**
- Create: `tools/merge-tests/run.mjs`（.ets→.ts 构建 harness）
- Create: `tools/merge-tests/merge_engine.test.mjs`
- Create: `app/entry/src/main/ets/service/merge/MergeEngine.ets`

**Interfaces:**
- Consumes: Task 1 的 `SyncRecord/ConflictEntry/MergeResult`
- Produces: `mergeElementSets(local: SyncRecord[], remote: SyncRecord[]): MergeResult`、`appendConflictLog(existingJson: string, entries: ConflictEntry[], cap: number): string` —— Task 3 SyncScheduler 依赖。

- [ ] **Step 1: 写 harness run.mjs**

```js
// tools/merge-tests/run.mjs —— 把纯函数 .ets 复制为 .ts 并补全导入扩展名，供 Node 24 type-stripping 执行
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..'); // huanghe-memory/app
const SRC = join(ROOT, 'entry/src/main/ets');
const OUT = join(ROOT, 'tools/.tsbuild');
const FILES = [
  'model/SyncModels.ets',
  'model/UserDataModels.ets',
  'model/ContentModels.ets',
  'service/merge/MergeEngine.ets',
  'service/sync/SyncScheduler.ets',
  'repository/IDataRepository.ets',
  'repository/ITransport.ets',
  'repository/LoopbackAdapter.ets',
  'service/content/ContentParse.ets',
];

rmSync(OUT, { recursive: true, force: true });
for (const f of FILES) {
  let code = readFileSync(join(SRC, f), 'utf8');
  // 相对导入无扩展名 → 补 .ts（Node ESM 要求显式扩展名）
  code = code.replace(/from '(\.\.?\/[^']+)'/g, (mm, spec) => {
    if (/\.(ts|js|json)$/.test(spec)) return mm;
    return `from '${spec}.ts'`;
  });
  const dest = join(OUT, f.replace(/\.ets$/, '.ts'));
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, code);
}
console.log('tsbuild ready:', OUT);
```

- [ ] **Step 2: 写失败测试（7 个用例，逐条对应 §6.2）**

```js
// tools/merge-tests/merge_engine.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeElementSets, appendConflictLog } from '../.tsbuild/service/merge/MergeEngine.ts';

const rec = (key, t, dev, del = false, extra = {}) => ({
  key, updateTime: t, deviceId: dev, isDeleted: del, payload: extra,
});

test('单方有 → 直接纳入', () => {
  const r = mergeElementSets([rec('a', 1, 'A')], [rec('b', 1, 'B')]);
  assert.deepEqual(r.finalRecords.map((x) => x.key).sort(), ['a', 'b']);
  assert.equal(r.conflicts.length, 0);
});

test('双方均有 → updateTime 大者胜，记冲突', () => {
  const r = mergeElementSets([rec('a', 1, 'A', false, { v: 'old' })], [rec('a', 2, 'B', false, { v: 'new' })]);
  assert.equal(r.finalRecords.length, 1);
  assert.equal(r.finalRecords[0].payload.v, 'new');
  assert.equal(r.conflicts.length, 1);
  assert.equal(r.conflicts[0].loser.payload.v, 'old');
  assert.equal(r.conflicts[0].reason, 'updateTime');
});

test('时间戳相等 → deviceId 字典序大者胜，reason=tie_break_deviceId', () => {
  const r = mergeElementSets([rec('a', 5, 'deviceA')], [rec('a', 5, 'deviceB')]);
  assert.equal(r.finalRecords[0].deviceId, 'deviceB');
  assert.equal(r.conflicts[0].reason, 'tie_break_deviceId');
});

test('完全相同记录（同 deviceId 同时间同墓碑态）→ 无冲突', () => {
  const r = mergeElementSets([rec('a', 5, 'A')], [rec('a', 5, 'A')]);
  assert.equal(r.conflicts.length, 0);
  assert.equal(r.finalRecords.length, 1);
});

test('墓碑 vs 存活 → 仍按时间戳裁决（删除是最后一次编辑）', () => {
  const r = mergeElementSets([rec('a', 3, 'A', false)], [rec('a', 4, 'B', true)]);
  assert.equal(r.finalRecords[0].isDeleted, true);
  const r2 = mergeElementSets([rec('a', 9, 'A', false)], [rec('a', 4, 'B', true)]);
  assert.equal(r2.finalRecords[0].isDeleted, false);
});

test('输出按 key 字典序确定排列', () => {
  const r = mergeElementSets([rec('z', 1, 'A'), rec('a', 1, 'A')], [rec('m', 1, 'B')]);
  assert.deepEqual(r.finalRecords.map((x) => x.key), ['a', 'm', 'z']);
});

test('appendConflictLog 滚动上限 50，新条目在尾部', () => {
  const e = (k) => ({ key: k, winner: rec(k, 2, 'B'), loser: rec(k, 1, 'A'), reason: 'updateTime' });
  let json = '[]';
  for (let i = 0; i < 60; i++) json = appendConflictLog(json, [e('k' + i)], 50);
  const log = JSON.parse(json);
  assert.equal(log.length, 50);
  assert.equal(log[49].key, 'k59');
  assert.equal(log[0].key, 'k10');
});

test('appendConflictLog 容忍空/坏 existingJson', () => {
  const one = [{ key: 'x', winner: rec('x', 2, 'B'), loser: rec('x', 1, 'A'), reason: 'updateTime' }];
  assert.equal(JSON.parse(appendConflictLog('', one, 50)).length, 1);
  assert.equal(JSON.parse(appendConflictLog('not-json', one, 50)).length, 1);
});
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd "E:\ .stepclaw\huanghe-memory" && node tools/merge-tests/run.mjs && node --test tools/merge-tests/`
Expected: FAIL —— `Cannot find module .../MergeEngine.ts`（文件还不存在）

- [ ] **Step 4: 实现 MergeEngine.ets**

```ts
// entry/src/main/ets/service/merge/MergeEngine.ets —— 纯函数，禁 @kit
import { SyncRecord, ConflictVersion, ConflictEntry, MergeResult } from '../../model/SyncModels';

function toVersion(r: SyncRecord): ConflictVersion {
  const v: ConflictVersion = {
    updateTime: r.updateTime, deviceId: r.deviceId,
    isDeleted: r.isDeleted, payload: r.payload
  };
  return v;
}

export function mergeElementSets(local: SyncRecord[], remote: SyncRecord[]): MergeResult {
  const localMap: Map<string, SyncRecord> = new Map();
  for (const r of local) { localMap.set(r.key, r); }
  const remoteMap: Map<string, SyncRecord> = new Map();
  for (const r of remote) { remoteMap.set(r.key, r); }
  const finals: SyncRecord[] = [];
  const conflicts: ConflictEntry[] = [];
  const keys: Set<string> = new Set();
  localMap.forEach((_v: SyncRecord, k: string) => { keys.add(k); });
  remoteMap.forEach((_v: SyncRecord, k: string) => { keys.add(k); });
  keys.forEach((k: string) => {
    const a: SyncRecord | undefined = localMap.get(k);
    const b: SyncRecord | undefined = remoteMap.get(k);
    if (a !== undefined && b === undefined) { finals.push(a); return; }
    if (b !== undefined && a === undefined) { finals.push(b); return; }
    if (a === undefined || b === undefined) { return; }
    if (a.updateTime === b.updateTime && a.deviceId === b.deviceId && a.isDeleted === b.isDeleted) {
      finals.push(a); return;
    }
    let winner: SyncRecord = a;
    let reason: string = 'updateTime';
    if (a.updateTime === b.updateTime) {
      winner = a.deviceId > b.deviceId ? a : b;
      reason = 'tie_break_deviceId';
    } else {
      winner = a.updateTime > b.updateTime ? a : b;
    }
    const loser: SyncRecord = winner === a ? b : a;
    finals.push(winner);
    const entry: ConflictEntry = { key: k, winner: toVersion(winner), loser: toVersion(loser), reason: reason };
    conflicts.push(entry);
  });
  finals.sort((m: SyncRecord, n: SyncRecord): number => m.key < n.key ? -1 : (m.key > n.key ? 1 : 0));
  const result: MergeResult = { finalRecords: finals, conflicts: conflicts };
  return result;
}

export function appendConflictLog(existingJson: string, entries: ConflictEntry[], cap: number): string {
  let log: ConflictEntry[] = [];
  try {
    const parsed: ConflictEntry[] | null = JSON.parse(existingJson) as ConflictEntry[] | null;
    if (parsed !== null) { log = parsed; }
  } catch (e) {
    log = [];
  }
  for (const x of entries) { log.push(x); }
  if (log.length > cap) { log = log.slice(log.length - cap); }
  return JSON.stringify(log);
}
```

- [ ] **Step 5: 跑测试确认全绿**

Run: `node tools/merge-tests/run.mjs && node --test tools/merge-tests/`
Expected: `pass 8 / fail 0`

- [ ] **Step 6: 编译门**

Run: `cd "E:\ .stepclaw\huanghe-memory\app" && ./build-oh.bat` → `BUILD SUCCESSFUL`

- [ ] **Step 7: Commit**

```bash
cd "E:\ .stepclaw" && git add huanghe-memory/app/entry/src/main/ets/service/merge huanghe-memory/tools && git commit -m "feat(huanghe-memory): MergeEngine LWW 合并纯函数与 Node 单测(8例)"
```

---

### Task 3: 仓储接口 + LocalRdbImpl(DDL) + LoopbackAdapter + SyncScheduler

**Files:**
- Create: `app/entry/src/main/ets/repository/IDataRepository.ets`
- Create: `app/entry/src/main/ets/repository/ITransport.ets`
- Create: `app/entry/src/main/ets/repository/LocalRdbImpl.ets`
- Create: `app/entry/src/main/ets/repository/LoopbackAdapter.ets`
- Create: `app/entry/src/main/ets/service/sync/SyncScheduler.ets`
- Create: `tools/merge-tests/scheduler.test.mjs`

**Interfaces:**
- Consumes: Task 2 `mergeElementSets/appendConflictLog`、Task 1 模型
- Produces: `IDataRepository`、`ITransport`、`runSync(deviceId, repo, transport, onProgress?): Promise<ConflictEntry[]>`、`LocalRdbImpl`（单例式 class）、`LoopbackAdapter` —— UI 计划与同步面板将按此调用。

- [ ] **Step 1: 写接口（纯类型，进 harness FILES 已在 Task 2 列好）**

```ts
// entry/src/main/ets/repository/ITransport.ets
import { SyncRecord } from '../model/SyncModels';

export interface ITransport {
  // 返回对端（或对方设备档案）的五表快照
  exchange(deviceId: string, local: Map<string, SyncRecord[]>): Promise<Map<string, SyncRecord[]>>;
  // 合并完成后回写，使下一轮对端能看到本轮终态（收敛语义）
  notifyAfterSync(deviceId: string, finalTables: Map<string, SyncRecord[]>): Promise<void>;
}
```

```ts
// entry/src/main/ets/repository/IDataRepository.ets
import { SyncRecord } from '../model/SyncModels';
import { FavoriteDO, NoteDO, TagDO, ProgressDO } from '../model/UserDataModels';

export interface IDataRepository {
  init(context: ESObject): Promise<void>;
  snapshotSyncTables(): Promise<Map<string, SyncRecord[]>>;
  applyMerged(table: string, records: SyncRecord[]): Promise<void>;
  getMeta(key: string): Promise<string>;
  setMeta(key: string, value: string): Promise<void>;
  upsertFavorite(fav: FavoriteDO): Promise<void>;
  deleteFavorite(targetKey: string, deviceId: string, now: number): Promise<void>;
  upsertNote(note: NoteDO): Promise<void>;
  setNoteTags(noteId: string, tagIds: string[], now: number, deviceId: string): Promise<void>;
  upsertTag(tag: TagDO): Promise<void>;
  upsertProgress(p: ProgressDO): Promise<void>;
}
```

- [ ] **Step 2: 写 LoopbackAdapter（纯函数级，可进 Node 测试）**

```ts
// entry/src/main/ets/repository/LoopbackAdapter.ets —— 单机双档案仿真，禁 @kit
import { SyncRecord } from '../model/SyncModels';
import { ITransport } from './ITransport';

function cloneTables(t: Map<string, SyncRecord[]>): Map<string, SyncRecord[]> {
  const out: Map<string, SyncRecord[]> = new Map();
  t.forEach((recs: SyncRecord[], name: string) => {
    const copy: SyncRecord[] = [];
    for (const r of recs) {
      const c: SyncRecord = { key: r.key, updateTime: r.updateTime, deviceId: r.deviceId,
        isDeleted: r.isDeleted, payload: r.payload };
      copy.push(c);
    }
    out.set(name, copy);
  });
  return out;
}

export class LoopbackAdapter implements ITransport {
  private profiles: Map<string, Map<string, SyncRecord[]>> = new Map();
  private static peerOf(deviceId: string): string {
    return deviceId === 'deviceA' ? 'deviceB' : 'deviceA';
  }
  async exchange(deviceId: string, local: Map<string, SyncRecord[]>): Promise<Map<string, SyncRecord[]>> {
    const peer = LoopbackAdapter.peerOf(deviceId);
    const theirs = this.profiles.get(peer);
    if (theirs === undefined) {
      this.profiles.set(peer, cloneTables(local));
      const empty: Map<string, SyncRecord[]> = new Map();
      local.forEach((_v: SyncRecord[], name: string) => { empty.set(name, []); });
      return empty;
    }
    return cloneTables(theirs);
  }
  async notifyAfterSync(deviceId: string, finalTables: Map<string, SyncRecord[]>): Promise<void> {
    this.profiles.set(LoopbackAdapter.peerOf(deviceId), cloneTables(finalTables));
  }
}
```

- [ ] **Step 3: 写 SyncScheduler，先写它的失败测试**

```js
// tools/merge-tests/scheduler.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { runSync } from '../.tsbuild/service/sync/SyncScheduler.ts';
import { LoopbackAdapter } from '../.tsbuild/repository/LoopbackAdapter.ts';

const rec = (key, t, dev, del = false) => ({ key, updateTime: t, deviceId: dev, isDeleted: del, payload: {} });

class FakeRepo {
  constructor(tables, metas = new Map()) { this.tables = tables; this.metas = metas; }
  async snapshotSyncTables() { const m = new Map(); Object.entries(this.tables).forEach(([k, v]) => m.set(k, v)); return m; }
  async applyMerged(table, records) { this.tables[table] = records.map((r) => r); }
  async getMeta(k) { return this.metas.get(k) ?? ''; }
  async setMeta(k, v) { this.metas.set(k, v); }
}

test('A/B 各改同一条笔记 → 同步 → 胜者正确且冲突历史可见败版本 (T3 算法部分)', async () => {
  const repoA = new FakeRepo({ favorite: [rec('n1', 1, 'deviceA')], note: [], note_tag: [], tag: [], progress: [] });
  const repoB = new FakeRepo({ favorite: [rec('n1', 2, 'deviceB')], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  const conflicts = await runSync('deviceA', repoA, bus);
  assert.equal(conflicts.length, 1);
  assert.equal(repoA.tables.favorite[0].deviceId, 'deviceB'); // B 时间戳大
  await runSync('deviceB', repoB, bus);
  assert.deepEqual(repoB.tables.favorite.map((r) => [r.key, r.updateTime]), [['n1', 2]]); // 收敛
  const log = JSON.parse(repoA.metas.get('conflictLogJson'));
  assert.equal(log[0].loser.deviceId, 'deviceA');
  assert.ok(Number(repoA.metas.get('lastSyncTime')) > 0);
});

test('首轮对端为空 → 单方纳入无冲突', async () => {
  const repoA = new FakeRepo({ favorite: [rec('f1', 1, 'A')], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  const conflicts = await runSync('deviceA', repoA, bus);
  assert.equal(conflicts.length, 0);
  assert.equal(repoA.tables.favorite.length, 1);
});

test('onProgress 每表回调一次且 total 单调', async () => {
  const repoA = new FakeRepo({ favorite: [], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  const seen = [];
  await runSync('deviceA', repoA, bus, (table, done, total) => { seen.push([table, done, total]); });
  assert.equal(seen.length, 5);
  assert.equal(seen[0][2], 5);
});
```

- [ ] **Step 4: 跑测试确认失败**

Run: `node tools/merge-tests/run.mjs && node --test tools/merge-tests/`
Expected: scheduler 用例 FAIL（SyncScheduler.ts 不存在）

- [ ] **Step 5: 实现 SyncScheduler.ets**

```ts
// entry/src/main/ets/service/sync/SyncScheduler.ets —— 禁 @kit
import { SyncRecord, ConflictEntry, SYNC_TABLES } from '../../model/SyncModels';
import { mergeElementSets, appendConflictLog } from '../merge/MergeEngine';
import { IDataRepository } from '../../repository/IDataRepository';
import { ITransport } from '../../repository/ITransport';

export type ProgressCallback = (table: string, done: number, total: number) => void;

export async function runSync(deviceId: string, repo: IDataRepository,
  transport: ITransport, onProgress?: ProgressCallback): Promise<ConflictEntry[]> {
  const local = await repo.snapshotSyncTables();
  const remote = await transport.exchange(deviceId, local);
  const allConflicts: ConflictEntry[] = [];
  const finalTables: Map<string, SyncRecord[]> = new Map();
  let done = 0;
  for (const name of SYNC_TABLES) {
    const a: SyncRecord[] = local.get(name) ?? [];
    const b: SyncRecord[] = remote.get(name) ?? [];
    const merged = mergeElementSets(a, b);
    allConflicts = allConflicts.concat(merged.conflicts);
    finalTables.set(name, merged.finalRecords);
    await repo.applyMerged(name, merged.finalRecords);
    done = done + 1;
    if (onProgress !== undefined) { onProgress(name, done, SYNC_TABLES.length); }
  }
  await transport.notifyAfterSync(deviceId, finalTables);
  if (allConflicts.length > 0) {
    const oldLog: string = await repo.getMeta('conflictLogJson');
    await repo.setMeta('conflictLogJson', appendConflictLog(oldLog, allConflicts, 50));
  }
  await repo.setMeta('lastSyncTime', String(Date.now()));
  return allConflicts;
}
```

- [ ] **Step 6: Node 测试全绿 + 编译门**

Run: `node tools/merge-tests/run.mjs && node --test tools/merge-tests/` → 11 pass
Run: `cd app && ./build-oh.bat` → BUILD SUCCESSFUL

- [ ] **Step 7: 实现 LocalRdbImpl.ets（DDL 逐字 §6.1；不进 harness）**

```ts
// entry/src/main/ets/repository/LocalRdbImpl.ets
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SyncRecord, SYNC_TABLES } from '../model/SyncModels';
import { FavoriteDO, NoteDO, TagDO, ProgressDO } from '../model/UserDataModels';
import { IDataRepository } from './IDataRepository';

const DOMAIN = 0x0001;
const TAG = 'HuangheRdb';

const DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS favorite (
  target_key TEXT PRIMARY KEY,
  createTime INTEGER, updateTime INTEGER,
  deviceId TEXT, isDeleted INTEGER DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS note (
  note_id TEXT PRIMARY KEY,
  target_key TEXT, text TEXT, createTime INTEGER, updateTime INTEGER,
  deviceId TEXT, isDeleted INTEGER DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS note_tag (note_id TEXT, tag_id TEXT, updateTime INTEGER,
  PRIMARY KEY(note_id, tag_id))`,
  `CREATE TABLE IF NOT EXISTS tag (
  tag_id TEXT PRIMARY KEY, name TEXT, isPreset INTEGER,
  updateTime INTEGER, isDeleted INTEGER)`,
  `CREATE TABLE IF NOT EXISTS progress (
  target_key TEXT, section TEXT,
  done INTEGER, updateTime INTEGER, deviceId TEXT,
  PRIMARY KEY(target_key, section))`,
  `CREATE TABLE IF NOT EXISTS sync_meta (k TEXT PRIMARY KEY, v TEXT)`
];

// 表元数据：主键列名 + 同步域四列在各表中的列名映射
class TableMeta {
  pk: string = '';
  keyCols: string[] = [];        // 拼 key 的列（主键列，note_tag 为两列）
  updateTimeCol: string = 'updateTime';
  deviceCol: string = 'deviceId'; // note_tag/tag/progress 中可能缺省 → ''
  deleteCol: string = 'isDeleted';// note_tag 无墓碑列 → ''
}
const TABLE_META: Map<string, TableMeta> = new Map();
function meta(pk: string, keyCols: string[], deviceCol: string, deleteCol: string): TableMeta {
  const m = new TableMeta();
  m.pk = pk; m.keyCols = keyCols; m.deviceCol = deviceCol; m.deleteCol = deleteCol;
  return m;
}
TABLE_META.set('favorite', meta('target_key', ['target_key'], 'deviceId', 'isDeleted'));
TABLE_META.set('note', meta('note_id', ['note_id'], 'deviceId', 'isDeleted'));
TABLE_META.set('note_tag', meta('note_id', ['note_id', 'tag_id'], '', ''));
TABLE_META.set('tag', meta('tag_id', ['tag_id'], '', 'isDeleted'));
TABLE_META.set('progress', meta('target_key', ['target_key', 'section'], 'deviceId', ''));

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'huanghe_memory.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

export class LocalRdbImpl implements IDataRepository {
  private store: relationalStore.RdbStore | null = null;

  async init(context: ESObject): Promise<void> {
    this.store = await relationalStore.getRdbStore(context as common.UIAbilityContext, STORE_CONFIG);
    for (const sql of DDL) { await this.store.executeSql(sql); }
    hilog.info(DOMAIN, TAG, 'db ready');
  }

  private s(): relationalStore.RdbStore {
    const st = this.store;
    if (st === null) { throw new Error('rdb not init'); }
    return st;
  }

  async snapshotSyncTables(): Promise<Map<string, SyncRecord[]>> {
    const out: Map<string, SyncRecord[]> = new Map();
    for (const name of SYNC_TABLES) {
      const m = TABLE_META.get(name)!;
      const rs = await this.s().querySql(`SELECT * FROM ${name}`);
      const rows: SyncRecord[] = [];
      while (rs.goToNextRow()) {
        const cols = rs.columnNames;
        const payload: Record<string, string | number | boolean> = {};
        for (const col of cols) {
          if (col === m.updateTimeCol) { continue; }
          const idx = rs.getColumnIndex(col);
          payload[col] = rs.getLong(idx) !== undefined ? rs.getString(idx) : '';
        }
        const keyParts: string[] = [];
        for (const kc of m.keyCols) { keyParts.push(rs.getString(rs.getColumnIndex(kc))); }
        const rec: SyncRecord = {
          key: keyParts.join('\u001f'),
          updateTime: rs.getLong(rs.getColumnIndex(m.updateTimeCol)),
          deviceId: m.deviceCol === '' ? '' : rs.getString(rs.getColumnIndex(m.deviceCol)),
          isDeleted: m.deleteCol === '' ? false : rs.getLong(rs.getColumnIndex(m.deleteCol)) === 1,
          payload: payload
        };
        rows.push(rec);
      }
      rs.close();
      out.set(name, rows);
    }
    return out;
  }

  async applyMerged(table: string, records: SyncRecord[]): Promise<void> {
    const m = TABLE_META.get(table);
    if (m === undefined) { return; }
    await this.s().executeSql(`DELETE FROM ${table}`);
    for (const r of records) {
      const cols = Object.keys(r.payload);
      const keyVals = r.key.split('\u001f');
      const allCols: string[] = [];
      const bucket: relationalStore.ValuesBucket = {};
      for (let i = 0; i < m.keyCols.length; i++) { allCols.push(m.keyCols[i]); bucket[m.keyCols[i]] = keyVals[i]; }
      for (const c of cols) { allCols.push(c); bucket[c] = r.payload[c]; }
      allCols.push(m.updateTimeCol); bucket[m.updateTimeCol] = r.updateTime;
      if (m.deviceCol !== '') { allCols.push(m.deviceCol); bucket[m.deviceCol] = r.deviceId; }
      if (m.deleteCol !== '') { allCols.push(m.deleteCol); bucket[m.deleteCol] = r.isDeleted ? 1 : 0; }
      const placeholders = allCols.map((_c: string): string => '?').join(',');
      const values = allCols.map((c: string): string | number | boolean => bucket[c]);
      await this.s().executeSql(
        `INSERT OR REPLACE INTO ${table} (${allCols.join(',')}) VALUES (${placeholders})`, values);
    }
  }

  async getMeta(key: string): Promise<string> {
    const rs = await this.s().querySql('SELECT v FROM sync_meta WHERE k = ?', [key]);
    let v = '';
    if (rs.goToNextRow()) { v = rs.getString(0); }
    rs.close();
    return v;
  }

  async setMeta(key: string, value: string): Promise<void> {
    await this.s().executeSql(
      'INSERT OR REPLACE INTO sync_meta (k, v) VALUES (?, ?)', [key, value]);
  }

  async upsertFavorite(fav: FavoriteDO): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      target_key: fav.targetKey, createTime: fav.createTime, updateTime: fav.updateTime,
      deviceId: fav.deviceId, isDeleted: fav.isDeleted ? 1 : 0
    };
    await this.s().insert('favorite', bucket);
  }

  async deleteFavorite(targetKey: string, deviceId: string, now: number): Promise<void> {
    // 墓碑更新（§4.2）：不物理删除
    const bucket: relationalStore.ValuesBucket = { updateTime: now, deviceId: deviceId, isDeleted: 1 };
    const p = new relationalStore.RdbPredicates('favorite');
    p.equalTo('target_key', targetKey);
    await this.s().update(bucket, p);
  }

  async upsertNote(note: NoteDO): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      note_id: note.noteId, target_key: note.targetKey, text: note.text,
      createTime: note.createTime, updateTime: note.updateTime,
      deviceId: note.deviceId, isDeleted: note.isDeleted ? 1 : 0
    };
    await this.s().insert('note', bucket);
  }

  async setNoteTags(noteId: string, tagIds: string[], now: number, deviceId: string): Promise<void> {
    const del = new relationalStore.RdbPredicates('note_tag');
    del.equalTo('note_id', noteId);
    await this.s().delete(del);
    for (const t of tagIds) {
      const b: relationalStore.ValuesBucket = { note_id: noteId, tag_id: t, updateTime: now };
      await this.s().insert('note_tag', b);
    }
    for (const t of tagIds) {
      const tb: relationalStore.ValuesBucket = { tag_id: t, name: t, isPreset: 0, updateTime: now, isDeleted: 0 };
      await this.s().insert('tag', tb); // 字典自动补全，INSERT OR IGNORE 语义由调用方 tag 表 PK 保证 → 用 insert 冲突时忽略
    }
  }

  async upsertTag(tag: TagDO): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      tag_id: tag.tagId, name: tag.name, isPreset: tag.isPreset ? 1 : 0,
      updateTime: tag.updateTime, isDeleted: tag.isDeleted ? 1 : 0
    };
    await this.s().insert('tag', bucket);
  }

  async upsertProgress(p: ProgressDO): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      target_key: p.targetKey, section: p.section, done: p.done ? 1 : 0,
      updateTime: p.updateTime, deviceId: p.deviceId
    };
    await this.s().insert('progress', bucket);
  }
}
```
注意：`upsertTag/setNoteTags` 里 tag 自动补全若遇 PK 冲突，`insert` 会抛错——实现时给 tag 的插入包一层 `try { } catch (e) { }` 或改用 `INSERT OR IGNORE`（executeSql）。执行时二选一并保持编译绿。

- [ ] **Step 8: 编译门 + Commit**

Run: `cd app && ./build-oh.bat` → BUILD SUCCESSFUL
```bash
cd "E:\ .stepclaw" && git add huanghe-memory && git commit -m "feat(huanghe-memory): 仓储接口/LocalRdbImpl建表/LoopbackAdapter/SyncScheduler"
```

---

### Task 4: 内容 schema + validate_sites.py + 种子数据（9 遗址）

**Files:**
- Create: `tools/site.schema.json`
- Create: `tools/validate_sites.py`
- Create: `tools/sites-src/*.json`（9 个母本，含 source 字段）
- Create: `tools/merge-tests/fixtures/broken_site.json`
- Test: `python tools/validate_sites.py tools/sites-src`（期望 exit 0 + 矩阵报告）；对 broken fixture 期望非零

**Interfaces:**
- Produces: `tools/sites-out/*.json`（剥离 source 后的发布版）——Task 5 拷入 rawfile。

- [ ] **Step 1: 写 site.schema.json**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["id", "name", "city", "era", "site_type", "summary", "tags",
               "sections", "images", "relics"],
  "properties": {
    "id": { "type": "string", "pattern": "^[a-z0-9_]{3,40}$" },
    "name": { "type": "string", "minLength": 2 },
    "city": { "enum": ["sanmenxia", "luoyang", "zhengzhou", "kaifeng", "puyang"] },
    "era": { "enum": ["yangshao", "longshan", "xiashang", "zhou", "hantang", "song"] },
    "site_type": { "enum": ["capital", "burial", "kiln", "ancient_arch"] },
    "summary": { "type": "string", "minLength": 20 },
    "tags": { "type": "array", "minItems": 1, "items": { "type": "string" } },
    "sections": {
      "type": "object",
      "required": ["intro", "arch", "events", "poems", "tourism"],
      "properties": {
        "intro": { "type": "string", "minLength": 30 },
        "arch": { "type": "string", "minLength": 30 },
        "events": { "type": "string", "minLength": 20 },
        "poems": { "type": "array", "items": {
          "type": "object", "required": ["text", "author", "source"],
          "properties": { "text": {"type":"string","minLength":4}, "author": {"type":"string","minLength":1}, "source": {"type":"string","minLength":1} } } },
        "tourism": { "type": "string", "minLength": 10 }
      }
    },
    "images": { "type": "array", "minItems": 2, "maxItems": 4, "items": { "type": "string", "pattern": "^images/[a-z0-9_]+/[a-z0-9_]+\\.webp$" } },
    "relics": { "type": "array", "minItems": 2, "maxItems": 4, "items": {
      "type": "object", "required": ["id", "name", "era", "summary", "material", "images"],
      "properties": {
        "id": { "type": "string", "pattern": "^[a-z0-9_]{3,40}$" },
        "name": { "type": "string", "minLength": 2 },
        "era": { "enum": ["yangshao", "longshan", "xiashang", "zhou", "hantang", "song"] },
        "summary": { "type": "string", "minLength": 20 },
        "material": { "type": "string", "minLength": 2 },
        "images": { "type": "array", "minItems": 1, "maxItems": 2, "items": { "type": "string" } }
      } } }
  },
  "additionalProperties": true
}
```

- [ ] **Step 2: 写 validate_sites.py**

```python
#!/usr/bin/env python3
# tools/validate_sites.py — schema 校验 + 配额矩阵报告 + 剥离 source 生成发布版
import json, sys, copy
from pathlib import Path

ERA_PREHISTORIC = {"yangshao", "longshan"}

def load_schema(base: Path) -> dict:
    return json.loads((base / "site.schema.json").read_text(encoding="utf-8"))

def check_site(obj: dict, schema: dict) -> list[str]:
    errs = []
    for k in schema["required"]:
        if k not in obj:
            errs.append(f"缺字段 {k}")
    if errs:
        return errs
    props = schema["properties"]
    for name, spec in props.items():
        v = obj.get(name)
        if v is None:
            continue
        if "enum" in spec and v not in spec["enum"]:
            errs.append(f"{name}={v!r} 不在枚举 {spec['enum']}")
        if spec.get("type") == "string" and "minLength" in spec and len(v) < spec["minLength"]:
            errs.append(f"{name} 过短({len(v)}<{spec['minLength']})")
        if spec.get("type") == "array" and "minItems" in spec and len(v) < spec["minItems"]:
            errs.append(f"{name} 条目数 {len(v)}<{spec['minItems']}")
        if spec.get("type") == "array" and "maxItems" in spec and len(v) > spec["maxItems"]:
            errs.append(f"{name} 条目数 {len(v)}>{spec['maxItems']}")
    sec = obj["sections"]
    for k in ("intro", "arch", "events", "tourism"):
        if len(sec.get(k, "")) < 10:
            errs.append(f"sections.{k} 过短")
    poems = sec.get("poems", [])
    for p in poems:
        for f in ("text", "author", "source"):
            if not str(p.get(f, "")).strip():
                errs.append(f"poems 缺 {f}（诗词必须真句真作者真出处）")
    if not poems and obj["era"] not in ERA_PREHISTORIC:
        errs.append("非史前遗址 poems 为空")
    for r in obj.get("relics", []):
        if r.get("era") not in schema["properties"]["era"]["enum"]:
            errs.append(f"relic {r.get('id')} era 非法")
    return errs

def strip_source(obj: dict) -> dict:
    o = copy.deepcopy(obj)
    o.pop("source", None)
    for r in o.get("relics", []):
        r.pop("source", None)
    return o

def main(src_dir: str, out_dir: str | None) -> int:
    base = Path(__file__).parent
    schema = load_schema(base)
    sites = []
    fail = False
    for f in sorted(Path(src_dir).glob("*.json")):
        obj = json.loads(f.read_text(encoding="utf-8"))
        errs = check_site(obj, schema)
        if errs:
            fail = True
            print(f"[FAIL] {f.name}: " + "; ".join(errs))
        sites.append(obj)
    # 配额矩阵（报告，不判失败——满配 40 条由内容线补齐时再收紧为硬闸门）
    cities = sorted({s["city"] for s in sites})
    eras = sorted({s["era"] for s in sites})
    types_ = sorted({s["site_type"] for s in sites})
    print(f"共 {len(sites)} 条 | 城市覆盖 {cities}")
    print(f"年代覆盖 {eras} | 类型覆盖 {types_}")
    for c in schema["properties"]["city"]["enum"]:
        n = sum(1 for s in sites if s["city"] == c)
        print(f"  city {c}: {n}")
    for e in schema["properties"]["era"]["enum"]:
        n = sum(1 for s in sites if s["era"] == e)
        print(f"  era {e}: {n}")
    ids = [s["id"] for s in sites] + [r["id"] for s in sites for r in s.get("relics", [])]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        print(f"[FAIL] id 重复: {dup}"); fail = True
    if not fail and out_dir:
        od = Path(out_dir); od.mkdir(exist_ok=True)
        for s in sites:
            (od / f"{s['id']}.json").write_text(
                json.dumps(strip_source(s), ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"发布版已生成 → {out_dir} ({len(sites)} 文件)")
    return 1 if fail else 0

if __name__ == "__main__":
    args = sys.argv[1:]
    sys.exit(main(args[0], args[1] if len(args) > 1 else str(Path(args[0]).parent / "sites-out")))
```

- [ ] **Step 3: 跑 validator 确认对空目录/坏数据能失败**

Run: `cd "E:\ .stepclaw\huanghe-memory" && python tools/validate_sites.py tools/merge-tests/fixtures`
Expected: 非零退出（fixture 里放一个故意坏例：缺 relics + poems 有句无作者）

- [ ] **Step 4: 写 9 条种子遗址母本（tools/sites-src/）**

| id | 名称 | city | era | site_type | 代表文物（2–4 件） |
|---|---|---|---|---|---|
| yangshao_village | 仰韶村遗址 | sanmenxia | yangshao | kiln | 小口尖底瓶、彩陶盆 |
| beiliangang | 北梁岗墓地（仰韶文化墓地） | luoyang | yangshao | burial | 彩陶壶、骨簪 |
| pengyu | 西水坡遗址（蚌塑龙出土地） | puyang | yangshao | burial | 蚌塑龙虎图案、人骨 |
| wangchenggang | 王城岗遗址 | zhengzhou | longshan | capital | 龙山黑陶、城墙夯土样本 |
| erlitou | 二里头遗址 | luoyang | xiashang | capital | 青铜爵（绿松石嵌片）、乳钉纹铜镜、陶鬶 |
| yanshi_shangcheng | 偃师商城遗址 | luoyang | xiashang | capital | 石圭、陶鼎 |
| zhengzhou_shangcheng | 郑州商城遗址 | zhengzhou | xiashang | capital | 杜岭方鼎、兽面纹铜尊 |
| han_canal | 鸿沟故道（鸿沟/汉运河遗迹） | sanmenxia | hantang | ancient_arch | 运河木构闸板（以公开简报为准） |
| dongjing | 北宋东京城遗址（州桥及汴河遗址） | kaifeng | song | capital | 州桥石刻壁面、汴河沉船构件 |

**事实核验步骤（必做，防编造）**：每条动笔前用 WebSearch 核对该遗址的：所在区县、年代归属、类型定性、代表文物名称与收藏单位、发掘简报口径的考古层内容。州桥及汴河遗址（开封，宋）与西水坡（濮阳，蚌塑龙）为高置信条目；**鸿沟故道一条若考古层事实核不实，改选三门峡陕州"底张湾汉墓群"或弃之换 `hantang` 城市=洛阳的"汉魏洛阳城遗址"（推荐后者，事实充足）**。poems 字段：史前两档（仰韶/龙山）允许空数组；其余每条至少 1 首真诗——汉魏洛阳城可用曹丕/《古诗十九首》相关句（须核实出处），郑州商城无合适古诗时允许引用甲骨文卜辞原文并标注出处为社科院考古所公开著录。
每条母本含 `source` 字段（来源清单，构建时剥离）。

- [ ] **Step 5: 跑 validator 全绿并生成发布版**

Run: `python tools/validate_sites.py tools/sites-src tools/sites-out`
Expected: exit 0，`发布版已生成 → tools/sites-out (9 文件)`，矩阵报告显示 5 城市全覆盖、era 至少 5 档、type 至少 3 类

- [ ] **Step 6: Commit**

```bash
cd "E:\ .stepclaw" && git add huanghe-memory/tools && git commit -m "feat(huanghe-memory): 遗址内容schema/校验脚本/9条种子数据(含source母本)"
```

---

### Task 5: rawfile 集成 + ContentParse 纯函数 + ContentRepo

**Files:**
- Create: `app/entry/src/main/ets/service/content/ContentParse.ets`（纯函数，进 harness）
- Create: `app/entry/src/main/ets/repository/ContentRepo.ets`（唯一 @kit 触点：resourceManager）
- Create: `tools/merge-tests/content_parse.test.mjs`
- Copy: `tools/sites-out/*.json` → `app/entry/src/main/resources/rawfile/sites/`

**Interfaces:**
- Consumes: Task 1 `SiteInfo/RelicInfo/PoemRef/ERAS/CITIES/SITE_TYPES`、Task 4 发布版 JSON
- Produces: `parseSiteJson(raw: string): SiteInfo`（抛错即数据坏）、`parseAll(raws: string[]): SiteInfo[]`、`ContentRepo.load(context): Promise<SiteInfo[]>`、`filterSites(sites, eras, types, cities): SiteInfo[]`、`searchSites(sites, keyword): SiteInfo[]`（name/summary/tags 小写包含）

- [ ] **Step 1: 写失败测试**

```js
// tools/merge-tests/content_parse.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parseSiteJson, parseAll, filterSites, searchSites } from '../.tsbuild/service/content/ContentParse.ts';

const DIR = join(import.meta.dirname, '../../app/entry/src/main/resources/rawfile/sites');

test('rawfile 全部 9 条可解析且枚举合法', () => {
  const raws = readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => readFileSync(join(DIR, f), 'utf8'));
  const sites = parseAll(raws);
  assert.equal(sites.length, 9);
  for (const s of sites) {
    assert.ok(s.id && s.name && s.relics.length >= 2);
    assert.ok(!('source' in s));
  }
});

test('三维筛选：组内并集组间交集', () => {
  const sites = parseAll(readdirSync(DIR).map((f) => readFileSync(join(DIR, f), 'utf8')));
  const r = filterSites(sites, ['yangshao', 'longshan'], [], ['luoyang', 'puyang']);
  assert.ok(r.length >= 1);
  assert.ok(r.every((s) => ['yangshao', 'longshan'].includes(s.era)
    && ['luoyang', 'puyang'].includes(s.city)));
});

test('关键词检索命中 name/summary/tags 且大小写不敏感', () => {
  const sites = parseAll(readdirSync(DIR).map((f) => readFileSync(join(DIR, f), 'utf8')));
  const hit = searchSites(sites, sites[0].name.toUpperCase());
  assert.ok(hit.some((s) => s.id === sites[0].id));
});
```

- [ ] **Step 2: 确认失败**（ContentParse.ts 不存在）
Run: `node tools/merge-tests/run.mjs && node --test tools/merge-tests/`

- [ ] **Step 3: 实现 ContentParse.ets**

```ts
// entry/src/main/ets/service/content/ContentParse.ets —— 纯函数，禁 @kit
import { SiteInfo, RelicInfo, PoemRef, ERAS, CITIES, SITE_TYPES } from '../../model/ContentModels';

function reqStr(o: Record<string, Object>, k: string): string {
  const v = o[k];
  if (typeof v !== 'string') { throw new Error(`字段 ${k} 缺失或非字符串`); }
  return v as string;
}

export function parseSiteJson(raw: string): SiteInfo {
  const o = JSON.parse(raw) as Record<string, Object>;
  const s = new SiteInfo();
  s.id = reqStr(o, 'id'); s.name = reqStr(o, 'name');
  s.city = reqStr(o, 'city'); s.era = reqStr(o, 'era'); s.siteType = reqStr(o, 'site_type');
  s.summary = reqStr(o, 'summary');
  if (!ERAS.includes(s.era) || !CITIES.includes(s.city) || !SITE_TYPES.includes(s.siteType)) {
    throw new Error(`${s.id}: 枚举值非法`);
  }
  const tags = o['tags'] as string[]; s.tags = tags;
  const sec = o['sections'] as Record<string, Object>;
  s.intro = reqStr(sec, 'intro'); s.archaeology = reqStr(sec, 'arch');
  s.events = reqStr(sec, 'events'); s.tourism = reqStr(sec, 'tourism');
  const poems = sec['poems'] as Record<string, Object>[];
  for (const p of poems) {
    const pr = new PoemRef();
    pr.text = reqStr(p, 'text'); pr.author = reqStr(p, 'author'); pr.source = reqStr(p, 'source');
    s.poems.push(pr);
  }
  s.images = o['images'] as string[];
  const relics = o['relics'] as Record<string, Object>[];
  for (const rj of relics) {
    const r = new RelicInfo();
    r.id = reqStr(rj, 'id'); r.siteId = s.id; r.name = reqStr(rj, 'name');
    r.era = reqStr(rj, 'era'); r.summary = reqStr(rj, 'summary');
    r.material = reqStr(rj, 'material'); r.images = rj['images'] as string[];
    s.relics.push(r);
  }
  return s;
}

export function parseAll(raws: string[]): SiteInfo[] {
  const out: SiteInfo[] = [];
  for (const raw of raws) { out.push(parseSiteJson(raw)); }
  return out;
}

export function filterSites(sites: SiteInfo[], eras: string[], types: string[], cities: string[]): SiteInfo[] {
  return sites.filter((s: SiteInfo): boolean =>
    (eras.length === 0 || eras.includes(s.era)) &&
    (types.length === 0 || types.includes(s.siteType)) &&
    (cities.length === 0 || cities.includes(s.city)));
}

export function searchSites(sites: SiteInfo[], keyword: string): SiteInfo[] {
  const kw = keyword.toLowerCase();
  if (kw.length === 0) { return sites; }
  return sites.filter((s: SiteInfo): boolean =>
    s.name.toLowerCase().includes(kw) || s.summary.toLowerCase().includes(kw) ||
    s.tags.some((t: string): boolean => t.toLowerCase().includes(kw)));
}
```

- [ ] **Step 4: 拷发布版进 rawfile 并跑测试全绿**

```bash
mkdir -p "app/entry/src/main/resources/rawfile/sites" && cp tools/sites-out/*.json app/entry/src/main/resources/rawfile/sites/
node tools/merge-tests/run.mjs && node --test tools/merge-tests/
```
Expected: 14 pass 0 fail（8 merge + 3 scheduler + 3 content）

- [ ] **Step 5: 实现 ContentRepo.ets（@kit 触点，编译门验证）**

```ts
// entry/src/main/ets/repository/ContentRepo.ets
import { resourceManager } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';
import { SiteInfo } from '../model/ContentModels';
import { parseAll } from '../service/content/ContentParse';

const SITE_DIR = 'sites';

export class ContentRepo {
  private static cache: SiteInfo[] | null = null;

  static async load(context: Context): Promise<SiteInfo[]> {
    const cached = ContentRepo.cache;
    if (cached !== null) { return cached; }
    const rm = context.resourceManager;
    const names: string[] = await rm.getRawFileList(SITE_DIR) as string[];
    const raws: string[] = [];
    for (const n of names) {
      if (!n.endsWith('.json')) { continue; }
      const bytes: Uint8Array = await rm.getRawFileContent(`${SITE_DIR}/${n}`);
      raws.push(util.TextDecoder.create('utf-8').decodeToString(bytes));
    }
    const sites = parseAll(raws);
    ContentRepo.cache = sites;
    return sites;
  }
}
```
（`Context` 用 `common.UIAbilityContext` 传入；若编译报 `Context` 未定义，改为 `import { common } from '@kit.AbilityKit'` 并以 `common.BaseContext` 为参。）

- [ ] **Step 6: 编译门 + Commit**

Run: `cd app && ./build-oh.bat` → BUILD SUCCESSFUL（rawfile 打进 HAP，包体仍应 <1MB，为 T6 留余量）
```bash
cd "E:\ .stepclaw" && git add huanghe-memory && git commit -m "feat(huanghe-memory): ContentParse纯函数检索筛选+rawfile内容集成"
```

---

## 验收（整计划出口）

1. `node tools/merge-tests/run.mjs && node --test tools/merge-tests/` → 14 pass
2. `python tools/validate_sites.py tools/sites-src tools/sites-out` → exit 0
3. `cd app && ./build-oh.bat` → BUILD SUCCESSFUL，HAP 产出
4. `git log --oneline` 上 5 个本计划提交，工作树对 huanghe-memory 干净
5. 交付说明：T3 的算法部分已由 scheduler.test 覆盖；设备端 ohosTest（T8）、RDB 真库读写、同步面板 UI 属下一份「UI 九屏 + 同步面板」计划的前置。

## Self-Review 记录

- **Spec 覆盖**：§6.1 DDL→Task3；§6.2 合并→Task2/3；§3.2 模块树（model/service/repository/rawfile/tools）→全部；§7.1 配额矩阵→Task4 validator 报告（满配 40 为内容线后续任务，本计划 9 条种子）；§7.2 色板→Task1；§4.5 推荐纯函数→**未含**（依赖行为数据表，随 UI 计划实现，此处刻意推迟避免无消费方的 YAGNI）；§4.1/4.2/4.3UI/4.6/§5→下一计划。
- **占位符扫描**：无 TBD；Task4 种子数据给出逐条字段来源与核验步骤。
- **类型一致性**：`mergeElementSets/appendConflictLog/runSync/exchange/notifyAfterSync/snapshotSyncTables/applyMerged` 在 Task2/3/5 引用处签名一致；`SyncRecord.key` 分隔符 `\u001f` 在 LocalRdbImpl 与 LoopbackAdapter 一致。
