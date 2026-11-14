#!/usr/bin/env bash
# tools/press_probe_e2e.sh —— 在模拟器上实测按压反馈（端到端像素探针）
#
# 为什么要有这个脚本：按压反馈的**写法正确**与**屏幕上有反应**是两件事。
# 2026-10-09 那一轮 56 处 stateStyles({ pressed }) 全部编译通过、全部过门禁，
# 逐像素实测却零变化——静态检查证明不了任何事。
#
# 三个必须踩准的坑（都是本脚本踩出来的）：
#
# 1. **uinput -T -d 是一次性事件，进程随即退出，按下态不保持。**
#    `uinput -T -m X Y X Y -k <ms>` 才会保持手指在原位（keep time）。
#    `-d` + `-u` 配对会让探针永远抓到 0% —— 那不是「按压态没生效」，
#    是「根本没按住」。
#
# 2. **坐标必须落在目标元素上，否则 onTouch 压根不触发。**
#    探到空白处会得到干净的 0%，看起来像「实现失效」。先 dumpLayout
#    拿到目标文本的 bounds，再取其中点。
#
# 3. **状态变更不能包在 animateTo 里。**
#    `animateTo(anim, () => { this.pressed = true })` 在 ArkUI 上会让
#    状态变更与属性动画(.animation())互相打断，按下态在屏上不出现。
#    正确写法是直接赋值：`.animation(pressAnim())` 自己会做插值。
#    这一点只有逐像素比对能发现——编译通过、onTouch 也确实触发了。
#
# 另有一条基线纪律：**对照基线必须与按压帧在同一页面、同一时刻**。
# 用旧截图当基线会把「状态栏时钟跳了」「图片懒加载完成」算成按压反馈。
# 本脚本在按压前现抓基线，并先做一次「空闲两帧」自检：两帧必须逐字节
# 相同，否则说明画面本身在动，此时的差异不可归因。
#
# 用法：
#   bash tools/press_probe_e2e.sh <x> <y> <x1> <y1> <x2> <y2> [标签]
#     x y     目标元素中心坐标（设备像素）
#     x1 y1 x2 y2  采样框（探针比对的区域）
#     标签     打印用的名字，默认 "target"
#
#   bash tools/press_probe_e2e.sh --by-text "<文本>" [标签]
#     自动 dumpLayout 找到该文本的 bounds，取中心点当目标，
#     采样框取该 bounds 外扩 12vp。**强烈建议用这个形式**：
#     手写坐标一旦落空（页面已被上一次探针的点击跳走），探针会给出
#     干净的 0%，看起来像「按压态没生效」，实则根本没按到东西。
set -u

# MSYS2_ARG_CONV_EXCL='*' 阻止 MSYS 把 /data/... 这类设备端路径改写成
# Windows 路径。⚠️ 但**不能**同时设 MSYS_NO_PATHCONV=1：它会连 PATH 里的
# Windows 形式路径一起停止转换，于是 bash 无法用该条目找到 hdc
# （报 "hdc: command not found"）。故 PATH 项单独用 cygpath 转成 POSIX 形式。
export MSYS2_ARG_CONV_EXCL='*'
SDK_TOOLS="$(cygpath -u 'E:/OpenHarmony/Sdk/26.0.0/toolchains')"
export PATH="$PATH:$SDK_TOOLS"

if [ "${1:-}" = "--by-text" ]; then
  WANT="${2:?用法: press_probe_e2e.sh --by-text \"<文本>\" [标签]}"
  LABEL="${3:-$WANT}"
  HERE0="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  OUT0="$HERE0/.press_probe"
  mkdir -p "$OUT0"
  hdc shell uitest dumpLayout -p /data/local/tmp/pp_layout.json >/dev/null 2>&1
  ( cd "$OUT0" && hdc file recv /data/local/tmp/pp_layout.json pp_layout.json >/dev/null 2>&1 )
  read -r TARGET_X TARGET_Y BOX_X1 BOX_Y1 BOX_X2 BOX_Y2 <<<"$(
    python "$(cygpath -w "$HERE0/press_probe.py")" --locate       "$(cygpath -w "$OUT0/pp_layout.json")" "$WANT")"
  if [ -z "${TARGET_X:-}" ]; then
    echo "✗ 在当前页面找不到文本「$WANT」——请确认 App 停在该元素所在的页。" >&2
    exit 3
  fi
  echo "目标文本「$WANT」→ 中心 ($TARGET_X, $TARGET_Y)，采样框 ($BOX_X1,$BOX_Y1)-($BOX_X2,$BOX_Y2)"
else
TARGET_X="${1:?用法: press_probe_e2e.sh <x> <y> <x1> <y1> <x2> <y2> [标签]}"
TARGET_Y="${2:?}"
BOX_X1="${3:?}"
BOX_Y1="${4:?}"
BOX_X2="${5:?}"
BOX_Y2="${6:?}"
LABEL="${7:-target}"
fi

# hdc file recv 只认 Windows 风格路径：Git Bash 的 /e/... 形式它解析不了，
# 会报「no such file or directory」。故输出目录取 cygpath 转换后的 Windows 路径。
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_WIN="$(cygpath -w "$HERE/.press_probe")"
OUT="$HERE/.press_probe"
mkdir -p "$OUT"

echo "=== 按压探针：$LABEL @ ($TARGET_X, $TARGET_Y) 采样框 ($BOX_X1,$BOX_Y1)-($BOX_X2,$BOX_Y2) ==="

# 收图：hdc file recv 的本地路径必须相对当前工作目录（绝对路径会被
# 拼到 cwd 后面，找不到目录）。故这里 cd 到输出目录再用文件名收。
shot() {  # shot <设备端文件名> <本地文件名>
  # 两处坑（本机实测）：
  #  · 判据是**文件落盘**，不是 hdc 的退出码——recv 成功时也返回非零。
  #  · 本地路径用**纯文件名**：hdc 会把带盘符/斜杠的路径当成相对当前
  #    目录再拼一次，于是报「no such file or directory」。故先收到
  #    当前工作目录，再由调用方挪到输出目录。
  rm -f "$2"
  hdc shell snapshot_display -f "/data/local/tmp/$1" >/dev/null 2>&1
  hdc file recv "/data/local/tmp/$1" "$2" >/dev/null 2>&1
  if [ ! -s "$2" ]; then
    echo "收图失败: $1 -> $2" >&2
    return 1
  fi
}

# ---- 1. 空闲自检：两帧必须逐字节相同 ----
cd "$OUT" || exit 3
shot idle1.jpeg idle1.jpeg
sleep 1.5
shot idle2.jpeg idle2.jpeg
if ! cmp -s "$OUT/idle1.jpeg" "$OUT/idle2.jpeg"; then
  echo "✗ 空闲两帧就不同 —— 画面本身在动，本次差异不可归因于按压。"
  echo "  （常见原因：状态栏时钟、图片懒加载、加载动画）"
  exit 2
fi
echo "✓ 空闲自检通过（两帧逐字节相同，噪声为 0）"

# ---- 2. 基线（就在按压前现抓） ----
shot base.jpeg base.jpeg

# ---- 3. 按住：uinput -T -m 保持手指 12 秒，期间抓帧 ----
( hdc shell "uinput -T -m $TARGET_X $TARGET_Y $TARGET_X $TARGET_Y -k 12000" >/dev/null 2>&1 & )
sleep 1.5
shot press.jpeg press.jpeg
sleep 11   # 等 uinput 自己松手

# ---- 4. 比对 ----
# python 也不认 /e/... 形式（会报 can't open file 'E:\e\...'），
# 故脚本路径与图片路径都走 cygpath 转换后的 Windows 形式。
python "$(cygpath -w "$HERE/press_probe.py")" \
  "$(cygpath -w "$OUT/base.jpeg")" "$(cygpath -w "$OUT/press.jpeg")" \
  "$BOX_X1" "$BOX_Y1" "$BOX_X2" "$BOX_Y2"
rc=$?

echo
echo "截图留在 $OUT/ ：base.jpeg（基线） press.jpeg（按压中）"
exit $rc
