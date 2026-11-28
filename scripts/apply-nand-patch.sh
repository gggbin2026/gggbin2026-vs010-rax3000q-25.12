#!/bin/sh
# 用法: sh scripts/apply-nand-patch.sh <WORKSPACE> <KVER_HINT> <true|false>
set -eu
W=${1:-.}; HINT=${2:-}; ON=${3:-false}
[ "$ON" = true ] || { echo "[nand] 默认关闭，跳过"; exit 0; }
case "$HINT" in 6.12*|6.6*|6.1*) ;; *) echo "::warning::非 6.12 基线，NAND 补丁跳过"; exit 0 ;; esac
found=0
for p in "$W"/patches/*.patch; do
  [ -f "$p" ] || continue
  found=$((found+1))
  if (cd "$W/openwrt" && git apply --check "$p"); then
    (cd "$W/openwrt" && git apply "$p") && echo "[nand] 已应用 $(basename "$p")"
  else
    echo "::warning::$(basename "$p") 与当前内核源码不匹配，跳过（不停编）"
  fi
done
[ "$found" -gt 0 ] || echo "::warning::勾了 nand_patch 但 patches/ 下没有 .patch，跳过（见 patches/README.md）"
