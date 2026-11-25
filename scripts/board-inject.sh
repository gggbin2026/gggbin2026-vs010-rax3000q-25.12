#!/bin/bash
# 把 VS010（以及缺树时的 RAX3000Q）注入 6.12 源码树
# 用法: scripts/board-inject.sh <device> <source-tree>
set -euo pipefail
D="${1:?device}"; TREE="${2:-openwrt}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TREE"

echo "==================== [board-inject] $D ===================="

# ── 探测树的布局（★ 第 43 次：25.12 官方/qosmio 把 dts 移到了 files/.../qcom）──
#   旧版只认 target/linux/qualcommax/dts/，在 qosmio 25.12-nss 上会直接
#   "::error::不是 ipq50xx 源码树" 停编。实测该树 DTS 在：
#     target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
if [ -d target/linux/qualcommax/files/arch/arm64/boot/dts/qcom ]; then
  DTS_DIR=target/linux/qualcommax/files/arch/arm64/boot/dts/qcom
  IMGMK=target/linux/qualcommax/image/ipq50xx.mk
  NET=target/linux/qualcommax/ipq50xx/base-files/etc/board.d/02_network
  LAYOUT=qualcommax-files
elif [ -d target/linux/qualcommax/dts ]; then
  DTS_DIR=target/linux/qualcommax/dts
  IMGMK=target/linux/qualcommax/image/ipq50xx.mk
  NET=target/linux/qualcommax/ipq50xx/base-files/etc/board.d/02_network
  LAYOUT=qualcommax
elif [ -d target/linux/ipq50xx/dts ]; then
  DTS_DIR=target/linux/ipq50xx/dts
  IMGMK=target/linux/ipq50xx/image/Makefile
  NET=target/linux/ipq50xx/base-files/etc/board.d/02_network
  LAYOUT=ipq50xx
else
  echo "::error::不是 ipq50xx 源码树"; exit 1
fi
echo "[board-inject] 布局 = $LAYOUT"

# ── ART 真值（只读）落进 rootfs，供运行期 art-check 比对 ──
# 不把 ART 切片/产线校准编进固件：wifi-truth.conf 实证好固件不加载 caldata，
# 改这条路径风险大于收益。这里只放【文本真值】用于自检与判定机型。
if [ -s "$ROOT/art/art-truth.conf" ]; then
  mkdir -p files/etc
  cp "$ROOT/art/art-truth.conf" files/etc/art-truth.conf
  echo "  ✓ ART 真值 → files/etc/art-truth.conf（art-check 用，不含二进制校准）"
fi

# ART_CALIBRATION=1 才允许装配本机 board-2.bin；默认 0 = 完全不引用 ART。
ART_CALIBRATION="${ART_CALIBRATION:-0}"

# 通用：按机型装配（有产物才装，没有就保留官方通用容器）
install_board2() {
  _dev="$1"
  FDIR="files/lib/firmware/ath11k/IPQ5018/hw1.0"
  mkdir -p "$FDIR"
  # ★ 严格按机型取，绝不回落到另一台的产物：
  #   VS010 与 RAX3000Q 的 ART 切片互差 738 / 2552 字节，跨机用 = 拿别人的功率表。
  #   只有 VS010 额外兼容老路径 vs010/bdf/board-2.bin。
  _src="$ROOT/art/out/$_dev/board-2.bin"
  if [ "$_dev" = vs010 ] && [ ! -s "$_src" ] && [ -s "$ROOT/vs010/bdf/board-2.bin" ]; then
    _src="$ROOT/vs010/bdf/board-2.bin"
  fi
  if [ "$ART_CALIBRATION" = 1 ] && [ -s "$_src" ]; then
    # 必须是合法容器，不是单个 BDF 改名（那会让两个射频都读错校准）
    if head -c 16 "$_src" | grep -qa 'QCA-ATH11K-BOARD'; then
      # ★ 实机日志（art/oem-bootlog.txt）证明：好固件下载 bdwlan.b10 / bdwlan.b60，
      #   MD5 == 模板 BDF；Caldata not present → ART 切片根本没被加载。
      #   容器里若含 ART 切片，等于把一份没被验证过的功率表刷进固件。
      if [ -s "$ROOT/art/art-truth.conf" ] && command -v python3 >/dev/null 2>&1; then
        _info=$(python3 "$ROOT/art/make-board2.py" info "$_src" 2>/dev/null || true)
        for _m in $(grep -E '^ART_.*_BDF[25]G_MD5=' "$ROOT/art/art-truth.conf" | cut -d= -f2); do
          if printf '%s' "$_info" | grep -q "$_m"; then
            echo "::warning::[$_dev] 容器含 ART 切片 BDF（$_m）"
            echo "::warning::好固件实证用的是模板 BDF（bdwlan.b10 / bdwlan.b60），不是 ART 切片"
            echo "::warning::请改用 art/make-board2.py from-oem 重新生成，否则功率表可能不对"
          fi
        done
      fi
      cp "$_src" "$FDIR/board-2.bin"
      echo "  ✓ [$_dev] 已装配本机校准 board-2.bin（ART_CALIBRATION=1）"
      echo "     来源 $_src · md5=$(md5sum "$_src" | awk '{print $1}')"
    else
      echo "::error::$_src 不是 board-2.bin 容器（缺 QCA-ATH11K-BOARD 签名），停编"
      echo "::error::单个 BDF 直接改名会让射频不 probe；用 art/make-board2.py 合成"
      exit 1
    fi
  else
    if [ -s "$_src" ]; then
      echo "  ℹ [$_dev] 检测到 $_src 但 ART_CALIBRATION=0 → 不装配，保留官方通用容器"
    else
      echo "  ℹ [$_dev] 未提供本机 board-2.bin → 保留官方通用容器（最稳）"
    fi
  fi
}

# ── 共用：DTS 依赖的 dtsi 是否齐 ──
# ★ ipq5018.dtsi 来自 Linux 内核源码（编译期由 kernel dts 目录提供），
#   qosmio 25.12-nss 树内本来就没有它；上游 ipq5018-pz-l8.dts 同样 include，
#   所以不再把它当成「树内缺失」，避免每次编译刷一条误导性警告。
for inc in ipq5018-ess.dtsi ipq5018-qcn6122.dtsi; do
  case "$LAYOUT" in
    qualcommax|qualcommax-files)
      find target/linux/qualcommax -name "$inc" -print -quit | grep -q . \
        || echo "::warning::树里没有 $inc，DTS 可能需要按本树 dtsi 改写"
      ;;
  esac
done

# ── VS010 注入 ──
if [ "$D" = vs010 ]; then
  SRC="$ROOT/board/ipq5018-vs010.6.12.dts"
  [ -s "$SRC" ] || { echo "::error::缺 $SRC"; exit 1; }
  # 实机真值：VS010 只有 WPS 键，没有 reset 键；带 KEY_RESTART 会开机进 failsafe
  if sed -E '/^[[:space:]]*(\/\/|\/\*|\*|\*\/)/d' "$SRC" \
       | grep -qE 'KEY_RESTART|label[[:space:]]*=[[:space:]]*"reset"'; then
    echo "::error::VS010 DTS 仍含复位键定义，停编"; exit 1
  fi
  cp "$SRC" "$DTS_DIR/ipq5018-vs010.dts"
  echo "  ✓ DTS → $DTS_DIR/ipq5018-vs010.dts（6.12 官方 PZ-L8 风格）"

  # 设备定义：与官方 25.12 Device/cmcc_pz-l8 完全同骨架
  if ! grep -q '^define Device/unicom_vs010' "$IMGMK"; then
    cat >> "$IMGMK" <<'MKEOF'

define Device/unicom_vs010
	$(call Device/FitImageLzma)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Unicom
	DEVICE_MODEL := VS010
	DEVICE_DTS_CONFIG := config@mp02.1
	SOC := ipq5018
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 59392k
	NAND_SIZE := 128m
	# 官方 25.12 的 cmcc_pz-l8 没写 DEVICE_PACKAGES，射频不 probe，这里必须补
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		kmod-ath11k-ahb ipq-wifi-cucc_vs010
	IMAGES += factory.img
	IMAGE/factory.img := append-ubi | qsdk-ipq-factory-nand
endef
TARGET_DEVICES += unicom_vs010
MKEOF
    echo "  ✓ 追加 Device/unicom_vs010（含 factory.img，适配原厂 Web API 的 .img）"
  fi

  # board.d 网络映射（锚点不存在就只警告，不硬改）
  if [ -f "$NET" ] && ! grep -q 'unicom,vs010' "$NET"; then
    if grep -q 'cmcc,pz-l8' "$NET"; then
      sed -i '/^[[:space:]]*cmcc,pz-l8[|)]/i\\tunicom,vs010|\\' "$NET"
      echo "  ✓ 02_network 追加 unicom,vs010"
    else
      echo "::warning::02_network 锚点 cmcc,pz-l8 不存在，请手工核对端口映射"
    fi
  fi

  # ── 原厂 BDF 本地落盘 + 本地 ipq-wifi 包（绝不联网下载，规避老仓库 403）──
  BDFD="$ROOT/vs010/bdf"
  FWDIR="files/lib/firmware/ath11k/IPQ5018/hw1.0"
  mkdir -p "$FWDIR"
  for f in board-cucc_vs010.ipq5018 board-cucc_vs010.qcn6122; do
    [ -s "$BDFD/$f" ] || { echo "::error::缺原厂 BDF $f"; exit 1; }
    cp "$BDFD/$f" "$FWDIR/"
  done
  echo "  ✓ 实证在用的模板 BDF 落盘 $FWDIR/（bdwlan.b10 / bdwlan.b60，见 oem-bootlog.txt）"

  # 官方 25.12 的 ipq-wifi 机制：board-<name>.IPQ5018 会被装成 board-2.bin。
  # 但单个 BDF 不是 board-2.bin 容器，直接改名会让两个射频都读错校准。
  # ★ 2026-11-24 实机日志纠正：好固件下载 bdwlan.b10 / bdwlan.b60（== 模板 BDF），
  #   且 Caldata not present → ART 切片没被加载。本机校准请用
  #     python3 art/make-board2.py from-oem --base <官方容器> --out art/out/vs010/board-2.bin
  #   不要用 ART 切片造容器。这里生成【本地包】：没有产物就装空包、保留官方
  #   ath11k-firmware 自带 board-2.bin（射频仍能起来）——最稳、最少系统问题。
  PKG="package/firmware/ipq-wifi-cucc_vs010"
  mkdir -p "$PKG"
  cat > "$PKG/Makefile" <<'MKEOF'
include $(TOPDIR)/rules.mk
PKG_NAME:=ipq-wifi-cucc_vs010
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_FLAGS:=nonshared
include $(INCLUDE_DIR)/package.mk

define Package/ipq-wifi-cucc_vs010
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Unicom VS010 local board-2.bin (optional, no network)
  DEPENDS:=@(TARGET_qualcommax||TARGET_ipq50xx)
endef

define Package/ipq-wifi-cucc_vs010/description
  Installs a locally generated board-2.bin for VS010 when present.
  No network download. Without board-2.bin the package installs nothing and
  the upstream ath11k-firmware board-2.bin is kept, so both radios still probe.
endef

define Build/Compile
endef

define Package/ipq-wifi-cucc_vs010/install
	$(INSTALL_DIR) $(1)/lib/firmware/ath11k/IPQ5018/hw1.0
	[ -f $(TOPDIR)/files/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin ] && \
		$(INSTALL_DATA) $(TOPDIR)/files/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin \
			$(1)/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin || true
endef

$(eval $(call BuildPackage,ipq-wifi-cucc_vs010))
MKEOF
  echo "  ✓ 本地包 $PKG（不联网、不 403、包符号真实存在）"

  install_board2 vs010
  echo "  ℹ 不注册联网的 ipq-wifi 包；老仓库第 30 次校准即因 generate-ipq-wifi-package 403 失败"

  # wifi-truth.conf 真值（VERIFIED=1 时才覆盖 DTS 节点）
  TRUTH="$ROOT/vs010/wifi-truth.conf"
  if grep -qE '^[[:space:]]*VERIFIED[[:space:]]*=[[:space:]]*1' "$TRUTH" 2>/dev/null; then
    echo "  ✓ wifi-truth.conf VERIFIED=1：请按 board/README.md 同步 DTS 节点后再编译"
  else
    echo "  ℹ wifi-truth.conf VERIFIED=0，保持官方 PZ-L8 推断值（有实机 fdt 再填 1）"
  fi
fi

# ── RAX3000Q ──
# ★ 第 43 次实证更正：qosmio/openwrt-ipq @ 25.12-nss 整树 12317 个路径里
#   "rax3000q" 0 命中；target/linux/qualcommax/image/ipq50xx.mk 只有 15 个官方
#   ipq50xx 设备（含 cmcc_pz-l8），【没有】cmcc_rax3000q。
#   baseline.env 旧注释「树内原生、实机验证过」是错的，已改为 inject:pz-l8-skeleton。
#   所以这里不再硬报错停编，而是按同芯片 PZ-L8 骨架 + 好固件 FIT 真实 DTB 的
#   model/compatible 注入板级。⚠ 该板级未在 6.12 主线实机验证，见 DTS 头注释。
if [ "$D" = rax3000q ]; then
  SRC="$ROOT/board/ipq5018-rax3000q.6.12.dts"
  [ -s "$SRC" ] || { echo "::error::缺 $SRC（第 43 次新增的 RAX3000Q 板级）"; exit 1; }
  cp "$SRC" "$DTS_DIR/ipq5018-rax3000q.dts"
  echo "  ✓ DTS → $DTS_DIR/ipq5018-rax3000q.dts"
  echo "::warning::[rax3000q] 板级 = PZ-L8 的 6.12 绑定骨架 + 官方 main DTS 硬件真值"
  echo "::warning::（第 44 次：QCA8337 端口/ECC/compatible 已按逐字节官方原文校正）"
  echo "::warning::未在 6.12 主线实机验证；首次刷务必接 3.3V USB-TTL 看串口。"

  # 设备定义：与 cmcc_pz-l8 同骨架，补 DEVICE_PACKAGES（否则射频不 probe）
  if ! grep -q '^define Device/cmcc_rax3000q' "$IMGMK"; then
    cat >> "$IMGMK" <<'MKEOF'

define Device/cmcc_rax3000q
	$(call Device/FitImageLzma)
	$(call Device/UbiFit)
	DEVICE_VENDOR := CMCC
	DEVICE_MODEL := RAX3000QY
	DEVICE_DTS_CONFIG := config@mp02.1
	SOC := ipq5018
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 59392k
	NAND_SIZE := 128m
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 		kmod-ath11k-ahb
	IMAGES += factory.img
	IMAGE/factory.img := append-ubi | qsdk-ipq-factory-nand
endef
TARGET_DEVICES += cmcc_rax3000q
MKEOF
    echo "  ✓ 追加 Device/cmcc_rax3000q（含 factory.img，适配原厂 Web API）"
  fi
  # board.d 网络映射：★ 第 44 次——两个 compatible 都要有分支
  #   官方 main（2026-09-27 合入）用 cmcc,rax3000q；
  #   用户手上的 QSDK 12.2 好固件 FDT 用 cmcc,rax3000qy（QY 变体）。
  #   DTS 的 compatible 两个都写了，这里也必须两个都注入，否则 board_name
  #   匹配不到 → ucidef 不生效 → WAN/LAN 不进 br-lan。
  #   注意用单引号 sed（双引号会把 \\t 吃掉，插入成 tcmcc... 语法错误）。
  if [ -f "$NET" ]; then
    if grep -q 'cmcc,pz-l8' "$NET"; then
      if ! grep -qF 'cmcc,rax3000q|' "$NET"; then
        sed -i '/^[[:space:]]*cmcc,pz-l8[|)]/i\\tcmcc,rax3000q|\\' "$NET"
        echo "  ✓ 02_network 追加 cmcc,rax3000q（官方主线名）"
      fi
      if ! grep -qF 'cmcc,rax3000qy|' "$NET"; then
        sed -i '/^[[:space:]]*cmcc,pz-l8[|)]/i\\tcmcc,rax3000qy|\\' "$NET"
        echo "  ✓ 02_network 追加 cmcc,rax3000qy（QY 变体）"
      fi
    else
      echo "::warning::02_network 锚点 cmcc,pz-l8 不存在，请手工核对端口映射"
    fi
  fi

  # 逐项探测 DEVICE_PACKAGES（PZ-L8 参考仓教训：缺这两项射频根本不 probe）
  DEVBLK=$(awk '/^define Device\/cmcc_rax3000q/{f=1} f{print} f&&/^endef/{exit}' "$IMGMK")
  for need in ath11k-firmware-ipq5018-qcn6122 kmod-ath11k-ahb; do
    if ! printf '%s\n' "$DEVBLK" | grep -q "$need"; then
      sed -i "/^define Device\/cmcc_rax3000q/,/^endef/ s#\(^[ \t]*DEVICE_PACKAGES[ \t]*:=[ \t]*\)#\1$need #" "$IMGMK"
      DEVBLK=$(awk '/^define Device\/cmcc_rax3000q/{f=1} f{print} f&&/^endef/{exit}' "$IMGMK")
      echo "  ✓ DEVICE_PACKAGES 补 $need"
    fi
  done

  # RAX3000Q 的 ART 与 VS010 结构同构但校准逐台不同（2G 差 738B / 5G 差 2552B），
  # 所以有独立产物路径 art/out/rax3000q/，默认同样不装配。
  install_board2 rax3000q

  # MAC 提示：RAX3000Q 的 ART 头是全 FF，不能像 VS010 那样从 macaddr@0 取。
  echo "::warning::[rax3000q] ART 头全 FF：DTS 故意不引用 nvmem macaddr，"
  echo "::warning::请按机身标签用 uci 固化 wireless/default_radio*.macaddr 与 lan MAC"
  echo "  ℹ 若双频/网口异常，先用 device=vs010 单编验证编译链是否正常"
fi

# ── 6. 裁剪 TARGET_DEVICES（第 46 次 · 修 Compile firmware exit 1）──────
# 【日志实证】2026-11-24 15:14 run #3 两份 job 都在 target/linux/install 段挂掉：
#   Error: .../arch/arm64/boot/dts/qcom/ipq5018-nss.dtsi:118.1-7
#          Label or path wifi0 not found
#   FATAL ERROR: Syntax error parsing input tree
#   make[5]: *** [Makefile:42: image-ipq5018-wrc-x3000gs2.dtb] Error 1
#   make[5]: *** [Makefile:42: image-ipq5018-gl-b3000.dtb] Error 1
#   → ERROR: target/linux failed to build → world Error 2 → 步骤 exit 1
#
# 【根因】qosmio 25.12-nss 自带的 ipq5018-nss.dtsi 引用 &wifi0 / &wifi1 / &wifi2，
#   但整棵树只有 wifi:（内核 ipq5018.dtsi，2G 内置）、wifi1:/wifi2:
#   （ipq5018-qcn6122.dtsi），【从来没有 wifi0: label】。
#   树自带 elecom_wrc-x3000gs2 / glinet_gl-b3000 的 DTS include 了 nss.dtsi，
#   编 DTB 必炸（gl-b3000 还把 nss.dtsi 放在 qcn6122.dtsi 之前 include，
#   于是 wifi1/wifi2 也一并 not found）。这是上游分支当前快照的自身问题。
#
# 【为什么会拖垮我们】OpenWrt 的 `make -C image compile install` 会为 ipq50xx.mk
#   里【所有 TARGET_DEVICES +=】生成并编译 DTB，与 .config 里选了哪台无关。
#   哪怕只选 vs010，也会去编那两个坏设备 → 整个 target/linux/install 失败。
#
# 【为什么裁掉就安全】本仓 VS010 / RAX3000Q 两份 DTS 与能编过的 cmcc_pz-l8
#   同款 include（ipq5018.dtsi + ess + qcn6122），【都不 include nss.dtsi】，
#   引用 &wifi / &wifi1 两个真实存在的 label。NSS 加速靠驱动/固件包与 qca-nss
#   内核模块，不靠这段 dtsi，裁掉不影响无线/有线卸载。
#   顺带少编 11 个无关 DTB，更省 CI 时间与资源。
if [ -f "$IMGMK" ]; then
  cp -n "$IMGMK" "$IMGMK.orig46" 2>/dev/null || true
  awk '
    /^[[:space:]]*TARGET_DEVICES[[:space:]]*\+=/ {
      n=$0
      sub(/^[[:space:]]*TARGET_DEVICES[[:space:]]*\+=[[:space:]]*/,"",n)
      sub(/[[:space:]]*#.*$/,"",n)
      gsub(/[[:space:]]/,"",n)
      if (n !~ /^(unicom_vs010|cmcc_rax3000q)$/) {
        print "# [第46次裁剪] " $0
        next
      }
    }
    { print }
  ' "$IMGMK" > "$IMGMK.tmp46" && mv "$IMGMK.tmp46" "$IMGMK"

  LEFT=$(grep -c '^[[:space:]]*TARGET_DEVICES[[:space:]]*+=' "$IMGMK" || true)
  if [ "$LEFT" -lt 1 ]; then
    echo "::error::裁剪后 TARGET_DEVICES 为空（板级注入可能失败），停编"
    exit 1
  fi
  echo "  ✓ TARGET_DEVICES 裁剪完成，保留 $(grep '^[[:space:]]*TARGET_DEVICES' "$IMGMK" | tr '\n' ' ')（其余已注释，见 .orig46）"

  # 只读提示：树内 nss.dtsi 的悬空 label 依然存在，但已无设备 include 它
  NSSD="$DTS_DIR/ipq5018-nss.dtsi"
  if [ -f "$NSSD" ] && grep -q '&wifi0' "$NSSD"; then
    echo "::warning::树内 ipq5018-nss.dtsi 仍引用悬空 &wifi0（上游快照问题）；已通过裁剪 TARGET_DEVICES 绕开，不改动树内文件"
  fi
else
  echo "::warning::未找到 $IMGMK，跳过 TARGET_DEVICES 裁剪（若报 wifi0 not found 请检查板级布局）"
fi

echo "[board-inject] ✓ 完成"
