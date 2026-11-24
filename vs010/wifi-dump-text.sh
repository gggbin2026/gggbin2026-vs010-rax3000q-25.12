#!/bin/sh
# wifi-dump-text.sh —— 在「信号正常的那份固件」运行的机器上执行
#
# 全程只读，不改任何配置。所有结果直接打印到屏幕/串口，
# 复制从 ===== 0 基本信息 ===== 到 ===== END ===== 之间的文本贴回对话即可。
# 不用打包、不用 scp、不用上传附件。
#
# 可选环境变量（真机留空即可）：
#   ROOT=/tmp/mock     测试用，指向模拟根目录
#   ART_FILE=/path     直接指定 ART 备份文件；留空则自动从 /proc/mtd 找 0:ART
#
# 建议在开机稳定后尽快跑（dmesg 环形缓冲会被后续日志冲掉）。
#
# 【第 25 次校准】已定位到「信号正常」的参考固件整套文件（HFS 目录）：
#   旧基线（命名已废弃）的 cucc_vs010 与 cmcc_rax3000qy 两份 factory.bin，
#   ART 分区分别是 smem_0(0:ART) 与 mtd13(0:ART)，还有 VS010 的 U-Boot 与
#   两份 WDS 配置备份。请务必在【刷了这份 2024-04-16 固件】的机器上跑本脚本，
#   纯文本贴回来即可；文件清单见 vs010/wifi-truth.conf 的 REF_* 段。

R=${ROOT:-}
ART_FILE=${ART_FILE:-}

P() { printf '\n===== %s =====\n' "$*"; }
try() { "$@" 2>/dev/null || true; }
# 有的固件只有 od 没有 hexdump
HX() {
    if command -v hexdump >/dev/null 2>&1; then hexdump -C "$@" 2>/dev/null | head -4
    else od -An -tx1 -v "$@" 2>/dev/null | head -4
    fi
}

P '0 基本信息（判断内核/驱动栈是否同源）'
try date
try uname -a
try cat "$R/etc/openwrt_release"
try cat "$R/etc/os-release"
printf '\n-- 内核 vermagic / 模块目录 --\n'
try sh -c 'grep -m1 -i vermagic /proc/modules'
try ls "$R/lib/modules"

P '1 /proc/cmdline（U-Boot 传参，cnss2.bdf_* 最关键）'
try cat "$R/proc/cmdline"

P '2 /proc/mtd（找 0:ART / wifi_fw / bdf 分区）'
try cat "$R/proc/mtd"

P '3 无线驱动日志（BDF location / board id / calibration）'
try sh -c "dmesg | grep -iE 'cnss|BDF|bdwlan|cal|ath11k|qca.*wifi|wifi[01]|nss|wlan' | tail -100"

P '4 已加载的无线/加速模块'
try sh -c "grep -iE 'cnss|ath11k|qca|nss|wifi|ecm|sfe' /proc/modules"

P '5 设备树无线真值（board_id / bdf-addr / caldb-addr / mem-region）'
if command -v dtc >/dev/null 2>&1 && [ -f "$R/sys/firmware/fdt" ]; then
    try sh -c "dtc -I dtb -O dts $R/sys/firmware/fdt | grep -iE -A20 'wifi@|qcom,board-id|bdf-addr|caldb|qcn|wlan' | head -200"
elif [ -d "$R/proc/device-tree" ]; then
    echo '(无 dtc，改列 /proc/device-tree 属性原始值)'
    find "$R/proc/device-tree" -type f 2>/dev/null \
      | grep -iE 'wifi|qcn|wlan|ath' \
      | grep -iE 'board|bdf|cal|compatible|reg|memory' \
      | while read -r f; do
          printf '%s :\n' "$f"
          HX "$f"
        done
else
    echo '(无 fdt / dtc / /proc/device-tree，跳过；此项请务必从固件文件补)'
fi

P '6 /lib/firmware 无线相关清单（BDF / q6 / m3 / board-2.bin）'
if [ -d "$R/lib/firmware" ]; then
    find "$R/lib/firmware" -type f 2>/dev/null \
      | grep -iE 'bdwlan|board-2|qcn|ipq5018|ipq5000|ath11k|q6|m3|\.mdt|\.b00|wlan' \
      | head -100 \
      | while read -r f; do
          printf '%s  ' "$f"
          try ls -l "$f" | awk '{print $5" B"}'
        done
else
    echo '(无 /lib/firmware 目录)'
fi

P '7 /etc/config/wireless（country / txpower / htmode / channel）'
try cat "$R/etc/config/wireless"

P '8 射频注册与功率表'
for d in "$R"/sys/class/ieee80211/phy*; do
    [ -e "$d" ] || continue
    phy=${d##*/}
    printf '\n-- %s --\n' "$phy"
    try iw "$phy" info | grep -iE 'phy#|freq|channel|txpower|band|ht|vht|he' | head -30
done
try iw dev
try sh -c 'cat /sys/kernel/debug/ath11k/*/fw_stats 2>/dev/null | head -20'

P '9 ART 结构摘要（本机独立校准；只给偏移/块图，不外传原文）'
if [ -n "$ART_FILE" ] && [ -f "$ART_FILE" ]; then
    src="$ART_FILE"
elif [ -f "$R/proc/mtd" ]; then
    # 兼容 0:ART / smem_0:ART / mtd13:0ART / 0:art 等多种命名
    m=$(grep -iE '"[^"]*(art|ART)[^"]*"' "$R/proc/mtd" 2>/dev/null | head -1 | cut -d: -f1)
    art_label=$(grep -iE '"[^"]*(art|ART)[^"]*"' "$R/proc/mtd" 2>/dev/null | head -1 \
                | sed -n 's/.*"\([^"]*\)".*/\1/p')
    src="/dev/$m"
    [ -e "$src" ] || src=''
    [ -n "$art_label" ] && printf 'ART 分区标签: %s (设备 %s)\n' "$art_label" "$src"
else
    src=''
fi
if [ -n "$src" ] && [ -r "$src" ]; then
    printf '来源: %s\n' "$src"
    try dd if="$src" bs=4096 2>/dev/null | wc -c | awk '{print "整片字节: "$1}'
    printf 'MD5(前1MB): '; try dd if="$src" bs=4096 count=256 2>/dev/null | md5sum | cut -d' ' -f1
    printf '\n头 64 字节:\n'; dd if="$src" bs=64 count=1 2>/dev/null | HX
    printf '\n前 256KB 每 4KB 块有效字节数（非00/FF，判断 2.4G/5G 切片起点）:\n'
    try dd if="$src" bs=4096 count=64 2>/dev/null \
      | od -An -v -tu1 \
      | awk '{for(i=1;i<=NF;i++){v=$i; if(v!=0&&v!=255)n++; t++; if(t%4096==0){printf "%02d:%d ", int(t/4096)-1, n; n=0; if(int(t/4096)%8==0)printf "\n"}}} END{printf "\n"}'
else
    echo '(未找到 0:ART，跳过；可设 ART_FILE=/path/to/ART.bin 再跑)'
fi

P 'END —— 复制以上全部文本贴回对话即可（约几 KB，不需要任何附件）'
