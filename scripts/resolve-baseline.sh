#!/bin/sh
# 解析 baseline.env → 输出可被 eval 的 6 行。
# 用法: sh scripts/resolve-baseline.sh <BASELINE_ID> [override_repo] [override_ref]
set -eu
W=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$W/baseline.env"
B=${1:-$DEFAULT_BASELINE}
OVR_REPO=${2:-}; OVR_REF=${3:-}
case "$B" in
  official-25.12|official-main|qosmio-25.12-nss|kuncy7-6.18-nss) ;;
  *) echo "echo \"::error::未知基线 $B\" >&2" >&2; exit 1 ;;
esac
K=$(printf '%s' "$B" | tr '.-' '__' | tr 'a-z' 'A-Z')
get(){ eval "printf '%s' \"\${$1$2}\""; }
REPO=$(get REPO_ "$K")
REF=$(get REF_ "$K")
KH=$(get KERNEL_HINT_ "$K")
NSS=$(get NSS_ "$K")
BOARD=$(get BOARD_ "$K")
[ -n "$OVR_REPO" ] && REPO="$OVR_REPO"
[ -n "$OVR_REF" ]  && REF="$OVR_REF"
[ -n "$REPO" ] || { echo "::error::基线 $B 未配置 REPO_$K（见 baseline.env）" >&2; exit 1; }
[ -n "$REF" ]  || { echo "::error::基线 $B 未配置 REF_$K" >&2; exit 1; }
printf 'SOURCE_REPO=%s\n' "$REPO"
printf 'SOURCE_REF=%s\n' "$REF"
printf 'KERNEL_HINT=%s\n' "$KH"
printf 'NSS=%s\n' "$NSS"
printf 'BOARD_POLICY=%s\n' "$BOARD"
printf 'BASELINE_ID=%s\n' "$B"
