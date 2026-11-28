#!/bin/sh
# 生成 .config：精简 seed → 探测幽灵包 → 按机型/模式/基线追加 → make defconfig → 硬校验
# 用法: sh config/gen-config.sh <WORKSPACE> <DEVICE> <MODE> <BASELINE> <NSS>
set -eu
W=${1:-.}; D=${2:-vs010}; MODE=${3:-wds}; BASE=${4:-official-25.12}; NSS=${5:-0}
cd "$W/openwrt"

CFG="$W/config/common.seed"
OUT=.config
: > "$OUT"

# 1) 目标与镜像（按机型，一次只编一台，matrix 已经拆开）
{
  echo 'CONFIG_TARGET_qualcommax=y'
  echo 'CONFIG_TARGET_qualcommax_ipq50xx=y'
  echo 'CONFIG_TARGET_ROOTFS_SQUASHFS=y'
  echo 'CONFIG_ATH11K_MEM_PROFILE_256M=y'
  echo 'CONFIG_TARGET_MULTI_PROFILE=y'
  case "$D" in
    vs010)     echo 'CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_unicom_vs010=y'
               echo '# CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_cmcc_rax3000q is not set' ;;
    rax3000q)  echo 'CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_cmcc_rax3000q=y'
               echo '# CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_unicom_vs010 is not set' ;;
    *) echo "::error::未知机型 $D"; exit 1 ;;
  esac
} >> "$OUT"

# 2) seed：普通行直接写；OPTIONAL 行探测 feed 里是否真有这个包
FEEDLIST=/tmp/nwrt-feedlist.txt
./scripts/feeds list 2>/dev/null | cut -d' ' -f1 | sort -u > "$FEEDLIST" || true
DROPPED=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  case "$line" in
    OPTIONAL:*)
      sym=${line#OPTIONAL:}; pkg=${sym#CONFIG_PACKAGE_}; pkg=${pkg%=*}
      if grep -qx "$pkg" "$FEEDLIST" 2>/dev/null || [ -d "package/$pkg" ] || \
         grep -rqsl "PKG_NAME:=$pkg" feeds package 2>/dev/null; then
        echo "$sym" >> "$OUT"
      else
        echo "[gen-config] 警告：feed 无 $pkg，已从 .config 删除（不写空气包）"
        echo "# $sym is not set" >> "$OUT"
        DROPPED=$((DROPPED+1))
      fi
      ;;
    *) echo "$line" >> "$OUT" ;;
  esac
done < "$CFG"

# 3) IPv6：官方基线关编译符号；NSS 基线保留内核符号，只关网络层
if [ "$NSS" = 0 ]; then
  echo '# CONFIG_IPV6 is not set' >> "$OUT"
else
  echo '# [gen-config] NSS 基线：保留 CONFIG_IPV6 内核符号，运行期 sysctl 关死' >> "$OUT"
fi

# 4) NSS 基线追加加速包（包不存在时由 defconfig 静默丢弃，不阻断）
if [ "$NSS" = 1 ]; then
  for p in kmod-qca-nss-drv kmod-qca-nss-dp nss-ecm kmod-nss-ifb qca-nss-fw-ipq50xx-retail; do
    echo "CONFIG_PACKAGE_$p=y" >> "$OUT"
  done
fi

# 5) MODE 差异（WDS 需要完整 wpad 的 4addr；AP 需要双频 hostapd）
echo "CONFIG_PACKAGE_wpad-mbedtls=y" >> "$OUT"

# 6) defconfig
command -v gawk >/dev/null || { echo "::error::缺 gawk"; exit 1; }
if ! make defconfig >/tmp/nwrt-defconfig.log 2>&1; then
  echo "::error::make defconfig 失败，日志："
  tail -60 /tmp/nwrt-defconfig.log
  exit 1
fi
echo "[gen-config] defconfig OK，丢弃幽灵包 $DROPPED 个"

# 7) 硬校验：luci-app-* 只能有 1 个（ttyd）
N=$(grep -c '^CONFIG_PACKAGE_luci-app-' "$OUT" 2>/dev/null || true)
[ "${N:-0}" -le 1 ] || { echo "::error::luci-app-* 出现 $N 个，插件精简被破坏"; exit 1; }
grep -q '^CONFIG_PACKAGE_dropbear=y' "$OUT" || { echo "::error::SSH 丢失"; exit 1; }
grep -q '^CONFIG_PACKAGE_luci-theme-bootstrap=y' "$OUT" || { echo "::error::bootstrap 主题丢失"; exit 1; }
grep -q '^# CONFIG_PACKAGE_luci-theme-argon is not set' "$OUT" || echo "[gen-config] 注意：argon 未被显式关闭（defconfig 已处理）"
echo "[gen-config] RESULT: OK device=$D mode=$MODE baseline=$BASE nss=$NSS"
