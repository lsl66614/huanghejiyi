// entry/src/main/ets/common/ImagePolicy.ets
// 图像策略（docs/IMAGES.md 2026-10-03 口径）：
//   AI 生成图仅允许出现在首页年代块（EraTheme.ERA_COVER_IMAGES 指定的 6 张，挂「示意图」角标）；
//   其余一切图位一律使用真实照片（自有拍摄或已授权图），文件名以 real_ 开头，
//   如 images/qingtai/real_sizhipin.webp（命名符合 site.schema.json 的 pattern）。
//   真实照片到位前各图位按制式回退：遗址=年代色整块「图像整备中」，文物=单色剪影。
// 实拍入仓工作流：webp（宽 1024、quality 78）按 real_ 前缀命名放入 images/<遗址>/，
//   在该遗址 JSON 的 images / relics[].images 追加路径 → UI 自动显示，零代码改动。
export function isRealImage(path: string): boolean {
  const slash: number = path.lastIndexOf('/');
  return slash >= 0 && path.slice(slash + 1, slash + 5) === 'real';
}

export function firstRealImage(images: string[]): string {
  for (const p of images) {
    if (isRealImage(p)) {
      return p;
    }
  }
  return '';
}

export function realImagesExclude(images: string[], exclude: string): string[] {
  const out: string[] = [];
  for (const p of images) {
    if (isRealImage(p) && p !== exclude) {
      out.push(p);
    }
  }
  return out;
}
