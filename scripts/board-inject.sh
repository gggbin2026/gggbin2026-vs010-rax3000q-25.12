#!/bin/sh
# 编译期注入 VS010 / RAX3000Q 板级。用法:
#   sh scripts/board-inject.sh <WORKSPACE> <BOARD_POLICY> <DEVICE>
# BOARD_POLICY: inject（默认）| warn（6.18 尝鲜，只警告不阻断）
set -eu
W=${1:-.}; POLICY=${2:-inject}; D=${3:-vs010}
TREE="$W/openwrt"
[ -d "$TREE/target/linux/qualcommax" ] || { echo "::error::不是 qualcommax ipq50xx 源码树"; exit 1; }

if [ "$POLICY" = warn ]; then
  echo "::warning::该基线不含 VS010 / RAX3000Q 板级，注入后需自行核对 DTS 绑定与 02_network；首次刷必接 TTL"
fi

# 1) 探测两种 DTS 目录布局（第 43 次实证：25.12 已换到 files/.../dts/qcom/）
DTS_DIR=""
for c in \
  "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom" \
  "$TREE/target/linux/qualcommax/dts" \
  "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts"; do
  [ -d "$c" ] && { DTS_DIR="$c"; break; }
done
[ -n "$DTS_DIR" ] || { echo "::error::找不到 ipq50xx DTS 目录（两种布局都不匹配）"; exit 1; }
echo "[board] DTS 目录: $DTS_DIR"

# 2) 注入两台 DTS（board/ 里的 6.12 版，来自 OpenWrt main 官方 DTS 还原版 + 第 44 次结论）
for dts in ipq5018-vs010.6.12.dts ipq5018-rax3000q.6.12.dts; do
  src="$W/board/$dts"
  [ -f "$src" ] || { echo "::error::缺 board/$dts"; exit 1; }
  # 花括号配对（第 29.6 条：编译跑 1 小时才在打包阶段 exit 2 的坑）
  o=$(tr -cd '{' < "$src" | wc -c); c=$(tr -cd '}' < "$src" | wc -c)
  [ "$o" = "$c" ] || { echo "::error::$dts 花括号不配对 { $o } $c"; exit 1; }
  cp "$src" "$DTS_DIR/$dts"
  echo "[board] 注入 $dts（{ $o / } $c 配对 OK）"
done

# 3) ipq50xx.mk 追加两个 Device 定义（DEVICE_PACKAGES 必须补 ath11k 固件，否则射频不 probe）
MK=""
for c in \
  "$TREE/target/linux/qualcommax/image/ipq50xx.mk" \
  "$TREE/target/linux/qualcommax/ipq50xx/image/Makefile"; do
  [ -f "$c" ] && { MK="$c"; break; }
done
[ -n "$MK" ] || { echo "::error::找不到 ipq50xx.mk"; exit 1; }
if ! grep -q 'Device/unicom_vs010' "$MK"; then
  cat "$W/board/ipq50xx.device.inc" >> "$MK"
  echo "[board] 追加 Device/unicom_vs010 + Device/cmcc_rax3000q"
else
  echo "[board] Device 定义已存在，跳过追加"
fi

# 4) 02_network：兼容 pz-l8| 续行写法，两个分支都注入全 LAN（WAN 物理口也桥进 br-lan）
NET=""
for c in \
  "$TREE/target/linux/qualcommax/ipq50xx/base-files/etc/board.d/02_network" \
  "$TREE/target/linux/qualcommax/base-files/etc/board.d/02_network"; do
  [ -f "$c" ] && { NET="$c"; break; }
done
if [ -n "$NET" ]; then
  if ! grep -q 'cucc,vs010' "$NET"; then
    # 在第一个 case 分支前插入（用 python3 做精确锚点，避免 sed 续行粘连）
    python3 "$W/scripts/inject-02network.py" "$NET" "$W/board/02_network.inc"
    echo "[board] 注入 02_network 两个机型分支"
  else
    echo "[board] 02_network 已含 VS010，跳过"
  fi
else
  echo "::warning::没找到 02_network，运行期 bridge-netfix 会按 sysfs 动态补齐桥成员"
fi

# 5) BDF / ART 边界：默认不引用 ART 切片
if grep -rq 'ART_CALIBRATION=1' "$W/baseline.env" 2>/dev/null; then
  echo "::warning::ART_CALIBRATION=1 是实验项；实机日志证明好固件加载模板 BDF 且 Caldata not present，刷完必须用 TTL 验证射频"
fi
echo "[board] RESULT: OK device=$D policy=$POLICY"
