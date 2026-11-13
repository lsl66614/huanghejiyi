// entry/src/main/ets/common/Time.ets —— 纯函数，禁 @kit
export function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

export function stamp(ts: number): string {
  if (ts <= 0) { return '—'; }
  const d = new Date(ts);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

// 冲突裁决须在一分钟内区分先后，故版本号带秒
export function stampSec(ts: number): string {
  if (ts <= 0) { return '—'; }
  const d = new Date(ts);
  return `${stamp(ts)}:${pad2(d.getSeconds())}`;
}

// 三要素栏宽度有限，最后同步只显示到分
export function stampShort(ts: number): string {
  if (ts <= 0) { return '—'; }
  const d = new Date(ts);
  return `${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}
