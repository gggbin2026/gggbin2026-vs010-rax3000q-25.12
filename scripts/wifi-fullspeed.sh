#!/bin/bash
# 无线加速/满速：把「NSS FW 12.5 / ECM→NSS / CN+ch36+HE160 / 256M LOW /
# 本机 BDF」口径写进编译期 files/，并放一个只读自检脚本。
#
# 2026-11-24 第二次修订（参考 mufeng05/openwrt-cmcc-pz-l8-nss 后修正）：
#  · 之前把 nss.general.wifi_offload=1 当通用总开关是错的——它只存在于
#    kuncy7 c3po 那条 UCI 里。QSDK14 / PZ-L8 路径根本没有这个配置项，
#    无条件 `uci set` 会凭空造出 /etc/config/nss，属于「系统问题」。
#    改为：只有配置项本来就存在时才拉回 1；否则只检测 ECM→NSS/wifili 实况。
#  · NSS 固件 12.5 优先（PZ-L8 自测相对 12.2 +65%；kuncy7 nss-packages
#    2026-10-16 起 ipq50xx 默认 12.5、11-20 起同时发布 12.5 与 12.2）。
#  · 真实加速路径是 ECM→NSS，SFE/shortcut_fe 在本平台连接表为空属预期。
#  · 被卸载的流量不经过 Linux 网桥：eth0/eth1 各 989 Mbps 时 br-lan 只有 52，
#    所以判速读 eth0/eth1 + NSS debugfs，绝不读 br-lan 说「没加速」。
#  · CN + HE160 覆盖 DFS，开机 5G 要等约 60s CAC；2.4G HE40 默认因共存退 20MHz。
#
# 用法: scripts/wifi-fullspeed.sh <merged-files-dir> <baseline> <mode>
set -euo pipefail
F="${1:?files dir}"; BASE="${2:-qosmio-25.12-nss}"; MODE="${3:-wds}"
[ -d "$F/etc/config" ] || { echo "::error::不是 overlay 目录"; exit 1; }

echo "==================== [wifi-fullspeed] ECM→NSS 口径注入 ===================="

mkdir -p "$F/usr/sbin"
cat > "$F/usr/sbin/wifi-fullspeed" <<'EOS'
#!/bin/sh
# 无线加速自检：只读打印，不改任何配置。串口/SSH 直接跑 `wifi-fullspeed`。
# 判据参考 mufeng05/openwrt-cmcc-pz-l8-nss：NSS 占用 / 加速连接数 /
# wifili / eth0-eth1 计数；纯二层桥下 br-lan 计数偏低属预期。
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH
say(){ printf '%-26s %s\n' "$1" "$2"; }
mod(){ grep -qE "^$1 " /proc/modules 2>/dev/null && echo 已加载 || echo 未加载; }
firstnum(){ grep -oE '[0-9]+' 2>/dev/null | head -1 || echo ''; }

say "内核" "$(uname -r 2>/dev/null)"
say "架构" "$(uname -m 2>/dev/null)"
say "固件模式" "$(cat /etc/firmware_mode 2>/dev/null || echo unknown)"
say "基线" "$(sed -n 's/^BASELINE=//p' /etc/build-info 2>/dev/null | head -1 || echo unknown)"

echo
say "--- NSS 数据面（ECM→NSS，SFE 不干活）---" ""
say "  qca_nss_drv" "$(mod qca_nss_drv)"
say "  qca_nss_ecm" "$(mod qca_nss_ecm)"
say "  wifili（双射频卸载）" "$(grep -qE '^wifili ' /proc/modules 2>/dev/null && echo 已加载 || echo 未加载)"
say "  ath11k" "$(mod ath11k)"
say "  shortcut_fe / SFE" "$(mod shortcut_fe)（连接表为空属预期）"
LOAD=$(cat /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi 2>/dev/null | firstnum)
CONN=$(cat /sys/kernel/debug/ecm/ecm_db/connection_count 2>/dev/null | firstnum)
say "  NSS 核占用" "${LOAD:-不可用} %（/sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi）"
say "  ECM 加速连接数" "${CONN:-不可用}（/sys/kernel/debug/ecm/ecm_db/connection_count）"
FW=$(dmesg 2>/dev/null | grep -oE 'NSS[._]FW[._]?[0-9]+\.[0-9]+(-[0-9]+)?' | tail -1)
[ -z "$FW" ] && FW=$(ls /lib/firmware/ 2>/dev/null | grep -iE 'nss.*12\.5|12\.2' | head -1)
say "  NSS 固件版本" "${FW:-未从 dmesg 读到}（目标 12.5；12.2 仅回退）"

# wifi_offload 只在配置本来就存在时才有意义
OFF='本基线无此 UCI 配置项（正常，走 ECM→NSS 自动卸载）'
if command -v uci >/dev/null 2>&1; then
    cur=$(uci -q get nss.general.wifi_offload 2>/dev/null || echo '')
    [ -n "$cur" ] && OFF="$cur"
fi
say "  nss.general.wifi_offload" "$OFF"

echo
say "--- 逐端口计数：只读 eth0 / eth1，不读 br-lan ---" ""
for e in eth0 eth1; do
    d=/sys/class/net/$e
    [ -d "$d" ] || continue
    tx=$(cat "$d/statistics/tx_bytes" 2>/dev/null || echo 0)
    rx=$(cat "$d/statistics/rx_bytes" 2>/dev/null || echo 0)
    say "  $e" "TX=$tx B  RX=$rx B  oper=$(cat "$d/operstate" 2>/dev/null || echo '?')"
done
say "  提示" "被 NSS 卸载的包不进 Linux 网桥；br-lan 计数偏低不代表没加速"

echo
say "--- 射频实况（iw dev）---" ""
if command -v iw >/dev/null 2>&1; then
    for i in $(ls /sys/class/net 2>/dev/null | grep -E '^(wlan|phy[0-9]+-ap)'); do
        info=$(iw dev "$i" info 2>/dev/null || true)
        [ -z "$info" ] && continue
        ch=$(printf '%s\n' "$info" | sed -n 's/.*channel \([0-9]*\).*/\1/p' | head -1)
        wd=$(printf '%s\n' "$info" | sed -n 's/.*width \([0-9]* MHz\).*/\1/p' | head -1)
        say "  $i" "ch=${ch:-?} width=${wd:-?} type=$(printf '%s\n' "$info" | sed -n 's/.*type \(.*\)/\1/p' | head -1)"
    done
else
    say "  iw" "未安装"
fi

echo
say "--- 出厂无线配置（UCI）---" ""
for r in radio0 radio1; do
    [ -f /etc/config/wireless ] || break
    band=$(uci -q get "wireless.$r.band" 2>/dev/null || echo '?')
    ch=$(uci -q get "wireless.$r.channel" 2>/dev/null || echo '?')
    ht=$(uci -q get "wireless.$r.htmode" 2>/dev/null || echo '?')
    cc=$(uci -q get "wireless.$r.country" 2>/dev/null || echo '?')
    ns=$(uci -q get "wireless.$r.noscan" 2>/dev/null || echo '0')
    dis=$(uci -q get "wireless.$r.disabled" 2>/dev/null || echo '0')
    say "  $r" "band=$band ch=$ch htmode=$ht country=$cc noscan=$ns disabled=$dis"
done

echo
say "--- 温度（PZ-L8 口径）---" ""
for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/temp" ] && [ -r "$z/type" ] || continue
    nm=$(cat "$z/type" 2>/dev/null)
    case "$nm" in *cpu*|*CPU*) say "  CPU $nm" "$(( $(cat "$z/temp") / 1000 )) °C" ;; esac
done
for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue
    case "$(cat "$h/name" 2>/dev/null)" in ath11k*) ;; *) continue ;; esac
    dt=$(basename "$(readlink -f "$h/device" 2>/dev/null)" 2>/dev/null || basename "$h")
    for t in "$h"/temp*_input; do
        [ -r "$t" ] || continue
        say "  射频 $dt" "$(( $(cat "$t") / 1000 )) °C（按设备树节点，不按 phy 编号）"
    done
done

echo
say "--- 校准 / 固件 ---" ""
for f in /lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin \
         /lib/firmware/ath11k/IPQ5018/hw1.0/q6_fw.mdt; do
    [ -f "$f" ] && say "  $(basename "$f")" "$(ls -l "$f" | awk '{print $5}') B"
done
say "  256M profile" "$(cat /sys/module/ath11k/parameters/fw_memory_mode 2>/dev/null || echo '看 dmesg: FW memory mode')"

echo
say "结论" "满速 = NSS FW 12.5 + ECM→NSS/wifili + CN + 5G ch36 HE160 + 本机 BDF + 256M LOW"
say "DFS" "CN+HE160 覆盖 DFS：开机 5G 约 60s CAC 期间不可见，2.4G 先起；改 HE80 免等但吞吐少约 1/3"
say "2.4G" "HE40 默认因共存扫描退 20MHz；uci set wireless.radio0.noscan=1 可强开（无视邻区，慎用）"
say "判速" "看 eth0/eth1 + NSS cpu_load_ubi / connection_count，不要看 br-lan"
say "回退" "仅当配置项存在时：uci set nss.general.wifi_offload=0; uci commit nss; reboot"
EOS
chmod 755 "$F/usr/sbin/wifi-fullspeed"
echo "  ✓ /usr/sbin/wifi-fullspeed（只读自检，ECM→NSS 口径）"

mkdir -p "$F/etc/init.d"
cat > "$F/etc/init.d/wifi-fullspeed" <<'EOS'
#!/bin/sh /etc/rc.common
# 无线满速兜底：START=24，晚于 l2-guard(22)，早于 network/wifi。
# 2026-11-24 修正：绝不凭空创建 /etc/config/nss。
#   nss.general.wifi_offload 只存在于 kuncy7 c3po 那条 UCI；QSDK14/ECM→NSS
#   路径没有这个配置项，旧版无条件 uci set 会造出无用配置文件（系统问题）。
USE_PROCD=0
START=24
STOP=90

start() {
    command -v uci >/dev/null 2>&1 || return 0
    # 只有配置项本来就存在时才拉回 1，不新建任何 UCI 段
    cur=$(uci -q get nss.general.wifi_offload 2>/dev/null || echo '')
    if [ -n "$cur" ] && [ "$cur" != '1' ]; then
        uci -q set nss.general.wifi_offload='1'
        uci commit nss
        logger -t wifi-fullspeed 'wifi_offload 已拉回 1（该基线确有此配置项）'
    fi
    # 5G 必须 CN + ch36 + HE160，世界域会悄悄退回 80MHz
    [ -f /etc/config/wireless ] || return 0
    for r in radio0 radio1; do
        uci -q set "wireless.$r.country"='CN' 2>/dev/null || true
        uci -q set "wireless.$r.disabled"='0' 2>/dev/null || true
    done
    uci -q set wireless.radio1.channel='36' 2>/dev/null || true
    uci -q set wireless.radio1.htmode='HE160' 2>/dev/null || true
    uci commit wireless 2>/dev/null || true
    # 2.4G noscan 默认保持 0（共存优先，最稳），不在这里强开
}
EOS
chmod 755 "$F/etc/init.d/wifi-fullspeed"
echo "  ✓ /etc/init.d/wifi-fullspeed（不造无用 UCI 配置）"

W="$F/etc/config/wireless"
if [ -f "$W" ]; then
  python3 - "$W" <<'PY'
import re, sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
def setopt(sec, key, val):
    global s
    m=re.search(r"(config wifi-device '"+re.escape(sec)+r"'\n)(.*?)(?=\nconfig |\Z)", s, re.S)
    if not m: return
    seg=m.group(2)
    pat=re.compile(r"^[ \t]*option "+re.escape(key)+r" .*$", re.M)
    line="\toption %s '%s'"%(key,val)
    if pat.search(seg): seg=pat.sub(line, seg, count=1)
    else: seg=seg.rstrip()+"\n"+line+"\n"
    s=s[:m.start(2)]+seg+s[m.end(2):]
for sec,key,val in [('radio0','country','CN'),('radio1','country','CN'),
                    ('radio1','channel','36'),('radio1','htmode','HE160'),
                    ('radio0','htmode','HE40'),('radio0','channel','1')]:
    setopt(sec,key,val)
open(p,'w',encoding='utf-8').write(s)
print('[wifi-fullspeed] wireless: CN / 2.4G ch1 HE40(noscan=0) / 5G ch36 HE160')
PY
fi

mkdir -p "$F/etc"
cat > "$F/etc/wifi-profile" <<EOF
# 无线加速档案（由 scripts/wifi-fullspeed.sh 生成，状态页读取）
BASELINE=$BASE
MODE=$MODE
WIFI_TARGET=fullspeed
WIFI_NSS_FW=12.5
WIFI_OFFLOAD_PATH=ecm-nss
NSS_WIFI_OFFLOAD=conditional      # 仅当基线确有该 UCI 配置项时才拉回 1
BAND_5G=HE160
CHANNEL_5G=36
COUNTRY=CN
DFS_CAC=60s
BAND_2G=HE40
NOSCAN_2G=0
MEM_PROFILE=256M_LOW
SPEED_SOURCE=eth0/eth1            # 不取 br-lan：被卸载流量不经过 Linux 网桥
# 参考实测（mufeng05 PZ-L8，非本板保证值）：
#   有线 949/949 Mbps @ +0% 主机 CPU；5G 160MHz 697 Mbps @ 2.9%；80MHz 462 Mbps
#   2.4G 20MHz 75 Mbps / 40MHz noscan 112.5 Mbps
EOF
echo "  ✓ /etc/wifi-profile（12.5 / ECM→NSS / DFS / eth0-eth1 判速）"
echo "[wifi-fullspeed] ✓ 完成（$BASE / $MODE）"
