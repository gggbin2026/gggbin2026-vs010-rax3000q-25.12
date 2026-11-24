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

# ── 4. 显式关闭「防火墙 + IPv6 + 无用插件」：# 注释行不会进 .config，这里兜底 ──
# 纯二层桥不做三层转发；firewall4 会带一整套 nft 规则和菜单链，是系统问题主要来源。
# 第 44 次：用户明确要关 IPv6、只留 TTYD，这里把 v6 相关包也全部显式 n。
for k in firewall4 firewall \
         odhcpd odhcpd-ipv6only odhcp6c luci-proto-ipv6 ip6tables kmod-ip6tables \
         luci-mod-dashboard luci-app-librespeed luci-app-adblock luci-app-sqm \
         luci-app-wireguard luci-app-statistics luci-theme-material luci-theme-edge \
         smartdns https-dns-proxy iperf3 htop nano curl wget-ssl \
         luci-lib-ipkg luci-i18n-opkg-zh-cn; do
  echo "# CONFIG_PACKAGE_$k is not set" >> .config
done
echo "[gen-config] ✓ 防火墙/IPv6/无用包已显式 n（只留 SSH dropbear + luci-app-ttyd）"
echo "[gen-config] ✓ CONFIG_IPV6=n 由 common.seed 写入，defconfig 不会改回 y"

# ── 5. 包存在性核对（第 45 次重写，修掉「误删必需包」）──
# 旧版用 `./scripts/feeds list | awk '{print $1}'` 探测，在 qosmio 25.12-nss 上
# 对「明明刚 feeds install -a 装好的包」也报找不到，于是把
#   ath11k-firmware-ipq5018-qcn6122 / luci-app-ttyd
# 从 .config 里 sed 删掉并显式 n（见 2026-11-24 13:56 编译日志 4265 行）。
# 后果：射频固件没编进去、TTYD 没编进去；而且 =n 的主题会被上面的
# `grep -q '^CONFIG_PACKAGE_$p=y$' || continue` 跳过，旧逻辑自称的
# 「防主题白屏」其实一次都没生效，只误伤了必需包。
#
# 新原则：
#   ① 必需包（无线固件 / SSH / TTYD）永远不自动删 —— 删了比留着危害大得多。
#   ② 只有「主题类且 =y」才做「feed 里不存在就删」：主题目录不存在会让
#      mediaurlbase 指向空气 → LuCI 白屏 / 主题切换后 500，这条必须留。
#   ③ 探测改用文件存在性（feeds install -a 会生成
#      package/feeds/*/<pkg>/Makefile），不再依赖 feeds list 输出格式。
_pkg_present() {
    if [ -d package/feeds ] && \
       find package/feeds -maxdepth 3 -type f -path "*/$1/Makefile" -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi
    if [ -d feeds ] && \
       find feeds -maxdepth 5 -type f -path "*/$1/Makefile" -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi
    if ./scripts/feeds list -a 2>/dev/null | awk '{print $1}' | grep -qx "$1"; then
        return 0
    fi
    return 1
}
for p in luci-theme-argon luci-theme-footstrap luci-theme-material luci-theme-edge; do
  grep -q "^CONFIG_PACKAGE_$p=y$" .config || continue
  if ! _pkg_present "$p"; then
    sed -i "/^CONFIG_PACKAGE_$p=y$/d" .config
    echo "# CONFIG_PACKAGE_$p is not set" >> .config
    echo "::warning::主题 $p 在当前 feeds 中不存在，已从 .config 显式关闭（避免 LuCI 指向空气）"
  fi
done
# 必需包清单：defconfig 之后只核对、只警告，绝不从这里删
REQUIRED_PKGS="dropbear ttyd luci-app-ttyd ath11k-firmware-ipq5018-qcn6122 kmod-ath11k-ahb"

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
# 第 45 次：必需包核对（只警告，绝不阻断、绝不删除）
# 若这里报缺包，说明 feed 真的没有或 defconfig 丢符号，去查 feeds.conf.default，
# 而不是回头把 seed 里的 =y 注释掉 —— 那正是上一版把 TTYD 弄丢的原因。
for p in $REQUIRED_PKGS; do
  grep -q "^CONFIG_PACKAGE_$p=y$" .config \
    || echo "::warning::必需包 $p 未进入 .config（检查 feeds 是否 update/install 完整）"
done

grep -q "^$DEV_SYM=y" .config || {
  echo "::error::defconfig 把设备符号 $DEV_SYM 丢了"
  echo "::error::检查 ① board-inject.sh 是否注入 define Device/$DEV + TARGET_DEVICES +="
  echo "::error::      ② awk 是否 gawk（tmp/.targetinfo 为 0 字节就是这个症状）"
  echo "::error::      ③ ./scripts/feeds update -a && install -a 是否已跑"
  exit 1
}
echo "[gen-config] ✓ $(grep -c '^CONFIG_.*=y$' .config) 个 =y 符号，设备 $DEV 保住"
echo "[gen-config] 已编 luci-app-*: $(grep -c '^CONFIG_PACKAGE_luci-app-.*=y$' .config || true) 个（应为 1：ttyd）"
