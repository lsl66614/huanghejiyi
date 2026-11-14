#!/usr/bin/env bash
# tools/sync_probe_e2e.sh —— 模拟器上走通双档案同步 UI（含冲突演示）
#
# 用法：
#   bash tools/sync_probe_e2e.sh --dump            打印当前页所有文本
#   bash tools/sync_probe_e2e.sh --tap <x> <y> [s]  点一下
#   bash tools/sync_probe_e2e.sh --shot <名>        截图
#   bash tools/sync_probe_e2e.sh --conflict         跑完整冲突流程（需 App 在首页）
#
# 仿真语义（见 LoopbackAdapter.ets）：
#   exchange(dev, local)：把**本机**档案播种进「对端的袋」，
#   再取回「上次对端同步时留给我的那份」。
#   ⇒ 对方档案只有在对方先同步过一次之后才存在。
#
# 制造冲突的完整序列（每步都有可观测读数）：
#   1. A 建一条笔记            → A 本机 1 条
#   2. A 同步                  → 把 A 的档案播种进「B 的袋」
#   3. 切到 B，B 同步          → B 取回 A 的档案，B 本机记录数 0→1
#   4. B 改写同一条笔记        → B 的版本 updateTime 更晚
#   5. B 再同步一次            → 把 B 的新版本播种进「A 的袋」（漏这步则第 6 步无冲突）
#   6. 切回 A，A 同步          → A 取回 B 的版本 ⇒ 冲突历史出现「采信 B / 落选 A」
#
# ⚠️ 身份不是全局持久状态：SyncPage.aboutToAppear 每次进页面都调
#    setSimMode(true)，把身份重置回 deviceA。所以「切换身份」只在
#    **本次停留在同步面板期间**有效；离开面板再回来就回到 A。
#    ⇒ 改笔记必须在**切好身份之后**、且不重新进同步面板。
#
# ⚠️ 每个身份是一个独立 RDBStore（huanghe_memory.db.sim.<dev>），
#    A 的笔记和 B 的笔记本就是两个库里的两份数据。
set -u

export MSYS2_ARG_CONV_EXCL='*'
export PATH="$PATH:$(cygpath -u 'E:/OpenHarmony/Sdk/26.0.0/toolchains')"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/.sync_probe"
mkdir -p "$OUT"
cd "$OUT"

tap() { hdc shell uitest uiInput click "$1" "$2" >/dev/null 2>&1; sleep "${3:-2.5}"; }
typ() { hdc shell "uitest uiInput text '$1'" >/dev/null 2>&1; sleep 2; }

dump() {
  hdc shell uitest dumpLayout -p /data/local/tmp/sp.json >/dev/null 2>&1
  ( cd "$OUT" && hdc file recv /data/local/tmp/sp.json sp.json >/dev/null 2>&1 )
  python -c "
import sys, json
sys.stdout.reconfigure(encoding='utf-8')
d = json.load(open('sp.json', encoding='utf-8'))
o = []
def walk(n):
    a = n.get('attributes') or {}
    t = (a.get('text') or '').strip()
    if t: o.append((t, a.get('bounds') or ''))
    for c in n.get('children') or []: walk(c)
walk(d)
for t, b in o: print(repr(t), b)
"
}

# 只挑与同步判据有关的行
conflicts() {
  dump | grep -E "冲突|采信|落选|笔记标签|笔记 ·|记录|当前身份|仿真对端" || true
}

shot() {
  rm -f "$2"
  hdc shell snapshot_display -f "/data/local/tmp/$1" >/dev/null 2>&1
  ( cd "$OUT" && hdc file recv "/data/local/tmp/$1" "$2" >/dev/null 2>&1 )
  [ -s "$2" ] && echo "  截图 → $2" || echo "  ✗ 收图失败 $1"
}

# 完整冲突流程
run_conflict() {
  local NOTE="${1:-ProbeNote}"
  echo "① 我的 → 同步面板"
  tap 1119 2026 3
  tap 230 1285 3.5

  echo "② 随手笔记 → 新建一条"
  tap 115 198 3
  tap 230 1494 3.5
  tap 660 900 2
  hdc shell uitest uiInput keyEvent BACK >/dev/null 2>&1; sleep 1
  tap 660 900 2
  typ "$NOTE"
  tap 1157 219 3
  echo "   → $(dump | grep -c "$NOTE") 处出现该笔记"

  echo "③ 回同步面板 → A 同步（播种进 B 的袋）"
  tap 115 219 3
  tap 230 1285 3.5
  tap 969 1509 4.5

  echo "④ 切到 B → B 同步（取回 A 的档案）"
  tap 350 1509 3.5
  tap 969 1509 4.5
  conflicts

  echo "⑤ B 改写同一条笔记"
  tap 115 198 3
  tap 230 1494 3.5
  tap 1054 726 2.5
  tap 660 1300 2
  typ ' V2'
  tap 1157 219 3

  echo "⑥ 回同步面板 → 切 B → B 再同步（把新版播种进 A 的袋）"
  tap 115 219 3
  tap 230 1285 3.5
  tap 350 1509 3.5
  tap 969 1509 4.5

  echo "⑦ 切回 A → A 同步（⇒ 冲突）"
  tap 350 1509 3.5
  tap 969 1509 4.5
  conflicts
  shot sync_conflict.jpeg sync_conflict.jpeg
}

case "${1:-}" in
  --dump)      dump ;;
  --conflicts) conflicts ;;
  --shot)      shot "$2" "$2" ;;
  --tap)       tap "$2" "$3" "${4:-2.5}" ;;
  --type)      typ "$2" ;;
  --conflict)  run_conflict "${2:-ProbeNote}" ;;
  *)
    echo "用法: sync_probe_e2e.sh --dump | --conflicts | --shot <名> | --tap <x> <y> [s] | --type <文本> | --conflict [笔记文本]"
    exit 2
    ;;
esac
