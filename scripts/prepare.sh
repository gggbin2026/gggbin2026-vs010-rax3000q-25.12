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

# ── 第 58 次：安装【独立插件包】bridge-watchdog ──────────────────
# 标准 OpenWrt package 目录，能被 apk/opkg 单独装卸与升级；
# 必须在 gen-config.sh（内部 make defconfig）之前放进树，否则 CONFIG_PACKAGE_
# bridge-watchdog=y 会被 Kconfig 当作未知符号丢掉。
if [ -d "$ROOT/package/bridge-watchdog" ]; then
  rm -rf "$TREE/package/bridge-watchdog"
  cp -r "$ROOT/package/bridge-watchdog" "$TREE/package/bridge-watchdog"
  echo "  ✓ 已装入插件包 package/bridge-watchdog（可独立装卸/升级）"
else
  echo "::warning::缺 package/bridge-watchdog，机器狗将只由 files/ overlay 提供"
fi

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
# ── 第 54 次：构建树排除「包外野文件」（仓库文件原地保留，一个不删）──
# 网页上传是覆盖式，不会删多余文件。仓库里比冻结基线多出的 files/ 文件会被
# 上面的 cp -r 整目录带进固件：另一个自称「第 53 次」的 ntp-sync 三件套
# （又一个 5 分钟 NTP 守护，会和 ntp-poller 同时改系统时间）、
# dhcp-guard init.d（与 l2-guard 重复开机自启）、约 1.5MB QSDK 5.4 闭源
# WiFi 固件（Data.msc / regdb.bin，第 41 次已论证禁止进 6.12 主线 ath11k 镜像）。
# 这里只在【构建树】里剔除，不动仓库；KEEP_EXTRA_FILES=1 可原样保留。
if [ "${KEEP_EXTRA_FILES:-0}" != '1' ]; then
  EXTRA54=''
  for x in \
    etc/config/art-truth.conf \
    etc/config/ntp-sync \
    etc/config/oem-stack-truth.conf \
    etc/init.d/dhcp-guard \
    etc/init.d/ntp-sync \
    lib/firmware/IPQ5018/Data.msc \
    lib/firmware/IPQ5018/fw_ini_cfg.bin \
    lib/firmware/IPQ5018/qcn6122/Data.msc \
    lib/firmware/IPQ5018/qcn6122/fw_ini_cfg.bin \
    lib/firmware/IPQ5018/qcn6122/regdb.bin \
    lib/firmware/IPQ5018/regdb.bin \
    usr/sbin/ntp-sync \
    usr/sbin/wifi-art-cal \
    usr/sbin/wifi-stack-check; do
      if [ -e "$TREE/files/$x" ]; then
        rm -f "$TREE/files/$x"
        EXTRA54="$EXTRA54 $x"
      fi
  done
  # 清掉可能留下的空目录（只清 IPQ5018 这条，不碰其它 firmware 路径）
  rmdir "$TREE/files/lib/firmware/IPQ5018/qcn6122" "$TREE/files/lib/firmware/IPQ5018" 2>/dev/null || true
  [ -n "$EXTRA54" ] && echo "  ✓ 构建树已排除包外野文件（仓库不动）：$(echo "$EXTRA54" | wc -w) 个" \
    || echo "  · 构建树无包外野文件（干净）"
else
  echo "  ⚠ KEEP_EXTRA_FILES=1：包外 files/ 文件将原样进固件"
fi

printf '%s\n' "$MODE" > "$TREE/files/etc/firmware_mode"

# ── 第 58 次【插件化】：编译期默认【不注入】机器狗参数 ──────────────
# 用户要求「配置我自己来设置」：workflow 的 wds_delay / wds_peer 默认留空，
# 这里就一个字节都不改 tree/files/etc/config/wdsdog，出厂值原样保留；
# 用户刷后写 /etc/wdsdog.conf 或 uci set 自己定，首启也不会覆写。
# 只有用户【主动】在 Run workflow 里填了值才 sed（兼容老习惯）。
if [ "$MODE" = wds ] && { [ -n "${WDS_DELAY:-}" ] || [ -n "${WDS_PEER:-}" ]; }; then
  WD_DELAY="${WDS_DELAY:-}"; WD_PEER="${WDS_PEER:-}"
  if [ -n "$WD_DELAY" ]; then
    case "$WD_DELAY" in ''|*[!0-9]*) WD_DELAY=5 ;; esac
    [ "$WD_DELAY" -ge 1 ] && [ "$WD_DELAY" -le 120 ] || WD_DELAY=5
    sed -i -E "s/option delay '[0-9]*'/option delay '$WD_DELAY'/" "$TREE/files/etc/config/wdsdog"
  fi
  if [ -n "$WD_PEER" ]; then
    case "$WD_PEER" in
      auto|off) ;;
      *[!0-9.]*) WD_PEER=auto ;;
      *) ;;
    esac
    sed -i -E "s/option peer '[^']*'/option peer '$WD_PEER'/" "$TREE/files/etc/config/wdsdog"
  fi
  echo "  ✓ 用户在 workflow 显式填了机器狗参数，已注入：delay=${WD_DELAY:-不填} peer=${WD_PEER:-不填}"
else
  echo "  ✓ 机器狗插件：编译期不注入任何参数（配置由用户自设，见 /etc/wdsdog.conf）"
fi
# 第 48 次：AP / WDS 统一管理地址 172.10.10.241 / 255.255.252.0（/22）
AP_IP=172.10.10.241
# 第 51 次：NTP 固定周期（默认 5 分钟 = 300 秒）；非法值自动回落 5 分钟。
NTP_MIN="${NTP_POLL_MINUTES:-5}"
case "$NTP_MIN" in ''|*[!0-9]*) NTP_MIN=5 ;; esac
[ "$NTP_MIN" -ge 1 ] && [ "$NTP_MIN" -le 1440 ] || NTP_MIN=5
NTP_POLL=$(( NTP_MIN * 60 ))
AP_IP="$AP_IP" NTP_POLL="$NTP_POLL" "$ROOT/scripts/port-overlay.sh" "$TREE/files"
echo "  ✓ overlay 合并完成，firmware_mode=$MODE，管理 IP=$AP_IP，NTP 每 ${NTP_MIN} 分钟循环校时"

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
          "$TREE/files/etc/uci-defaults/99-no-firewall" \
          "$TREE/files/usr/sbin/ntp-poller" "$TREE/files/etc/init.d/ntp-poller" 2>/dev/null || true

# ── 6. 定稿 ──
make defconfig
echo "  ✓ make defconfig 收敛完成"
echo "  =y 包数: $(grep -c '^CONFIG_PACKAGE_.*=y$' .config || true)"
echo "  luci-app 数量: $(grep -c '^CONFIG_PACKAGE_luci-app-.*=y$' .config || true)（只应为 ttyd）"
echo "[prepare] ✓ 可以开始 make download / make"
