#!/bin/sh
# 【双仓通用 · 25.12 DSA 版（第 47 次）】
# bridge_apply_role <ap|sta>
# 把整机刷成 UBNT airOS「Bridge 模式」等价行为：
#   纯二层透明桥（无 NAT）+ 一条 5G WDS(4addr) 链路；IPv6 关闭
# 两端共用这一段，只差 mode / 管理 IP / DHCP。开机由 bridge-role 自动调用。
. /lib/functions.sh

BRIDGE_SSID='WDS_AP'
BRIDGE_KEY='WDS123456'              # 两端必须一致
BRIDGE_CHAN='36'                     # ★ HE160 必须用 36~64 连续段；149 段只有 100MHz
BRIDGE_HTMODE='HE160'                # ★ 5G 160MHz（不支持时驱动回落 HE80）
BRIDGE_DIST='550'                    # 500 m × 110%；按实际距离用 bridge-distance 改
BRIDGE_TXPWR='20'                    # 原装天线保守值；改 14dBi 平板改 19
BRIDGE_AP_IP='172.10.10.241'         # 主（ap）
BRIDGE_STA_IP='172.10.10.242'        # 备（sta）—— 自动错开，不用刷完手改
BRIDGE_LEASE='1h'                    # ★ DHCP 租期 1 小时

bridge_find_5g() {
    # 手动指定优先：bridge-radio radioX
    [ -s /etc/bridge_radio ] && { cat /etc/bridge_radio; return 0; }
    # 其次按信道 / band 找 5G 射频
    for r in radio1 radio0 radio2; do
        uci -q get "wireless.$r" >/dev/null || continue
        c=$(uci -q get "wireless.$r.channel" 2>/dev/null)
        b=$(uci -q get "wireless.$r.band" 2>/dev/null)
        h=$(uci -q get "wireless.$r.hwmode" 2>/dev/null)
        case "$c:$b:$h" in
            *5a*|*11a*|*a:*) echo "$r"; return 0 ;;
        esac
        [ -n "$c" ] && [ "$c" -ge 36 ] 2>/dev/null && { echo "$r"; return 0; }
    done
    # 默认：QSDK 上 radio1 通常是 5G
    uci -q get wireless.radio1 >/dev/null && { echo radio1; return 0; }
    echo radio0
}

bridge_find_iface() {
    # 找挂在 5G 射频上的 wifi-iface，没有就取第一个
    local r="$1" i=0 d
    while uci -q get "wireless.@wifi-iface[$i]" >/dev/null; do
        d=$(uci -q get "wireless.@wifi-iface[$i].device" 2>/dev/null)
        [ "$d" = "$r" ] && { echo "$i"; return 0; }
        i=$((i+1))
    done
    echo 0
}

bridge_apply_role() {
    local role="$1" r idx
    [ "$role" = ap ] || [ "$role" = sta ] || { echo "role 只能是 ap 或 sta" >&2; return 1; }

    # 所有射频（含 2.4G）统一 CN —— 手动 bridge-role 重跑也不会只留 5G 是 CN
    set_cn_all() { uci -q set "wireless.$1.country=CN"; }
    config_load wireless
    config_foreach set_cn_all wifi-device

    r=$(bridge_find_5g)
    idx=$(bridge_find_iface "$r")

    # ── 1. 射频：固定信道 / 国家码 / 距离 / 功率，显式 HE160 ──
    uci set "wireless.$r.country"='CN'
    uci set "wireless.$r.channel"="$BRIDGE_CHAN"
    uci set "wireless.$r.disabled"='0'
    uci set "wireless.$r.htmode"="$BRIDGE_HTMODE"   # 显式 HE160，别让缺项回落 HE80
    uci set "wireless.$r.distance"="$BRIDGE_DIST"
    uci set "wireless.$r.txpower"="$BRIDGE_TXPWR"

    # ── 2. WDS 4addr：两端同 SSID / 同密钥 / WPA2-AES ──
    uci set "wireless.@wifi-iface[$idx].device"="$r"
    uci set "wireless.@wifi-iface[$idx].network"='lan'
    uci set "wireless.@wifi-iface[$idx].mode"="$role"
    uci set "wireless.@wifi-iface[$idx].wds"='1'
    uci set "wireless.@wifi-iface[$idx].ssid"="$BRIDGE_SSID"
    uci set "wireless.@wifi-iface[$idx].encryption"='psk2+ccmp'
    uci set "wireless.@wifi-iface[$idx].key"="$BRIDGE_KEY"
    uci set "wireless.@wifi-iface[$idx].disabled"='0'

    # ── 3. 纯二层桥：LAN+WAN 口 + 无线都在 br-lan（25.12 DSA，第 47 次）──
    # ★ 旧版写 lan.type=bridge / ifname=eth0 eth1，25.12 netifd 不解析 → 桥建不出来。
    #   改为保留 config device 'br_lan' 并只改 lan.device；STP 必须写在 device 段。
    uci -q delete network.wan
    uci -q delete network.wan6
    uci -q delete dhcp.wan
    uci -q delete dhcp.wan6
    uci -q delete network.globals.ula_prefix
    uci -q get network.br_lan >/dev/null 2>&1 || {
        uci -q set network.br_lan='device'
        uci -q set network.br_lan.name='br-lan'
        uci -q set network.br_lan.type='bridge'
        for p in lan1 lan2 lan3 wan; do uci -q add_list network.br_lan.ports="$p"; done
    }
    uci -q set network.br_lan.stp='1'
    uci -q set network.br_lan.ipv6='0'
    uci -q delete network.lan.type
    uci -q delete network.lan.ifname
    while uci -q get network.@switch[0] >/dev/null 2>&1; do uci -q delete network.@switch[0]; done
    while [ -n "$(uci -q get network.@switch_vlan[0].vlan 2>/dev/null)" ]; do
        uci -q delete network.@switch_vlan[0]
    done
    uci -q set network.lan.device='br-lan'
    uci -q set network.lan.proto='static'
    uci -q set network.lan.force_link='1'
    # ★ 主/备自动错开管理 IP，刷完不用再手动改，避免两台都 172.10.10.241 的 ARP 冲突
    if [ "$role" = 'sta' ]; then
        uci set network.lan.ipaddr="$BRIDGE_STA_IP"
    else
        uci set network.lan.ipaddr="$BRIDGE_AP_IP"
    fi
    uci set network.lan.netmask='255.255.252.0'
    uci -q delete network.lan.gateway
    uci -q delete network.lan.dns

    # ── 4. DHCP：主(ap) 开、备(sta) 关，租期 1h；IPv6 编译期已关，配置面全清空 ──
    #     备端关 DHCP 避免双 DHCP 抢地址；bridge-dhcp on/off/lease 可随时改
    if [ "$role" = 'sta' ]; then
        uci set dhcp.lan.ignore='1'
    else
        uci set dhcp.lan.ignore='0'
    fi
    uci -q set dhcp.lan.start='100'
    uci -q set dhcp.lan.limit='100'
    uci -q set dhcp.lan.leasetime="$BRIDGE_LEASE"
    uci -q delete dhcp.lan.ra
    uci -q delete dhcp.lan.dhcpv6
    uci -q delete dhcp.lan.ndp
    uci -q delete network.lan.ip6assign
    uci -q delete network.lan.ipv6
    [ -x /etc/init.d/dnsmasq ] && { /etc/init.d/dnsmasq enable 2>/dev/null || true; /etc/init.d/dnsmasq restart 2>/dev/null || true; }
    [ -x /etc/init.d/odhcpd ] && { /etc/init.d/odhcpd stop 2>/dev/null || true; /etc/init.d/odhcpd disable 2>/dev/null || true; }

    # ── 5. 防火墙已整体移除（第 3 次更新）──
    # 第 12 次校准：firewall 包编回但服务禁用、/etc/config/firewall 不生成、LuCI 无菜单。
    # 纯二层透明桥不做 NAT、无 WAN、无 WAN/LAN 隔离，天然等价全放行。
    # 切角色时顺手清掉旧固件升级可能残留的配置。
    rm -f /etc/config/firewall 2>/dev/null || true

    uci commit wireless
    uci commit network
    uci commit dhcp

    # 给 bridge-status 留一份可读的运行信息
    printf 'role=%s\nradio=%s\niface=%s\nssid=%s\nchan=%s\ndistance=%s\ntxpower=%s\n' \
        "$role" "$r" "$idx" "$BRIDGE_SSID" "$BRIDGE_CHAN" "$BRIDGE_DIST" "$BRIDGE_TXPWR" \
        > /etc/bridge_info
    printf '%s\n' "$role" > /etc/bridge_role
    local ip
    if [ "$role" = 'sta' ]; then ip="$BRIDGE_STA_IP"; else ip="$BRIDGE_AP_IP"; fi

    # 第 50 次：WDS 角色链路本地别名（与管理 IP 解耦，机器狗互 ping 用）
    #   主(ap) 挂 169.254.241.1/16、备(sta) 挂 169.254.241.2/16。
    #   避开 AP 模式调试别名 169.254.240.1；改管理 IP 后这两个别名不变。
    #   两台都刷 WDS 时各挂各的，不冲突；bridge-netfix / health-fix 还会兜底补挂。
    local _ll_self='169.254.241.1' _ll_other='169.254.241.2'
    [ "$role" = 'sta' ] && { _ll_self='169.254.241.2'; _ll_other='169.254.241.1'; }
    ip addr show br-lan 2>/dev/null | grep -qF "$_ll_self/16" \
      || ip addr add "$_ll_self/16" dev br-lan 2>/dev/null || true
    ip addr show br-lan 2>/dev/null | grep -qF "$_ll_other/16" \
      && ip addr del "$_ll_other/16" dev br-lan 2>/dev/null || true

    echo "  ✓ 角色 $role | 5G=$r | iface=$idx | ch=$BRIDGE_CHAN/$BRIDGE_HTMODE | IP=$ip | 别名=$_ll_self/16 | DHCP=$([ "$role" = sta ] && echo 关 || echo "$BRIDGE_LEASE") | WDS/4addr"
}
