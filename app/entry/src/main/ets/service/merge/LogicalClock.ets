// entry/src/main/ets/service/merge/LogicalClock.ets —— 纯函数，禁 @kit
//
// 为什么需要它（设计方案 §6 已知限制、README「已知限制」）：LWW 原本直接取
// 设备本地 Date.now()。两个最常见的致「旧编辑反赢」的场景：
//   1. 设备系统时钟被回拨（NTP 尚未对齐、手动改时间）→ 墙钟倒退；
//   2. 同一台设备同一毫秒连写两次（连点收藏/笔记）→ 后写的时间戳并不比
//      先写的大，LWW 平局落到 deviceId 字典序，与「谁后写」的实际因果无关。
//
// 这里的办法是给每台设备一份**单调逻辑时钟（高水位）**：写入时间戳取
//     now = 墙钟 > 高水位 ? 墙钟 : 高水位 + 1
// 即严格大于上次写入，且不小于墙钟。高水位持久化在 sync_meta.lastWrite，
// 每台真机、每份仿真档案各一份（见 LocalRdbImpl.nextWriteTime）。
//
// 边界诚实说明：这只修掉「本地回拨 + 同毫秒踩踏」两类**本机**致因。两台真机
// 系统时间绝对偏差很大的场景仍可能按墙钟误裁决——属已知限制，靠系统侧
// 时钟同步（SNTP/NTP）兜底，不在应用层逻辑时钟的收敛范围内。

// 由「本库上次写入高水位 last」与「当前墙钟 wall」算出本次写入时间戳。
// 保证结果严格大于 last（同一设备连写不产生并列时间戳），且不小于 wall。
export function monotonicNow(last: number, wall: number): number {
  if (wall > last) {
    return wall;
  }
  return last + 1;
}

// 连续写入的时间戳序列。用于测试与演示「连写也单调」。
// 从 startWall 起每次都以「上一次结果」为 last，返回 n 个严格递增的值。
export function monotonicSeries(startWall: number, n: number): number[] {
  const out: number[] = [];
  let last = 0;
  for (let i = 0; i < n; i++) {
    const t: number = i === 0 ? monotonicNow(last, startWall) : monotonicNow(last, 0);
    out.push(t);
    last = t;
  }
  return out;
}
