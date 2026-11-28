#!/bin/sh
# 用法: sh scripts/apply-nand-patch.sh <WORKSPACE> <KVER_HINT> <true|false>
set -eu
W=${1:-.}; HINT=${2:-}; ON=${3:-false}
[ "$ON" = true ] || { echo "[nand] 默认关闭，跳过"; exit 0; }
case "$HINT" in 6.12*|6.6*|6.1*) ;; *)
  # 6.18 基线：上游 target/linux/qualcommax/patches-6.18/0401 已内置 4-bit ECC 修复，
  # 由构建系统自动应用；本仓手动补丁不适用，如实说明并跳过（不是「不需要」）。
  echo "::warning::${HINT} 基线：上游 patches-6.18/0401 已内置 4-bit ECC 修复，本仓补丁跳过"; exit 0 ;; esac
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
