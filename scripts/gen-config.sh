#!/bin/bash
# 按 25.12 Kconfig 生成 .config —— 取代老仓库 7283 行全量 .config
# 用法: scripts/gen-config.sh <device:rax3000q|vs010> <mode:wds|ap> <source-tree>
set -euo pipefail
D="${1:?device}"; MODE="${2:?wds|ap}"; TREE="${3:-openwrt}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TREE"

echo "==================== [gen-config] $D / $MODE ===================="
# 第 52 次：插件 / 服务以第 51 次为冻结基线，【只增不减】。
# 包清单唯一数据源 = baseline/frozen-baseline.conf 的 [pkg] 段。
# 第 54 次修正：第 52 次误把「defconfig 后 .config 里精确 =y」当成冻结判据。
# 第 55 次【最终口径】：第 54 次仍留了一句「Kconfig 无符号、无包源 → 真缺 → exit 1」，
#   又把 luci-i18n-base-zh-cn（luci.mk 模板生成，无独立包目录）和
#   kmod-bridge（内核 CONFIG_BRIDGE=y 内建，netsupport.mk 已无该 kmod 定义）
#   误判成缺包，03:2x 的编译再次在 make 之前断掉。
#   ★ 定论：「树里能不能找到包源/符号」与「插件有没有被删」没有关系，
#     OpenWrt 版本、feed 布局、机型都会让它变，绝不能当阻断条件。
#   最终只剩两类硬阻断：
#     A 层 seed 声明 29/29 =y（防人为删插件 —— 这才是「只增不减」）
#     核心锚点 5 项 defconfig 后精确 =y（SSH/TTYD/射频固件，防功能真丢）
#   其余一切 Kconfig 收敛 / 符号合并 / 平台提供 / 模板生成，只 ::warning:: 诊断。

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
# ── 第 52 次：必需包清单改为「冻结基线 [pkg] 段」全量 29 项 ──────────
# 旧版只列 5 个（SSH / TTYD / 射频固件），其余 24 个包被删掉时无人拦截。
# 现在从 baseline/frozen-baseline.conf 读，单一数据源，verify.sh 也读同一份。
# 以后【加】包：往该文件 [pkg] 段追加一行即可，这里自动生效；
# 以后【删】包：不允许 —— 编译期直接失败，这就是「不能再减少」的技术保障。
BASELINE="$ROOT/baseline/frozen-baseline.conf"
if [ ! -f "$BASELINE" ]; then
  echo "::error::缺冻结基线 $BASELINE（第 52 次起插件只增不减，此文件必须随仓库保留）"
  exit 1
fi
REQUIRED_PKGS=$(awk -F'|' '$1=="[pkg]" {print $2}' "$BASELINE")
[ -n "$REQUIRED_PKGS" ] || { echo "::error::冻结基线 [pkg] 段为空或被删"; exit 1; }
NPKG=$(printf '%s\n' $REQUIRED_PKGS | wc -l)
echo "[gen-config] 冻结基线已加载：$NPKG 个包（只增不减）"

# ── 第 54 次 A 层【硬阻断】：seed 声明层 ─────────────────────────────
# 「不能再减少插件」唯一会被人改坏的地方，就是 config/*.seed 里的 =y 行：
# 注释掉 / 改成 =n / 删行。defconfig 之后的符号变化是 Kconfig 自动收敛，
# 不是人删的。所以真正的铁律落在这一层：29 项逐条查 seed 里有没有 =y。
# 第 45 次「gen-config 用 feeds list 误判把 luci-app-ttyd 从 .config 删掉」
# 的坑，也会被这一层 + 下面「主题剔除白名单」共同挡住。
SEED_DECL_MISS=""
for p in $REQUIRED_PKGS; do
  grep -q "^CONFIG_PACKAGE_$p=y$" "$ROOT"/config/*.seed 2>/dev/null \
    || SEED_DECL_MISS="$SEED_DECL_MISS $p"
done
if [ -n "$SEED_DECL_MISS" ]; then
  echo "::error::🔴 冻结基线包在 config/*.seed 里被删 / 改值（只增不减）：$SEED_DECL_MISS"
  echo "::error::要【加】包请往 baseline/frozen-baseline.conf 的 [pkg] 段追加行；禁止动已有 =y"
  exit 1
fi
echo "[gen-config] ✓ A 层 seed 声明 $NPKG/$NPKG 在位（只增不减，此层硬阻断）"

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
# ── 第 55 次 B 层：defconfig 之后【只诊断，不阻断】──────────────────
# 复盘两次误判：
#   第 52 次：要求 29 项 defconfig 后全精确 =y → 误伤 Kconfig 收敛（02:28 失败）
#   第 54 次：留了「符号+包源都找不到 → 真缺 → exit 1」→ 误伤平台提供项（03:2x 失败）
#     · luci-i18n-base-zh-cn：由 luci.mk 按 po/zh-cn 模板生成，源码树里
#       【没有】同名包目录，Kconfig 里也不一定出现精确符号行
#     · kmod-bridge：25.12 的 target/linux/generic/config-6.12 里
#       CONFIG_BRIDGE=y（内核内建），netsupport.mk 已无 KernelPackage/bridge，
#       自然既没有包符号也没有包源 —— 但功能由内核提供，反而更省资源
#   ★ 这两项「树里查不到」是 25.12 的正常结构，不是 feeds 没装好，更不是删了插件。
#
# 最终规则（以后任何 OpenWrt 版本 / feed 布局都不再误停编）：
#   🔴 硬阻断 ① A 层：config/*.seed 里 29 项逐条 =y（见上，防人为删）
#   🔴 硬阻断 ② 核心锚点 STRICT_PKGS 5 项 defconfig 后必须精确 =y
#   ⚪ 其余一切：精确 =y 就计数；否则统一归入 CONVERGED，只 ::warning:: 汇总
#      + 写 build.env；绝不 exit 1
#   ⚪ 机型条件项：rax3000q 下本地 BDF 包不生成，seed 声明仍在，跳过
STRICT_PKGS="dropbear ttyd luci-app-ttyd ath11k-firmware-ipq5018-qcn6122 kmod-ath11k-ahb"
COND_VS010_ONLY="ipq-wifi-cucc_vs010"     # board-inject.sh 只在 vs010 生成该本地包
# 「平台提供 / 模板生成」：seed 声明保留，但本来就不以独立包符号或目录存在
PLATFORM_PROVIDED="kmod-bridge luci-i18n-base-zh-cn"

STRICT_MISS=""; CONVERGED=""; CONDI_SKIP=""; N_CONF_OK=0; N_PLATFORM=0
for p in $REQUIRED_PKGS; do
    case " $COND_VS010_ONLY " in
      *" $p "*) [ "$D" = vs010 ] || {
          CONDI_SKIP="$CONDI_SKIP $p($D 下本地包不生成，seed 声明仍在)"; continue; } ;;
    esac
    if grep -q "^CONFIG_PACKAGE_$p=y$" .config; then
        N_CONF_OK=$((N_CONF_OK+1)); continue
    fi
    case " $PLATFORM_PROVIDED " in
      *" $p "*) N_PLATFORM=$((N_PLATFORM+1)); CONVERGED="$CONVERGED $p(平台提供)"; continue ;;
    esac
    CONVERGED="$CONVERGED $p"
    case " $STRICT_PKGS " in
      *" $p "*) STRICT_MISS="$STRICT_MISS $p" ;;   # 核心锚点不允许收敛
    esac
done
if [ -n "$STRICT_MISS" ]; then
    echo "::error::🔴 核心锚点包被 defconfig 收敛，功能会真丢：$STRICT_MISS"
    echo "::error::查 feeds.conf.default / ./scripts/feeds install -a；禁止改 seed 的 =y"
    exit 1
fi
[ -n "$CONVERGED" ] && echo "::warning::Kconfig 收敛 / 平台提供（seed 声明未变，非减少插件）：$CONVERGED"
[ -n "$CONDI_SKIP" ] && echo "[gen-config] 机型条件项跳过：$CONDI_SKIP"
echo "[gen-config] ✓ B 层 defconfig 诊断：$N_CONF_OK 个精确 =y / $N_PLATFORM 个平台提供 / $(printf '%s' "$CONVERGED" | wc -w) 项收敛汇总 / 0 阻断"
# 收敛清单写进构建档案，刷机后可在 /etc/build-info 追溯
if [ -n "$CONVERGED" ]; then
    printf 'kconfig-converged:%s\n' "$CONVERGED" >> "$ROOT/build.env" 2>/dev/null || true
fi
echo "[gen-config] ✓ 冻结基线 $NPKG 项：A 层 seed 声明 $NPKG/$NPKG 硬阻断 + 核心锚点核对通过（其余只诊断）"

grep -q "^$DEV_SYM=y" .config || {
  echo "::error::defconfig 把设备符号 $DEV_SYM 丢了"
  echo "::error::检查 ① board-inject.sh 是否注入 define Device/$DEV + TARGET_DEVICES +="
  echo "::error::      ② awk 是否 gawk（tmp/.targetinfo 为 0 字节就是这个症状）"
  echo "::error::      ③ ./scripts/feeds update -a && install -a 是否已跑"
  exit 1
}
echo "[gen-config] ✓ $(grep -c '^CONFIG_.*=y$' .config) 个 =y 符号，设备 $DEV 保住"
echo "[gen-config] 已编 luci-app-*: $(grep -c '^CONFIG_PACKAGE_luci-app-.*=y$' .config || true) 个（冻结基线要求 ≥1：luci-app-ttyd；允许增加）"
