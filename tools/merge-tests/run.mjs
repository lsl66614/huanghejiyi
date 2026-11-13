// tools/merge-tests/run.mjs —— 把纯函数 .ets 复制为 .ts 并补全导入扩展名，供 Node 24 type-stripping 执行
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..'); // huanghe-memory
const SRC = join(ROOT, 'app', 'entry/src/main/ets');
const OUT = join(ROOT, 'tools/.tsbuild');
const FILES = [
  'model/SyncModels.ets',
  'model/UserDataModels.ets',
  'model/ContentModels.ets',
  'common/DesignTokens.ets',
  'common/EraTheme.ets',
  'common/Labels.ets',
  'common/Time.ets',
  'common/ZoomMath.ets',
  'service/merge/MergeEngine.ets',
  'service/merge/LogicalClock.ets',
  'service/merge/ConflictLabel.ets',
  'service/sync/SyncScheduler.ets',
  'service/sync/AutoSyncGate.ets',
  'repository/IDataRepository.ets',
  'repository/ITransport.ets',
  'repository/LoopbackAdapter.ets',
  'service/content/ContentParse.ets',
  'service/content/Attribution.ets',
  'service/content/RouteParse.ets',
  'service/content/TargetLabel.ets',
  'service/content/ItemTarget.ets',
  'service/notes/NoteReview.ets',
  'service/export/ExportFormat.ets',
  'service/import/ImportPlan.ets',
  'service/recommend/RecommendService.ets',
  'service/recommend/RecoSource.ets',
  'service/network/NetworkSource.ets',
  'service/network/ForceLayout.ets',
  'service/content/MaterialIndex.ets',
  'service/content/EraRelicCount.ets',
];

rmSync(OUT, { recursive: true, force: true });
for (const f of FILES) {
  if (!existsSync(join(SRC, f))) continue;
  let code = readFileSync(join(SRC, f), 'utf8');
  // 相对导入无扩展名 → 补 .ts（Node ESM 要求显式扩展名）
  code = code.replace(/from '(\.\.?\/[^']+)'/g, (mm, spec) => {
    if (/\.(ts|js|json)$/.test(spec)) return mm;
    return `from '${spec}.ts'`;
  });
  const dest = join(OUT, f.replace(/\.ets$/, '.ts'));
  mkdirSync(dirname(dest), { recursive: true });
  // ArkUI 全局枚举在 Node type-stripping 环境下不存在——引用处模块顶部注入 polyfill。
  // 值只需可比较/可传递，不参与真实动画。
  if (/\bCurve\./.test(code)) {
    code = "const Curve = { EaseOut: 'EaseOut', EaseIn: 'EaseIn', EaseInOut: 'EaseInOut', Linear: 'Linear', Spring: 'Spring' } as const;\n" + code;
  }
  writeFileSync(dest, code);
}
console.log('tsbuild ready:', OUT);
