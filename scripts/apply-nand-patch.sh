#!/bin/bash
# 条件式应用「复旦微 FM25LS01 SPI-NAND」补丁（V2 批次专用，默认不启用）
# 用法: scripts/apply-nand-patch.sh <source-tree> <baseline>
# 由 scripts/prepare.sh 调用；开关 NAND_PATCH=1|true 才生效。
#
# 为什么默认关：
#   · 这是 PZ-L8 V2 批次的芯片（ID 0xA5），替代 V1 的 ESMT F50D1G41LB。
#   · VS010 原厂是 ESMT，RAX3000Q 闪存型号未实证；V1 板子打它等于白打。
#   · 补丁声明 NAND_ECCREQ(8,512)，而数据手册写片上 1-bit/512。QPIC 控制器
#     按声明值配自己的硬件 ECC，8 是补丁作者在 V2 板上的经验值；声明值与
#     U-Boot 写入时不一致会读不出 UBI（-74 EUCLEAN）→ 变砖。
#   · 上游自己写明：只验证到「干净应用、能编过」，没在真 FM25LS01 上跑过。
# 什么时候开：dmesg 报 unknown flash ID / EUCLEAN、确认板子是 V2 批次。
set -euo pipefail
TREE="${1:?source-tree}"; BASE="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/patches/440-mtd-spinand-add-support-for-FudanMicro-FM25LS01.patch"
NAND_PATCH="${NAND_PATCH:-0}"
record(){ printf 'NAND_PATCH=%s\n' "$1" >> "$ROOT/build.env" 2>/dev/null || true; }

echo "==================== [nand-patch] baseline=$BASE enable=$NAND_PATCH =========="

# ── 1. 总开关（默认 0）──
case "$NAND_PATCH" in
  1|true|yes|on) ENABLE=1 ;;
  *) ENABLE=0 ;;
esac
if [ "$ENABLE" != 1 ]; then
  echo "  ℹ 未开启 → 不打补丁（默认）。V1/ESMT 板子不需要，打了反而多一个未经实机验证的变量"
  record 'off'
  exit 0
fi

# ── 2. 基线门：补丁放在 pending-6.12，6.18 不适用 ──
case "$BASE" in
  qosmio-25.12-nss|official-25.12.6) ;;
  *)
    echo "  ::warning::基线 $BASE 不是 6.12 → 跳过（该 patch 属 pending-6.12，6.18 不适用）"
    record "skipped-baseline-$BASE"
    exit 0 ;;
esac

# ── 3. 前置：fmsh.c 由 OpenWrt 的 generic backport 401/435 带进来 ──
F="$TREE/drivers/mtd/nand/spi/fmsh.c"
if [ ! -f "$F" ]; then
  echo "  ::warning::树里没有 drivers/mtd/nand/spi/fmsh.c → 跳过（fmsh.c 本身由 backport 401/435 加入）"
  echo "  ::warning::先确认 target/linux/generic/backport-6.12/ 里有 401-* / 435-* spinand-fmsh 补丁"
  record 'skipped-no-fmsh'
  exit 0
fi
if grep -q 'FM25LS01' "$F"; then
  echo "  ✓ fmsh.c 已含 FM25LS01，无需重复应用（幂等）"
  record 'already-present'
  exit 0
fi
if [ ! -s "$PATCH" ]; then
  echo "  ::warning::缺 $PATCH → 跳过"
  record 'skipped-no-patch'
  exit 0
fi

# ── 4. 先 check 再 apply；失败只警告，不砸整次编译 ──
cd "$TREE"
if ! git apply --check "$PATCH" 2>/tmp/nand-apply-check.log; then
  echo "  ::warning::git apply --check 失败，上下文不匹配 → 跳过（不强行打，避免编不过）"
  sed 's/^/      /' /tmp/nand-apply-check.log | head -10 || true
  record 'skipped-context-mismatch'
  exit 0
fi
if ! git apply "$PATCH" 2>/tmp/nand-apply.log; then
  echo "  ::warning::git apply 失败 → 跳过；内核仍是未打补丁的干净树"
  sed 's/^/      /' /tmp/nand-apply.log | head -10 || true
  record 'skipped-apply-failed'
  exit 0
fi

echo "  ✓ 已应用 FM25LS01 补丁（ID 0xA5 / 2048B 页 / 128B OOB / 64 页每块 / 1024 块 / ECC 8bit@512）"
echo "  ⚠ 开机务必看 dmesg：EUCLEAN(-74) 说明 ECC 声明值与 U-Boot 不一致，立刻回退"
echo "  ⚠ 上游未做真机验证；只在确认是 V2 批次且报 unknown flash ID 时才开"
record 'applied-FM25LS01-0xA5-ECC8'
