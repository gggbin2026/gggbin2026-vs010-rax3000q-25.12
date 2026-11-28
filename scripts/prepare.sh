#!/bin/sh
# 本地一键预检（不 clone、不 make）：等价于 workflow 的前两步。
set -eu
W=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
sh "$W/scripts/verify.sh"
echo "[prepare] 解析默认基线："
sh "$W/scripts/resolve-baseline.sh" "$( . "$W/baseline.env"; echo "$DEFAULT_BASELINE" )"
echo "[prepare] 完成。真编译请到 Actions → Run workflow。"
