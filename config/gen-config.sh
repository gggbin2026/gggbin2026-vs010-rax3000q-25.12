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

# 4) NSS 基线追加加速包
#    包名按 qosmio/openwrt-ipq @ 25.12-nss + qosmio/nss-packages @ NSS-12.5-K6.x 实证：
#      kmod-qca-nss-drv        ← feed  qca-nss-drv/Makefile        (KernelPackage/qca-nss-drv)
#      kmod-qca-nss-dp         ← 主树  package/kernel/qca-nss-dp   (KernelPackage/qca-nss-dp)
#      kmod-qca-nss-ecm        ← feed  qca-nss-ecm/Makefile        (KernelPackage/qca-nss-ecm)
#      kmod-nss-ifb            ← feed  nss-ifb/Makefile            (KernelPackage/nss-ifb)
#      nss-firmware-ipq50xx    ← feed  firmware/nss-firmware       (Package/nss-firmware-ipq50xx)
#    🔴 r22 修复：旧写法 `nss-ecm` / `qca-nss-fw-ipq50xx-retail` 在上游不存在，
#       defconfig 会静默丢弃 → ECM 不进镜像、加速落空。下面 6.6) 改为硬校验。
NSS_PKGS="kmod-qca-nss-drv kmod-qca-nss-dp kmod-qca-nss-ecm kmod-nss-ifb nss-firmware-ipq50xx"
if [ "$NSS" = 1 ]; then
  for p in $NSS_PKGS; do
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

# 6.5) 二层防护硬校验：defconfig 静默丢包会让 DHCP Snooping 变成空转，宁可停编
#     🔴 r23：25.12 起主树只有 nftables-nojson(默认)/nftables-json 两个变体，
#     Package/nftables/Default 是模板，PROVIDES:=nftables 是虚拟提供名、
#     不生成 CONFIG 符号 → 裸 CONFIG_PACKAGE_nftables=y 是幽灵符号，defconfig 会删除。
#     接受三个候选（兼容旧树），全缺才停编，并打印 .config 里实际 nft 行。
NFT_ANY=''
for p in nftables-nojson nftables-json nftables; do
  if grep -q "^CONFIG_PACKAGE_$p=y" "$OUT"; then NFT_ANY="$p"; break; fi
done
if [ -z "$NFT_ANY" ]; then
  echo "::error::nft 用户态未进 .config（nftables-nojson / nftables-json / nftables 均无 =y）"
  echo "::error::25.12 起主树只有 nftables-nojson(默认)/nftables-json 变体，裸 CONFIG_PACKAGE_nftables=y 是幽灵符号"
  echo "::error::.config 里现有 nft 相关行："
  grep -E '^CONFIG_PACKAGE_(nft|kmod-nft)' "$OUT" | head -20 || true
  echo "::error::请检查 feeds.conf.default 与所选基线；不要编一个假防护的固件"
  exit 1
fi
for p in kmod-nft-bridge; do
  grep -q "^CONFIG_PACKAGE_$p=y" "$OUT" || {
    echo "::error::$p 未进 .config（feed 缺包或被依赖覆盖），无线侧 DHCP 防护会失效"
    echo "::error::请检查 feeds.conf.default 与所选基线；不要编一个假防护的固件"
    exit 1
  }
done
echo "[gen-config] 二层防护 OK：nft=$NFT_ANY + kmod-nft-bridge 均已进 .config"

# 6.6) NSS 加速包硬校验：选 qosmio 基线就是为了加速，缺包宁可停编，不编假加速固件
NSS_OK=0; NSS_TOT=0; NSS_MISS=''
if [ "$NSS" = 1 ]; then
  for p in $NSS_PKGS; do
    NSS_TOT=$((NSS_TOT+1))
    if grep -q "^CONFIG_PACKAGE_$p=y" "$OUT"; then
      NSS_OK=$((NSS_OK+1))
    else
      NSS_MISS="$NSS_MISS $p"
    fi
  done
  if [ "$NSS_OK" -ne "$NSS_TOT" ]; then
    echo "::error::NSS 加速包未全部进 .config（缺:$NSS_MISS ）"
    echo "::error::检查 feeds.conf.default 是否含 nss_packages(NSS-12.5-K6.x) 且 feeds install -a 已执行"
    echo "::error::不要编一个「选了 NSS 基线却没有加速」的固件"
    exit 1
  fi
  echo "[gen-config] NSS 加速 OK：$NSS_OK/$NSS_TOT 个包均已进 .config"
fi

# 7) 硬校验：luci-app-* 只能有 1 个（ttyd）
N=$(grep -c '^CONFIG_PACKAGE_luci-app-' "$OUT" 2>/dev/null || true)
[ "${N:-0}" -le 1 ] || { echo "::error::luci-app-* 出现 $N 个，插件精简被破坏"; exit 1; }
grep -q '^CONFIG_PACKAGE_dropbear=y' "$OUT" || { echo "::error::SSH 丢失"; exit 1; }
grep -q '^CONFIG_PACKAGE_luci-theme-bootstrap=y' "$OUT" || { echo "::error::bootstrap 主题丢失"; exit 1; }
grep -q '^# CONFIG_PACKAGE_luci-theme-argon is not set' "$OUT" || echo "[gen-config] 注意：argon 未被显式关闭（defconfig 已处理）"
echo "[gen-config] RESULT: OK device=$D mode=$MODE baseline=$BASE nss=$NSS nss_pkgs=$NSS_OK/$NSS_TOT"
