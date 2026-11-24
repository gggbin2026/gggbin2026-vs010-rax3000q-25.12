#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# VS010 无线真值一键采集（只读，绝不改任何配置）
#
# 用在哪：刷回「信号挺好、无线能正常起来」的那份别人固件，开机稳定后跑一次。
# 采什么：设备树真值 / cnss2 日志 / 板级 BDF / ART 校准 / 功率表 / 驱动形态。
# 为什么：我们这版无线起不来，根因是 DTS 的 board_id / bdf-addr 是照抄
#         RAX3000Q 猜的。从能正常工作的固件里取真值，比继续猜靠谱得多。
#
# 产两个包（都在 /tmp）：
#   /tmp/vs010-wifi-mini.tar.gz  < 2 MB，串口 base64 或贴文本都行（推荐）
#   /tmp/vs010-wifi-full.tar.gz  含 ART 与整份 /lib/firmware，走浏览器/SSH
# 脚本还会把 full 包放到 /www/ 供浏览器直接下载（局域网内，取完记得删）。
#
# 注意：
#   · dmesg 环形缓冲会被冲掉 → 开机后尽快跑，别等半天。
#   · 0:ART 是每台机器独立校准数据，只用于你这台，别跨机刷、别外传。
#   · 全程只读；唯一的状态变化是可选 mount debugfs（不落盘）。
# ═══════════════════════════════════════════════════════════════════════
OUT=/tmp/vs010-wifi-dump
MINI=/tmp/vs010-wifi-mini.tar.gz
FULL=/tmp/vs010-wifi-full.tar.gz

say() { echo "[collect] $*"; }
# 采集命令输出（带原命令回显），单条失败不影响后续
snap() {
    n=$1; shift
    { printf '# %s\n' "$*"; "$@" 2>&1; } > "$OUT/$n" 2>&1 || true
}
# 采集 shell 片段（支持管道 / 循环）
snapc() {
    n=$1; shift
    { printf '# %s\n' "$*"; sh -c "$*" 2>&1; } > "$OUT/$n" 2>&1 || true
}

rm -rf "$OUT"
mkdir -p "$OUT/fdt" "$OUT/firmware" "$OUT/mtd" "$OUT/sys" \
         "$OUT/conf" "$OUT/mod"
say "输出目录 $OUT"

# ── A. 系统身份：判断驱动是 QSDK cnss2 还是主线 ath11k、内核是否同源 ──
say "A 系统身份 / 驱动形态"
snap  sys/uname.txt            uname -a
snapc sys/release.txt          'cat /proc/version /etc/openwrt_release /etc/os-release /etc/banner 2>/dev/null'
snapc sys/opkg.txt             'opkg list-installed 2>/dev/null || cat /rom/usr/lib/opkg/status 2>/dev/null'
snapc sys/cmdline.txt          'cat /proc/cmdline'
snapc sys/mtd.txt              'cat /proc/mtd'
snapc sys/iomem.txt            'cat /proc/iomem'
snapc mod/lsmod.txt            'cat /proc/modules'
snapc mod/modules-d.txt        'for f in /etc/modules.d/*; do echo "--- $f"; cat "$f"; done'
snapc mod/ko-list.txt          'find /lib/modules -name "*.ko" 2>/dev/null | sort'
snapc sys/fw-env.txt           'fw_printenv 2>/dev/null'   # U-Boot env 里常有 cnss2.bdf_* 地址

# ── B. 设备树真值【最值钱】：board_id / bdf-addr / caldb-addr ──────────
say "B 设备树（fdt.dtb 是决定性证据）"
if [ -r /sys/firmware/fdt ]; then
    cp /sys/firmware/fdt "$OUT/fdt/fdt.dtb" 2>/dev/null \
      && say "  ✓ fdt.dtb $(wc -c < "$OUT/fdt/fdt.dtb") B" \
      || say "  ! fdt.dtb 复制失败"
else
    say "  ! /sys/firmware/fdt 不存在，改采 /proc/device-tree"
fi
if [ -d /proc/device-tree ]; then
    tar cf "$OUT/fdt/proc-device-tree.tar" /proc/device-tree 2>/dev/null || true
    if command -v dtc >/dev/null 2>&1; then
        dtc -I fs -O dts /proc/device-tree > "$OUT/fdt/device-tree.dts" \
          2> "$OUT/fdt/dtc.err" || true
    fi
    # 人眼可读版：只列 wifi/cnss/q6 节点的属性（二进制属性用 od 打 hex）
    snapc fdt/wifi-props.txt '
      for f in $(find /proc/device-tree -type f 2>/dev/null |
                 grep -iE "wifi|cnss|q6|wcss|bdf|caldb|board_id"); do
        printf "=== %s\n" "$f"
        od -An -tx1 -v "$f" 2>/dev/null | head -8
      done'
fi

# ── C. 内核日志：cnss2 会直接打出 BDF location / bdwlan.bXX / 校准结果 ──
say "C 内核日志（越早采越完整）"
snapc sys/dmesg.txt            'dmesg'
snapc sys/dmesg-wifi.txt       'dmesg | grep -iE "cnss|BDF|bdwlan|cal|ath11k|wcss|q6|m3|firmware|wlan|phy|board|rproc"'
snapc sys/logread.txt          'logread 2>/dev/null'
snapc sys/debugfs.txt          'mount -t debugfs none /sys/kernel/debug 2>/dev/null; ls -lR /sys/kernel/debug/ath11k /sys/kernel/debug/cnss2 /sys/kernel/debug/cnss 2>/dev/null | head -200'

# ── D. 无线运行态：功率表 / 信道 / 国别 / 频宽（"信号好"的来源） ────────
say "D 无线运行态"
snapc sys/iw-dev.txt           'iw dev'
snapc sys/iw-phy0.txt          'iw phy phy0 info'
snapc sys/iw-phy1.txt          'iw phy phy1 info'
snapc sys/iw-list.txt          'iw list'
snapc sys/iw-reg.txt           'iw reg get'
snapc sys/wifi-status.txt      'wifi status'
snapc sys/sysfs-net.txt        'ls -l /sys/class/net /sys/class/ieee80211 2>/dev/null'
snapc sys/txpower.txt          'for p in /sys/class/ieee80211/phy*; do for f in "$p"/*; do [ -f "$f" ] && { printf "%s = " "$f"; cat "$f" 2>/dev/null; }; done; done'
[ -f /etc/config/wireless ] && cp /etc/config/wireless "$OUT/conf/wireless"
snapc conf/wireless-uci.txt    'uci show wireless 2>/dev/null'

# ── E. 板级数据 / 校准：ART 与 BDF（信号强弱的关键） ──────────────────
say "E ART / BDF / 固件"
# 所有名字像校准/板级的小分区都 dump（ART 通常 1 MB，不会太大）
grep -iE '"[^"]*(ART|art|BDF|bdwlan|calib|wifi|WIFI)[^"]*"' /proc/mtd 2>/dev/null |
while IFS=: read -r dev rest; do
    dev=$(echo "$dev" | tr -d ' \t')
    [ -z "$dev" ] && continue
    printf '%s %s\n' "$dev" "$rest" >> "$OUT/mtd/matched.txt"
    dd if="/dev/$dev" of="$OUT/mtd/$dev.bin" bs=64k 2>> "$OUT/mtd/dd.log" || true
    # 字符设备读不动时回落 block 设备
    [ -s "$OUT/mtd/$dev.bin" ] || {
        n=${dev#mtd}
        dd if="/dev/mtdblock$n" of="$OUT/mtd/$dev.bin" bs=64k 2>> "$OUT/mtd/dd.log" || true
    }
done
# ART 单独留一份固定名，方便直接给我
for f in "$OUT"/mtd/*.bin; do
    [ -s "$f" ] || continue
    case "$(basename "$f")" in
        *ART*|*art*) cp "$f" "$OUT/mtd/ART.bin" 2>/dev/null && break ;;
    esac
done
snapc firmware/list.txt        'ls -lR /lib/firmware 2>/dev/null'
# 整份（判断固件形态、提取 q6/m3/mdt）
tar cf "$OUT/firmware/lib-firmware.tar" /lib/firmware 2>/dev/null || true
# 关键小文件单列（bdwlan / board-2.bin / caldata / *.mdt），串口通道用得上
find /lib/firmware -type f -size -4096k 2>/dev/null |
  grep -iE 'bdwlan|board|caldata|\.mdt|\.bin|IPQ5018|qcn61|ath11k|wcss|q6' \
  > /tmp/vs010-fwlist.txt || true
if [ -s /tmp/vs010-fwlist.txt ]; then
    tar cf "$OUT/firmware/key-files.tar" -T /tmp/vs010-fwlist.txt 2>/dev/null \
      || tar cf "$OUT/firmware/key-files.tar" $(cat /tmp/vs010-fwlist.txt) 2>/dev/null \
      || true
fi

# ── F. 打包 ────────────────────────────────────────────────────────────
say "F 打包"
# 精简包：只收「确实采到」的文件（BusyBox tar 遇到不存在的成员可能整包失败）
MINI_LIST=/tmp/vs010-mini-list.txt
: > "$MINI_LIST"
for f in fdt/fdt.dtb fdt/proc-device-tree.tar fdt/device-tree.dts fdt/wifi-props.txt \
         sys/dmesg-wifi.txt sys/dmesg.txt sys/cmdline.txt sys/mtd.txt \
         sys/iw-list.txt sys/iw-phy0.txt sys/iw-phy1.txt sys/iw-reg.txt \
         sys/wifi-status.txt sys/uname.txt sys/release.txt sys/fw-env.txt \
         sys/opkg.txt sys/debugfs.txt conf/wireless conf/wireless-uci.txt \
         firmware/list.txt firmware/key-files.tar mtd/matched.txt mtd/ART.bin; do
    [ -s "$OUT/$f" ] && echo "$f" >> "$MINI_LIST"
done
tar czf "$MINI" -C "$OUT" -T "$MINI_LIST" 2>/dev/null \
  || tar czf "$MINI" -C "$OUT" $(cat "$MINI_LIST") 2>/dev/null || true
# 完整包：再加 ART 与整份 /lib/firmware
tar czf "$FULL" -C /tmp vs010-wifi-dump 2>/dev/null || true
if [ ! -s "$OUT/fdt/fdt.dtb" ] && [ ! -s "$OUT/fdt/proc-device-tree.tar" ]; then
    say "  ⚠ 警告：fdt.dtb 与 /proc/device-tree 都没采到 —— 这份包缺决定性证据，"
    say "    请把 /proc/mtd 与 dmesg 一起发来，我至少能按日志推 board_id"
fi
# 浏览器直取（若 /www 可写）
if [ -d /www ] && [ -s "$FULL" ]; then
    cp "$FULL" /www/vs010-wifi-full.tar.gz 2>/dev/null || true
    cp "$MINI" /www/vs010-wifi-mini.tar.gz 2>/dev/null || true
fi

echo
echo "════════════════════════════════════════════════════════════"
echo " 采集完成。文件："
ls -lh "$MINI" "$FULL" 2>/dev/null
echo " md5："
md5sum "$MINI" "$FULL" 2>/dev/null
echo
echo " 把包给我，三选一："
echo "  ① 浏览器（最省事）：http://<管理IP>/vs010-wifi-full.tar.gz"
echo "     （或 /vs010-wifi-mini.tar.gz），下载后拖进对话"
echo "  ② SSH：scp root@<管理IP>:/tmp/vs010-wifi-full.tar.gz ."
echo "  ③ 串口：base64 /tmp/vs010-wifi-mini.tar.gz  然后复制文本贴过来"
echo
echo " 取完删掉浏览器副本：rm -f /www/vs010-wifi-*.tar.gz"
echo "════════════════════════════════════════════════════════════"
exit 0
