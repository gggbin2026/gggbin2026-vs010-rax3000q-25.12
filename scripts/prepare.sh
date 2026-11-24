#!/bin/bash
# 一站式：clone 新内核基线 → feeds → 板级注入 → 差异配置 → overlay 合并/升级
# 用法: scripts/prepare.sh <device> <mode> <baseline>
# 由两份 workflow 调用；本地也可跑（会 clone 到 ./openwrt，约 1~3 分钟起）
set -euo pipefail
D="${1:?rax3000q|vs010}"; MODE="${2:?wds|ap}"; BASE="${3:-qosmio-25.12-nss}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="$ROOT/openwrt"

# shellcheck disable=SC1091
source "$ROOT/baseline.env"
case "$BASE" in
  qosmio-25.12-nss) URL="$BASE_A_URL"; REF="$BASE_A_REF"; K="$BASE_A_KERNEL" ;;
  official-25.12.6) URL="$BASE_B_URL"; REF="$BASE_B_REF"; K="$BASE_B_KERNEL" ;;
  kuncy7-6.18-nss)  URL="$BASE_C_URL"; REF="$BASE_C_REF"; K="$BASE_C_KERNEL" ;;
  *) echo "::error::未知基线 $BASE"; exit 1 ;;
esac
echo "==================== [prepare] $D / $MODE / $BASE (内核 $K) ===================="

# ── 1. 源码：锁 tag/分支，不拉浮动 main ──
if [ -d "$TREE/.git" ]; then
  cd "$TREE"; git fetch --depth=1 origin "$REF" 2>/dev/null || true
  git reset --hard FETCH_HEAD 2>/dev/null || true
else
  git clone --depth=1 -b "$REF" "$URL" "$TREE"
  cd "$TREE"
fi
echo "  HEAD=$(git rev-parse --short HEAD)  REF=$REF"
echo "  SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)" > "$ROOT/build.env"
grep -rE 'LINUX_VERSION|KERNEL_PATCHVER' target/linux/qualcommax/Makefile target/linux/ipq50xx/Makefile 2>/dev/null | head -5 || true

# ── 1.5 NAND 补丁（V2 批次复旦微 FM25LS01 专用，默认不启用）──
# 开关 NAND_PATCH 由 workflow 传入；不满足条件只警告不停编，见 patches/README.md。
"$ROOT/scripts/apply-nand-patch.sh" "$TREE" "$BASE"

# ── 2. feeds：保留树自带（qosmio 有 NSS feed），只追加缺失源 ──
[ -f feeds.conf.default ] && cp -n feeds.conf.default feeds.conf.default.orig
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  key=$(echo "$line" | awk '{print $2}')
  grep -qE "^src-git(-full)?[[:space:]]+$key[[:space:]]" feeds.conf.default || echo "$line" >> feeds.conf.default
done < "$ROOT/feeds.conf.default"
./scripts/feeds update -a
./scripts/feeds install -a
echo "  ✓ feeds 就绪"

# ── 3. 板级注入（VS010 DTS / RAX3000Q 校验 / BDF 落盘）──
"$ROOT/scripts/board-inject.sh" "$D" "$TREE"

# ── 4. 差异配置（自动探测 target 符号）──
"$ROOT/scripts/gen-config.sh" "$D" "$MODE" "$TREE"

# ── 5. overlay 合并：files/ → files.<机型>/ → files.ap/（AP 最后生效）──
mkdir -p "$TREE/files"
cp -r "$ROOT/files/." "$TREE/files/"
[ -d "$ROOT/files.$D" ] && cp -r "$ROOT/files.$D/." "$TREE/files/"
if [ "$MODE" = ap ]; then
  [ -d "$ROOT/files.ap" ] || { echo "::error::缺 files.ap/"; exit 1; }
  cp -r "$ROOT/files.ap/." "$TREE/files/"
  sed -i "s/option hostname '\([^']*\)'/option hostname '\1-AP'/" "$TREE/files/etc/config/system" 2>/dev/null || true
else
  sed -i "s/option hostname '\([^']*\)'/option hostname '\1-WDS'/" "$TREE/files/etc/config/system" 2>/dev/null || true
fi
printf '%s\n' "$MODE" > "$TREE/files/etc/firmware_mode"
[ "$MODE" = ap ] && AP_IP=192.168.1.240 || AP_IP=192.168.1.241
AP_IP="$AP_IP" "$ROOT/scripts/port-overlay.sh" "$TREE/files"
echo "  ✓ overlay 合并完成，firmware_mode=$MODE，管理 IP=$AP_IP"

# 2026-11-24：无线满速五件套 + 状态页版本档案（在 port-overlay 之后，band 已升级）
"$ROOT/scripts/wifi-fullspeed.sh" "$TREE/files" "$BASE" "$MODE"
{
  echo "BASELINE=$BASE"
  echo "FW_MODE=$MODE"
  echo "DEVICE=$D"
  echo "KERNEL_EXPECT=$K"
  echo "WIFI_TARGET=fullspeed"
  echo "NSS_WIFI_OFFLOAD=conditional"
  echo "BUILT_AT=$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %Z')"
} >> "$ROOT/build.env"
cp "$ROOT/build.env" "$TREE/files/etc/build-info" 2>/dev/null || true

# 运行期新增脚本补执行位
chmod 755 "$TREE/files/usr/sbin/l2-guard" "$TREE/files/usr/sbin/wifi-fullspeed" \
          "$TREE/files/usr/sbin/art-check" "$TREE/files/usr/sbin/oem-stack-check" \
          "$TREE/files/etc/init.d/l2-guard" "$TREE/files/etc/init.d/wifi-fullspeed" \
          "$TREE/files/etc/uci-defaults/99-no-firewall" 2>/dev/null || true

# ── 6. 定稿 ──
make defconfig
echo "  ✓ make defconfig 收敛完成"
echo "  =y 包数: $(grep -c '^CONFIG_PACKAGE_.*=y$' .config || true)"
echo "  luci-app 数量: $(grep -c '^CONFIG_PACKAGE_luci-app-.*=y$' .config || true)（只应为 ttyd）"
echo "[prepare] ✓ 可以开始 make download / make"
