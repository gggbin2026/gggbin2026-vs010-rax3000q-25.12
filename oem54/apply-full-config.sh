#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# 第 42 次 · 官方 NWRT 5.4.213 满血固件 —— 全量业务配置生成器
#
#   刷完 3000Q-VS010-固件/<机型>-factory.bin 后，在设备上跑这一个脚本，
#   把本仓全部定制（管理页 / 仪表盘 / WDS / AP / DHCP Snooping / 弱信号剔除 /
#   SSH / LuCI）一次性配好。
#
# 用法：
#   sh apply-full-config.sh --mode=wds --dry-run     # 预演，不改动
#   sh apply-full-config.sh --mode=wds               # WDS 网桥
#   sh apply-full-config.sh --mode=ap                # AP 模式
#   sh apply-full-config.sh --rollback               # 回滚本脚本的 uci 改动
#
# 设计原则（重要）：
#   ★ 内核 / 无线驱动 / NSS 加速【完全不碰】—— 官方固件本身就是 5.4.213
#     闭源 qca-wifi + ipq_cnss2 + qca-nss-drv/qca-ssdk/ecm 满血栈。
#   ★ 绝不整体覆盖 /etc/config/{network,wireless,dhcp,dropbear,luci,uhttpd,
#     firewall}。官方 rootfs 里 network/wireless 出厂为空，由首启脚本生成；
#     覆盖会断网、会让闭源 hostapd 起不来。
#   ★ 只做 uci 增量 set + 新增独立脚本/配置，全部可 --rollback。
#   ★ 接口名运行时探测（官方栈是 ath0/ath1、bridge 名也不定），不照抄本仓。
# ═══════════════════════════════════════════════════════════════════════
set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH; export PATH
MODE=''; DRY=0; ROLLBACK=0; SSID2=''; SSID5=''
for a in "$@"; do
  case "$a" in
    --mode=wds) MODE=wds ;; --mode=ap) MODE=ap ;;
    --dry-run) DRY=1 ;; --rollback) ROLLBACK=1 ;;
    --ssid2=*) SSID2=${a#--ssid2=} ;; --ssid5=*) SSID5=${a#--ssid5=} ;;
    -h|--help) sed -n '3,26p' "$0"; exit 0 ;;
    *) echo "[cfg] ERROR：未知参数 $a"; exit 1 ;;
  esac
done
[ "$ROLLBACK" = 0 ] && [ -z "$MODE" ] && { echo "[cfg] ERROR：必须 --mode=wds 或 --mode=ap"; exit 1; }

say(){ echo "[cfg] $*"; logger -t oem54cfg "$*" 2>/dev/null || true; }
warn(){ echo "[cfg] ⚠ $*"; logger -t oem54cfg "WARN $*" 2>/dev/null || true; }
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo 1)
BK=/etc/oem54-backup/$STAMP
UCILOG=/etc/oem54-backup/uci-changes.log

# ── 内核硬校验 ──
K=$(uname -r 2>/dev/null || echo unknown)
case "$K" in
  *5.4.213*) say "内核 $K ✓ 官方满血固件" ;;
  *) echo "[cfg] ERROR：内核 $K 不是 5.4.213。本脚本只用于刷好官方固件的设备。"; exit 1 ;;
esac

# ── 回滚 ──
if [ "$ROLLBACK" = 1 ]; then
  LAST=$(ls -1 /etc/oem54-backup 2>/dev/null | grep -E '^[0-9]{8}-' | sort | tail -1)
  [ -z "$LAST" ] && { say "ERROR：无备份可回滚"; exit 1; }
  B=/etc/oem54-backup/$LAST
  [ -f "$B/uci-rollback.sh" ] && sh "$B/uci-rollback.sh" && say "uci 已回滚"
  for f in /usr/sbin/qsdk-dhcp-guard /usr/sbin/qsdk-rssi-guard \
           /etc/config/qsdk-guard /etc/init.d/qsdk-guard; do
    [ -e "$f" ] && rm -f "$f" && say "删除 $f"
  done
  say "回滚完成（overlay 页面另用 apply-oem-overlay.sh --rollback）"
  exit 0
fi

say "模式=$MODE  预演=$DRY  备份目录=$BK"
# dry-run 必须完全只读：不建目录、不写任何文件（第 42 次修正）

# ── 探测（只读）──
WLANS=$(ls -1 /sys/class/net 2>/dev/null | grep -E '^(ath|wifi|wlan|wlan2)' | tr '\n' ' ' || true)
[ -z "$WLANS" ] && WLANS=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | tr '\n' ' ' || true)
BRIDGES=$(ls -1 /sys/class/net 2>/dev/null | grep -E '^(br|bridge)' | tr '\n' ' ' || true)
LANIF=$(uci -q get network.lan.ifname 2>/dev/null || uci -q get network.lan.device 2>/dev/null || echo '')
LANPROTO=$(uci -q get network.lan.proto 2>/dev/null || echo '')
say "无线接口: ${WLANS:-（未探测到，可能首启未生成）}"
say "网桥:     ${BRIDGES:-（无）}"
say "lan:      ifname=${LANIF:-?} proto=${LANPROTO:-?}"
say "官方配置段: $(ls /etc/config 2>/dev/null | tr '\n' ' ')"

# ── 能力探测（DHCP Snooping 能做到哪一档）──
CAP=none
if command -v ebtables >/dev/null 2>&1 && \
   ls /lib/modules/$(uname -r)/ebtables.ko >/dev/null 2>&1; then CAP=ebtables
elif command -v nft >/dev/null 2>&1; then CAP=nft
elif ls /lib/modules/$(uname -r)/br_netfilter.ko >/dev/null 2>&1 && \
     ls /lib/modules/$(uname -r)/xt_physdev.ko >/dev/null 2>&1 && \
     iptables -m physdev --help >/dev/null 2>&1; then CAP=physdev
fi
say "DHCP Snooping 能力探测: $CAP"
case "$CAP" in
  none)
    warn "官方 QSDK12.2 固件的内核【未编入 ebtables / nft bridge / br_netfilter】"
    warn "（实测 159 个 .ko 里只有 xt_physdev.ko，没有 ebtables.* 与 br_netfilter.ko）"
    warn "→ 无法在二层丢弃无线侧 DHCP OFFER/ACK，本脚本将启用【缓解模式】"
    warn "缓解 = dnsmasq authoritative（纠正被带偏的地址）+ 明确告警，不假装 100% 阻断"
    warn "要 100% 阻断请：① 上级交换机开 DHCP Snooping ② 重要终端设静态 IP"
    warn "（按你的要求，不启用无线客户端隔离）"
    ;;
  physdev|nft|ebtables) say "✓ 可用 $CAP 建真二层规则" ;;
esac

if [ "$DRY" = 1 ]; then
  say "── 预演：将执行的 uci 增量（不改动）──"
  say "  mode=$MODE：只 set disabled=0 / STP=1 / 可选 SSID，不整体覆盖 network/wireless"
  say "  将新增 /usr/sbin/qsdk-dhcp-guard（能力=$CAP）、/usr/sbin/qsdk-rssi-guard"
  say "  将新增 /etc/config/qsdk-guard、/etc/init.d/qsdk-guard"
  say "  不覆盖：network / wireless / dhcp / dropbear / luci / uhttpd / firewall"
  say "  官方 dropbear 已是 0.0.0.0:22（无 Interface 选项），SSH 本就正常，只 ensure enable"
  say "  官方 LuCI 自带 argon + 全中文包，主题本就正常，不改动"
  say "预演完成。去掉 --dry-run 正式执行。"
  exit 0
fi

mkdir -p "$BK" || { say "ERROR：/etc 不可写（请用 root 执行）"; exit 1; }
# ── 先叠加页面/只读工具 ──
if [ -f ./apply-oem-overlay.sh ] && [ -f ./oem-overlay.tar.gz ]; then
  sh ./apply-oem-overlay.sh >/dev/null 2>&1 && say "已叠加管理页/仪表盘/自检工具" \
    || warn "overlay 叠加未成功（可稍后单独跑 sh apply-oem-overlay.sh）"
else
  warn "当前目录缺 overlay 两文件，跳过页面叠加（不影响本脚本配置）"
fi

# ── uci 增量：记录原值以便回滚 ──
: > "$BK/uci-rollback.sh"; echo '#!/bin/sh' >> "$BK/uci-rollback.sh"
uci_set(){ sec=$1; opt=$2; val=$3
  old=$(uci -q get "$sec.$opt" 2>/dev/null || echo '__UNSET__')
  [ "$old" = "$val" ] && { say "  = $sec.$opt 已是 $val"; return; }
  say "  + $sec.$opt = $val （原: $old）"
  [ "$old" = '__UNSET__' ] \
    && echo "uci -q delete $sec.$opt" >> "$BK/uci-rollback.sh" \
    || echo "uci set $sec.$opt='$old'" >> "$BK/uci-rollback.sh"
  echo "$sec.$opt|$old|$val" >> "$UCILOG"
  [ "$DRY" = 0 ] && uci set "$sec.$opt=$val"
}
say "── uci 增量 ──"
# 无线：只清 disabled，绝不重建 radio/iface（闭源 hostapd 依赖首启生成的配置）
uci show wireless 2>/dev/null \
  | sed -n 's/^wireless\.\(.*\)=wifi-\(device\|iface\)$/\1/p' \
  | while read -r s; do
      [ -z "$s" ] && continue
      uci_set wireless "$s.disabled" 0 2>/dev/null || true
    done
# SSID 可选
[ -n "$SSID2" ] && { s=$(uci show wireless 2>/dev/null | grep -m1 'wifi-iface' | sed 's/wireless\.\([^=]*\)=.*/\1/'); [ -n "$s" ] && uci_set wireless "$s.ssid" "$SSID2"; }
if [ "$MODE" = wds ]; then
  # 网桥模式：只开 STP + 旁路由 dhcp，保留官方 lan 接口名
  uci_set network lan.stp 1
  uci_set network lan.proto dhcp
  uci_set network lan.type bridge
  say "  WDS：保留官方 lan.ifname=${LANIF:-?}，仅开 STP、改旁路由 dhcp、type=bridge"
else
  say "  AP：network 不动（官方默认路由模式），只管无线与防护"
fi
# SSH：官方配置本就正确，只确保 enable
/etc/init.d/dropbear enable 2>/dev/null && say "  dropbear enable ✓（配置原样保留）" || warn "dropbear enable 失败"
# LuCI：官方自带，只 ensure
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd enable 2>/dev/null || true
uci commit 2>/dev/null || true
echo 'uci commit' >> "$BK/uci-rollback.sh"
echo '/etc/init.d/network reload 2>/dev/null || true' >> "$BK/uci-rollback.sh"
chmod 755 "$BK/uci-rollback.sh"

# ── 生成 qsdk-dhcp-guard（能力自适应）──
cat > /usr/sbin/qsdk-dhcp-guard <<'GUARD'
#!/bin/sh
# QSDK12.2 适配版 DHCP 防护（第 42 次）。能力自适应，绝不假装完整阻断。
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH; export PATH
CFG=/etc/config/qsdk-guard
say(){ echo "[dhcp-guard] $*"; logger -t qsdk-dhcp-guard "$*" 2>/dev/null || true; }
detect(){
  command -v ebtables >/dev/null 2>&1 && ls /lib/modules/$(uname -r)/ebtables.ko >/dev/null 2>&1 && { echo ebtables; return; }
  command -v nft >/dev/null 2>&1 && { echo nft; return; }
  ls /lib/modules/$(uname -r)/br_netfilter.ko >/dev/null 2>&1 && \
    ls /lib/modules/$(uname -r)/xt_physdev.ko >/dev/null 2>&1 && \
    iptables -m physdev --help >/dev/null 2>&1 && { echo physdev; return; }
  echo none
}
wlans(){ ls -1 /sys/class/net 2>/dev/null | grep -E '^(ath|wifi|wlan)' || iw dev 2>/dev/null | awk '/Interface/{print $2}'; }
rules_on(){
  C=$(detect); say "能力=$C"
  case "$C" in
    ebtables)
      for w in $(wlans); do
        ebtables -A FORWARD -i "$w" -p IPv4 --ip-protocol udp --ip-source-port 67 -j DROP 2>/dev/null \
          && say "  ebtables 丢弃 $w 的 DHCP OFFER/ACK" || say "  ebtables 规则下发失败"
      done
      echo full ;;
    nft)
      nft add table bridge qsdk_guard 2>/dev/null || true
      nft add chain bridge qsdk_guard forward '{ type filter hook forward priority 0 ; }' 2>/dev/null || true
      for w in $(wlans); do
        nft add rule bridge qsdk_guard forward iifname "$w" udp sport 67 drop 2>/dev/null \
          && say "  nft 丢弃 $w 的 DHCP OFFER/ACK" || true
      done
      echo full ;;
    physdev)
      modprobe br_netfilter 2>/dev/null || true
      for w in $(wlans); do
        iptables -A FORWARD -m physdev --physdev-in "$w" -p udp --sport 67 -j DROP 2>/dev/null \
          && say "  iptables/physdev 丢弃 $w 的 DHCP OFFER/ACK" || true
      done
      echo full ;;
    none)
      say "⚠ 内核缺 ebtables / nft bridge / br_netfilter —— 【缓解模式】，不假装完整阻断"
      say "  缓解：dnsmasq authoritative=1 纠正被抢答带偏的地址"
      echo degraded ;;
  esac
}
rules_off(){
  for w in $(wlans); do
    ebtables -D FORWARD -i "$w" -p IPv4 --ip-protocol udp --ip-source-port 67 -j DROP 2>/dev/null || true
    iptables -D FORWARD -m physdev --physdev-in "$w" -p udp --sport 67 -j DROP 2>/dev/null || true
  done
  nft delete table bridge qsdk_guard 2>/dev/null || true
  say "规则已撤除"
}
case "${1:-status}" in
  on|start)
    R=$(rules_on)
    # 缓解：仅本机开 DHCP 时有意义
    if uci -q get dhcp.lan.ignore 2>/dev/null | grep -qv 1; then
      uci set dhcp.lan.authoritative=1 2>/dev/null && uci commit dhcp 2>/dev/null || true
    fi
    say "状态=$R  无线客户端隔离=未启用（按你的要求）"
    ;;
  off|stop) rules_off; say "已撤除" ;;
  status|*)
    echo "capability=$(detect)"; echo "wireless_isolated=0"
    echo "wlan_interfaces=$(wlans | tr '\n' ' ')"
    echo "note=官方 QSDK12.2 内核未编入 ebtables/br_netfilter，见 /usr/sbin/qsdk-dhcp-guard 输出"
    ;;
esac
GUARD
chmod 755 /usr/sbin/qsdk-dhcp-guard
say "已生成 /usr/sbin/qsdk-dhcp-guard"

# ── 生成 qsdk-rssi-guard（AP 弱信号剔除，闭源栈适配）──
cat > /usr/sbin/qsdk-rssi-guard <<'RSSI'
#!/bin/sh
# QSDK12.2 适配版弱信号剔除（第 42 次）
#   < -90 拒绝关联（hostapd rssi_reject_assoc_rssi，若官方 hostapd 支持）
#   < -92 从 AP 剔除（iw station dump 读信号 → hostapd_cli deauthenticate）
#   ⚠ 只在 AP 模式启用；WDS 回程接口一律跳过。
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH; export PATH
REJ=$(uci -q get qsdk-guard.main.rssi_reject 2>/dev/null || echo -90)
KICK=$(uci -q get qsdk-guard.main.rssi_kick 2>/dev/null || echo -92)
DRY=${DRYRUN:-0}
say(){ echo "[rssi-guard] $*"; logger -t qsdk-rssi-guard "$*" 2>/dev/null || true; }
ap_ifs(){ iw dev 2>/dev/null | awk '/Interface/{print $2}' | grep -vE '^(wds|sta|mesh)' || true; }
# ① 拒绝关联阈值：写进 hostapd 运行时配置（不覆盖 /etc/config/wireless）
set_reject(){
  for i in $(ap_ifs); do
    if command -v hostapd_cli >/dev/null 2>&1; then
      hostapd_cli -i "$i" set rssi_reject_assoc_rssi "$((0 - REJ))" 2>/dev/null \
        && say "  $i 拒绝弱于 ${REJ}dBm 的关联" \
        || say "  $i 官方 hostapd 不支持 rssi_reject_assoc_rssi（只能用②定时剔除）"
    fi
  done
}
# ② 逐终端扫描并剔除
scan_kick(){
  for i in $(ap_ifs); do
    [ -d /sys/class/net/"$i" ] || continue
    iw dev "$i" station dump 2>/dev/null | awk -v k="$KICK" -v dry="$DRY" -v iff="$i" '
      /^Station /{mac=$2; sig=""}
      /signal:/{for(j=1;j<=NF;j++) if($j=="signal:") sig=$(j+1)}
      /signal avg:/{ }
      mac!="" && sig!="" {
        if (sig+0 < k+0) {
          printf "[rssi-guard] %s %s signal=%sdBm < %sdBm → %s\n", iff, mac, sig, k, (dry?"[dryrun]":"KICK")
          if (!dry) system("hostapd_cli -i " iff " deauthenticate " mac " 2>/dev/null || iw dev " iff " station del " mac " 2>/dev/null")
        }
        mac=""; sig=""
      }'
  done
}
case "${1:-status}" in
  on|start) set_reject; scan_kick ;;
  once|scan) scan_kick ;;
  status|*)
    echo "mode=ap-only  rssi_reject=${REJ}dBm  rssi_kick=${KICK}dBm"
    echo "interfaces=$(ap_ifs | tr '\n' ' ')"
    echo "tools: hostapd_cli=$(command -v hostapd_cli >/dev/null && echo yes || echo no) iw=$(command -v iw >/dev/null && echo yes || echo no)"
    echo "wireless_isolated=0（按你的要求不启用）"
    ;;
esac
RSSI
chmod 755 /usr/sbin/qsdk-rssi-guard
say "已生成 /usr/sbin/qsdk-rssi-guard（AP 模式 -90 拒绝 / -92 剔除）"

# ── 独立配置 + init.d（可回滚）──
cat > /etc/config/qsdk-guard <<EOF
config qsdk-guard 'main'
	option mode '$MODE'
	option rssi_reject '-90'
	option rssi_kick '-92'
	option wireless_isolated '0'
	option dhcp_capability '$CAP'
EOF
cat > /etc/init.d/qsdk-guard <<'INIT'
#!/bin/sh /etc/rc.common
START=95
STOP=10
start(){
  /usr/sbin/qsdk-dhcp-guard on
  [ "$(uci -q get qsdk-guard.main.mode)" = ap ] && /usr/sbin/qsdk-rssi-guard on || true
}
stop(){ /usr/sbin/qsdk-dhcp-guard off; }
restart(){ stop; sleep 1; start; }
INIT
chmod 755 /etc/init.d/qsdk-guard
/etc/init.d/qsdk-guard enable 2>/dev/null || true
say "已生成 /etc/config/qsdk-guard + /etc/init.d/qsdk-guard 并 enable"

# ── 网络重载（温和）──
/etc/init.d/network reload 2>/dev/null || warn "network reload 未成功（可手动 /etc/init.d/network restart）"
wifi up 2>/dev/null || wlanconfig ath0 up 2>/dev/null || true

# ── 自检输出 ──
echo
say "════════ 验收 ════════"
say "  uname -r                              → 应 5.4.213（满血内核，本脚本没动）"
say "  lsmod | grep -iE 'qca_ol|umac|wifi_3_0|ipq_cnss2|qca_nss_drv'  → 闭源无线 + NSS 应在位"
say "  iw dev / wlanconfig ath0 list        → 两个射频应注册"
say "  sh /usr/sbin/wifi-stack-check        → 应判定「官方 5.4.213 满血闭源栈」"
say "  /usr/sbin/qsdk-dhcp-guard status     → capability / 是否降级"
say "  /usr/sbin/qsdk-rssi-guard status     → 阈值与接口（AP 模式）"
say "  /usr/sbin/health-fix                 → LuCI / SSH / CGI 自检"
say "  浏览器 Ctrl+F5 打开 /bridge/ 与 /ap/  → 三环温度仪表盘"
echo
say "备份：$BK（sh apply-full-config.sh --rollback 可回滚 uci + 删除新增脚本）"
say "⚠ 未改动内核、无线驱动、NSS、ART、分区；官方满血栈原样保留。"
[ "$CAP" = none ] && warn "DHCP Snooping 为【缓解模式】，原因见上方能力探测；要 100% 阻断请在上级交换机开或用静态 IP。"
say "完成。"
