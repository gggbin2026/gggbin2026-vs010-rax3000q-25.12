#!/bin/bash
# 按 25.12 Kconfig 生成 .config —— 取代老仓库 7283 行全量 .config
# 用法: scripts/gen-config.sh <device:rax3000q|vs010> <mode:wds|ap> <source-tree>
set -euo pipefail
D="${1:?device}"; MODE="${2:?wds|ap}"; TREE="${3:-openwrt}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TREE"

echo "==================== [gen-config] $D / $MODE ===================="

# ── 1. 自动探测 target / subtarget（不写死符号）──
if [ -f target/linux/qualcommax/image/ipq50xx.mk ]; then
  TARGET=qualcommax; SUB=ipq50xx; IMGMK=target/linux/qualcommax/image/ipq50xx.mk
  echo "[gen-config] target = qualcommax / ipq50xx（官方 25.12 布局）"
elif [ -f target/linux/ipq50xx/image/Makefile ]; then
  TARGET=ipq50xx; IMGMK=target/linux/ipq50xx/image/Makefile
  SUB=$(ls -d target/linux/ipq50xx/*/ 2>/dev/null | head -1 | xargs -r basename)
  SUB=${SUB:-arm}
  echo "[gen-config] target = ipq50xx / $SUB（QSDK 风格树）"
else
  echo "::error::找不到 ipq50xx 的 image Makefile，基线可能不是 ipq50xx 树"; exit 1
fi

# ── 2. 设备符号 ──
case "$D" in
  vs010)    DEV=unicom_vs010;    LEGACY_DEV=cucc_vs010 ;;
  rax3000q) DEV=cmcc_rax3000q;   LEGACY_DEV=cmcc_rax3000q ;;
  *) echo "::error::未知机型 $D"; exit 1 ;;
esac
if grep -q "^define Device/$LEGACY_DEV" "$IMGMK" 2>/dev/null; then DEV="$LEGACY_DEV"; fi
DEV_SYM="CONFIG_TARGET_${TARGET}_${SUB}_DEVICE_${DEV}"
echo "[gen-config] 设备符号 = $DEV_SYM"

# ── 3. 写 .config（差异式，交给 defconfig 补齐依赖）──
: > .config
{
  echo "CONFIG_TARGET_${TARGET}=y"
  echo "CONFIG_TARGET_${TARGET}_${SUB}=y"
  echo "$DEV_SYM=y"
  echo "CONFIG_TARGET_BOARD=\"$TARGET\""
  echo "CONFIG_TARGET_SUBTARGET=\"$SUB\""
} >> .config

for seed in common themes "$MODE"; do
  f="$ROOT/config/$seed.seed"
  [ -f "$f" ] || { echo "::error::缺 $f"; exit 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"; line="$(echo "$line" | xargs)"
    [ -z "$line" ] && continue
    case "$line" in
      *=y) echo "$line" >> .config ;;
      *=n) echo "# ${line%=n} is not set" >> .config ;;
      *)   echo "::warning::种子里有非 CONFIG 行，已忽略: $line" ;;
    esac
  done < "$f"
done

# ── 4. 显式关闭「防火墙 + 无用插件」：# 注释行不会进 .config，这里兜底 ──
# 纯二层桥不做三层转发；firewall4 会带一整套 nft 规则和菜单链，是系统问题主要来源。
for k in firewall4 firewall odhcpd-ipv6only \
         luci-mod-dashboard luci-app-librespeed luci-app-adblock luci-app-sqm \
         luci-app-wireguard luci-app-statistics luci-theme-material luci-theme-edge \
         smartdns https-dns-proxy iperf3 htop nano curl wget-ssl \
         luci-lib-ipkg luci-i18n-opkg-zh-cn; do
  echo "# CONFIG_PACKAGE_$k is not set" >> .config
done
echo "[gen-config] ✓ 防火墙与 18 类无用包已显式 n（luci-app-ttyd / dropbear 保留）"

# ── 5. 第三方包若 feed 没加，提前给可见警告（不中断编译）──
for p in ath11k-firmware-ipq5018-qcn6122 luci-theme-argon luci-theme-footstrap \
         luci-theme-material ttyd luci-app-ttyd; do
  grep -q "^CONFIG_PACKAGE_$p=y$" .config || continue
  if ! ./scripts/feeds list 2>/dev/null | awk '{print $1}' | grep -qx "$p" && \
     ! grep -rq "^PKG_NAME:=$p\|^Package/$p" feeds/ package/ 2>/dev/null; then
    # 关键：不能只 warning。defconfig 会静默丢掉未知符号，而 /etc/config/luci
    # 可能仍指向不存在的主题目录 → LuCI 白屏 / 主题切换后 500。
    # 这里直接从 .config 删掉并显式 n，保证「配置与镜像里真实存在的主题一致」。
    sed -i "/^CONFIG_PACKAGE_$p=y$/d" .config
    echo "# CONFIG_PACKAGE_$p is not set" >> .config
    echo "::warning::$p 在当前 feeds 中未找到，已从 .config 显式关闭（避免主题指向空气）"
  fi
done

# GNU awk 是 OpenWrt 的硬依赖（include/scan.awk 用 asort）。mawk 会让
# tmp/.targetinfo 变成 0 字节，进而让 defconfig 把全部设备符号丢掉。
# GitHub Actions 的 apt 步已装 gawk；这里只给可见提示，不阻断。
if ! awk -W version 2>&1 | grep -qi 'GNU Awk\|gawk'; then
  echo "::warning::当前 awk 不是 GNU awk，OpenWrt 需要 gawk（asort）；CI 环境已装"
fi
if ! make defconfig; then
  echo "::error::make defconfig 失败（常见原因：缺 gawk / ncurses / feeds 未 update）"
  exit 1
fi
grep -q "^$DEV_SYM=y" .config || {
  echo "::error::defconfig 把设备符号 $DEV_SYM 丢了"
  echo "::error::检查 ① board-inject.sh 是否注入 define Device/$DEV + TARGET_DEVICES +="
  echo "::error::      ② awk 是否 gawk（tmp/.targetinfo 为 0 字节就是这个症状）"
  echo "::error::      ③ ./scripts/feeds update -a && install -a 是否已跑"
  exit 1
}
echo "[gen-config] ✓ $(grep -c '^CONFIG_.*=y$' .config) 个 =y 符号，设备 $DEV 保住"
echo "[gen-config] 已编 luci-app-*: $(grep -c '^CONFIG_PACKAGE_luci-app-.*=y$' .config || true) 个（应为 1：ttyd）"
