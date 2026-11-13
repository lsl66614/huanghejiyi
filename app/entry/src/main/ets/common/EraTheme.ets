// entry/src/main/ets/common/EraTheme.ets
// 国风改版：六年代色按出土物本体色重定；前景/纹理逐块给定，禁止按年代名单硬编码判断。
//
// 本文件只管年代维度（哪个年代什么色）。
// 语义维度（什么层级、什么间距、什么字号）在 common/DesignTokens.ets。
import { INK, SURFACE_PAGE } from './DesignTokens';
const ERA_COLORS: Map<string, string> = new Map([
  ['yangshao', '#8E4028'],
  ['longshan', '#332E29'],
  ['xiashang', '#4E6B52'],
  ['zhou', '#75888F'],
  ['hantang', '#B98A44'],
  ['song', '#7F97A4']
]);

const ERA_INKS: Map<string, string> = new Map([
  ['yangshao', '#F5EFE2'], ['longshan', '#F5EFE2'], ['xiashang', '#F5EFE2'],
  ['zhou', '#1F1B16'], ['hantang', '#1F1B16'], ['song', '#1F1B16']
]);

// 每年代 ink 达到 4.5:1 所需的最小 alpha。eraInkA() 按此下限钳制——
// 调用方要的是"弱化文字"的视觉层级，不是"看不清"。低于此值即视为可读性缺陷。
// 数值由 tools/check_contrast.py 反解得出，改动色板必须重跑该脚本。
const ERA_INK_FLOORS: Map<string, string> = new Map([
  ['yangshao', 'D0'], ['longshan', '90'], ['xiashang', 'F0'],
  ['zhou', 'FF'], ['hantang', 'E0'], ['song', 'E0']
]);

// 年代色的文字变体：供画布标签、年代名等"把年代色当字色"的场合使用
const ERA_TEXT: Map<string, string> = new Map([
  ['yangshao', '#8E4028'], ['longshan', '#332E29'], ['xiashang', '#4E6B52'],
  ['zhou', '#5E6D72'], ['hantang', '#8B6833'], ['song', '#5F717B']
]);

// 年代色在**深底**（展柜 ON_DARK_PANEL #1C1A18）上的提亮变体。
// 原块色在深底上最低只有 1.29:1（龙山），完全不可读。提亮只抬明度、
// 不动色相，与 ERA_TEXT 同一手法。这是白盒体系里层色唯一以"文字"
// 身份出现在深底上的地方（RelicPage 文物名）。
const ERA_TEXT_DARK: Map<string, string> = new Map([
  ['yangshao', '#D98A6A'], ['longshan', '#9C948B'], ['xiashang', '#7FA487'],
  ['zhou', '#9DB0B7'], ['hantang', '#B98A44'], ['song', '#7F97A4']
]);

const ERA_TEXTURE_LINES: Map<string, string> = new Map([
  ['yangshao', '#1AF5EFE2'], ['longshan', '#1AF5EFE2'], ['xiashang', '#1AF5EFE2'],
  ['zhou', '#141F1B16'], ['hantang', '#141F1B16'], ['song', '#141F1B16']
]);

const ERA_NAMES: Map<string, string> = new Map([
  ['yangshao', '仰韶'], ['longshan', '龙山'], ['xiashang', '夏商'],
  ['zhou', '周'], ['hantang', '汉唐'], ['song', '宋']
]);

// 年代跨度（P1 年代块等宽小字）：口径与首屏"公元前5000—公元1279"对齐
const ERA_SPANS: Map<string, string> = new Map([
  ['yangshao', '约前5000 — 前3000'], ['longshan', '约前3000 — 前2000'],
  ['xiashang', '约前2070 — 前1046'], ['zhou', '前1046 — 前221'],
  ['hantang', '前202 — 907'], ['song', '960 — 1279']
]);

// P1 年代块封面（各期取一张遗址/器物氛围图，白字直压；AI 生成图统一挂"示意图"角标）
const ERA_COVER_IMAGES: Map<string, string> = new Map([
  ['yangshao', 'images/mianchi_yangshao/caitao_pian.webp'],
  ['longshan', 'images/dahecun/taoyao_yiji.webp'],
  ['xiashang', 'images/erlitou/gongcheng_jianzhuji.webp'],
  ['zhou', 'images/dongzhou_wangcheng/chengqu_hangtu.webp'],
  ['hantang', 'images/hanwei_luoyangcheng/changhe_men.webp'],
  ['song', 'images/dongjing/zhouqiao_qiaoti.webp']
]);

export function eraColor(era: string): string {
  const c = ERA_COLORS.get(era);
  return c !== undefined ? c : '#332E29';
}

export function eraInk(era: string): string {
  const c = ERA_INKS.get(era);
  return c !== undefined ? c : '#F5EFE2';
}

export function eraTextureLine(era: string): string {
  const c = ERA_TEXTURE_LINES.get(era);
  return c !== undefined ? c : '#1AF5EFE2';
}

export function eraName(era: string): string {
  const n = ERA_NAMES.get(era);
  return n !== undefined ? n : era;
}

export function eraSpan(era: string): string {
  const s = ERA_SPANS.get(era);
  return s !== undefined ? s : '';
}

export function eraCoverImage(era: string): string {
  const p = ERA_COVER_IMAGES.get(era);
  return p !== undefined ? p : '';
}

// #RRGGBB → #AARRGGBB（叠层渐变/角标用）；alpha 两位 hex，如 'B3'
export function eraColorA(era: string, alpha: string): string {
  return '#' + alpha + eraColor(era).slice(1);
}

// 文字专用：alpha 会被钳制到该年代的 ERA_INK_FLOORS 下限。
// 背景遮罩请继续用 eraColorA()，那条路径不做钳制。
export function eraInkA(era: string, alpha: string): string {
  const floor = ERA_INK_FLOORS.get(era);
  const lo = floor !== undefined ? floor : 'D0';
  return '#' + (parseInt(alpha, 16) >= parseInt(lo, 16) ? alpha : lo) + eraInk(era).slice(1);
}

// 年代色的文字变体：供画布标签、年代名等"把年代色当字色"的场合使用
export function eraText(era: string): string {
  const c = ERA_TEXT.get(era);
  return c !== undefined ? c : '#332E29';
}

// 年代色的深底文字变体：RelicPage 文物名等深底场合专用
export function eraTextDark(era: string): string {
  const c = ERA_TEXT_DARK.get(era);
  return c !== undefined ? c : '#9C948B';
}

// 展柜图的辉光渐变端点：年代色 40% 不透明。仅作发光，不承载信息，
// 不受 eraInkA() 的可读性下限约束。
const GLOW_ALPHA: string = '66';
export function eraGlow(era: string): string {
  return eraColorA(era, GLOW_ALPHA);
}

// 页面底与主墨色的旧名。值已迁到 DesignTokens，这里保留别名，
// 让十个页面不必在同一个改动里同时改 import 和字面量。
// 新代码直接用 SURFACE_PAGE / INK。
export const THEME_BG: string = SURFACE_PAGE;
export const THEME_INK: string = INK;
