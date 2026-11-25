#!/bin/sh
# ───────────────────────────────────────────────────────────────────────
# qsdk-wifi.sh · 第 44 次 · 无线探测共用库（双栈兼容）
#
#   官方 5.4.213 闭源 qca-wifi：接口常叫 ath0/ath1/wifi0/wifi1，
#     没有 /sys/class/ieee80211、没有 mac80211；工具是 wlanconfig/wifitool，
#     但补丁版 cfg80211 仍带 iw。
#   老仓 5.4.164 开源 ath11k：接口叫 wlan0/wlan1，iw / iwinfo 齐全。
#
#   本库把差异挡在函数里，上层脚本与 CGI 只认统一输出：
#     Station <mac>
#         signal: -56
# ───────────────────────────────────────────────────────────────────────

# 列出所有无线 VAP 接口名
# ★ 第 46 次实机纠错：官方 5.4.213 里 wifi0/wifi1 是【radio】(link/ieee802.11)、
#   soc0/soc1 是内部接口，真正的 VAP 是 ath0/ath1 (link/ether，挂在 br-lan)。
#   旧版把 wifi* 也列进去，qwifi_5g() 的 tail -1 会选中 wifi1（radio），
#   导致 WDS 关联探测与机器狗判通断全错。这里只认 ath*/wlan*。
qwifi_ifaces() {
    for a in /sys/class/net/*; do
        n=${a##*/}
        case "$n" in ath[0-9]*|wlan[0-9]*) echo "$n" ;; esac
    done
    # iw dev 补一次（开源栈用 wlan*），同样排除 wifi*/soc*/bond*
    if command -v iw >/dev/null 2>&1; then
        iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' \
          | grep -E '^(ath|wlan)[0-9]' || true
    fi
}

# 去重后的接口列表
qwifi_all() { qwifi_ifaces | sort -u | grep -v '^$' || true; }

# 挑 5G 接口：优先 UCI 里 5G radio 对应的 VAP，否则取最后一个（QSDK 里 ath1/wlan1 通常是 5G）
qwifi_5g() {
    [ -s /etc/qsdk_radio ] && { cat /etc/qsdk_radio; return 0; }
    if command -v uci >/dev/null 2>&1; then
        for r in radio1 radio0 radio2 wifi1 wifi0; do
            uci -q get "wireless.$r" >/dev/null 2>&1 || continue
            c=$(uci -q get "wireless.$r.channel" 2>/dev/null)
            case "$c" in ''|*[!0-9]*) ;; *) [ "$c" -ge 36 ] 2>/dev/null && {
                # 找挂在该 radio 的 iface 对应 VAP
                i=0
                while uci -q get "wireless.@wifi-iface[$i]" >/dev/null 2>&1; do
                    d=$(uci -q get "wireless.@wifi-iface[$i].device" 2>/dev/null)
                    ifn=$(uci -q get "wireless.@wifi-iface[$i].ifname" 2>/dev/null)
                    [ "$d" = "$r" ] && [ -n "$ifn" ] && [ -d "/sys/class/net/$ifn" ] && { echo "$ifn"; return 0; }
                    i=$((i+1))
                done
            } ;; esac
        done
    fi
    # 接口名兜底：ath1 / wlan1 优先（5G VAP），绝不选 wifi1（radio）
    for n in ath1 wlan1 ath0 wlan0; do
        [ -d "/sys/class/net/$n" ] && { echo "$n"; return 0; }
    done
    qwifi_all | tail -n 1
}

# 本机接口 MAC
qwifi_mac() {
    [ -r "/sys/class/net/$1/address" ] && { tr -d '\n' < "/sys/class/net/$1/address"; echo; return 0; }
    ip link show "$1" 2>/dev/null | sed -n 's/.*link\/ether \([0-9a-fA-F:]*\).*/\1/p' | head -1
}

# 统一 station dump：输出 `Station <mac>` 与缩进 `signal: <dbm>` 行
qwifi_sta_dump() {
    ifn=$1
    out=''
    if command -v iw >/dev/null 2>&1 && [ -d "/sys/class/net/$ifn" ]; then
        out=$(iw dev "$ifn" station dump 2>/dev/null)
    fi
    if ! printf '%s\n' "$out" | grep -q '^Station ' && command -v iwinfo >/dev/null 2>&1; then
        # iwinfo assoclist 格式： MAC  -56 dBm  ...
        out=$(iwinfo "$ifn" assoclist 2>/dev/null | awk '
            /^([0-9A-Fa-f][0-9A-Fa-f]:){5}[0-9A-Fa-f][0-9A-Fa-f]/ {
                print "Station " $1
                s=$2; gsub(/[^0-9-]/,"",s)
                print "\tsignal: " s
            }')
    fi
    if ! printf '%s\n' "$out" | grep -q '^Station ' && command -v wlanconfig >/dev/null 2>&1; then
        # wlanconfig athX list 格式（QSDK）：首列 MAC，含 RSSI/SIG 列
        out=$(wlanconfig "$ifn" list 2>/dev/null | awk '
            /^([0-9A-Fa-f][0-9A-Fa-f]:){5}[0-9A-Fa-f][0-9A-Fa-f]/ {
                mac=$1; sig=""
                for(i=2;i<=NF;i++) if($i ~ /^-?[0-9]+$/) { sig=$i; break }
                print "Station " mac
                if(sig!="") print "\tsignal: " sig
            }')
    fi
    printf '%s\n' "$out"
}

# 统一 link 信息（STA 端）
qwifi_link() {
    ifn=$1
    out=''
    command -v iw >/dev/null 2>&1 && out=$(iw dev "$ifn" link 2>/dev/null)
    [ -n "$out" ] || { command -v iwinfo >/dev/null 2>&1 && out=$(iwinfo "$ifn" info 2>/dev/null); }
    [ -n "$out" ] || { command -v wlanconfig >/dev/null 2>&1 && out=$(wlanconfig "$ifn" list 2>/dev/null); }
    printf '%s\n' "$out"
}

# 关联是否成立（有 Station 行 / Connected to）
qwifi_assoc() {
    qwifi_sta_dump "$1" | grep -q '^Station ' && return 0
    qwifi_link "$1" | grep -qi 'Connected to' && return 0
    return 1
}
