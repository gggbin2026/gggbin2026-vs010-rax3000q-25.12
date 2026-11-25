#!/bin/bash
# 把老仓库 21.02 语法的 files/ overlay 升级到 OpenWrt 25.12（DSA + ucode + apk）
# 用法: scripts/port-overlay.sh <merged-files-dir>
# 只改【与版本绑定】的少数文件，其余 40+ 个 shell/CGI/HTML 原样保留。
set -eu
F="${1:?files dir}"; [ -d "$F/etc/config" ] || { echo "::error::不是 overlay 目录"; exit 1; }
# DSA 端口名：25.12 的 ipq50xx 常见 lan1/lan2/lan3/wan；实机以 `ip link` 为准
PORTS="${PORTS:-lan1 lan2 lan3 wan}"

echo "==================== [port-overlay] 21.02 → 25.12 ===================="

write_network() {
  local ip="$1" out="$2"
  {
    echo "# OpenWrt 25.12 DSA 写法（由 port-overlay.sh 从老 21.02 配置升级）"
    echo "# 老版 option type='bridge' + option ifname='eth0 eth1' 在 22.03+ 不被 netifd 解析"
    echo ""
    echo "config interface 'loopback'"
    echo -e "\toption device 'lo'"
    echo -e "\toption proto 'static'"
    echo -e "\toption ipaddr '127.0.0.1'"
    echo -e "\toption netmask '255.0.0.0'"
    echo ""
    echo "config globals 'globals'"
    echo -e "\toption ula_prefix ''"
    echo ""
    echo "config device 'br_lan'"
    echo -e "\toption name 'br-lan'"
    echo -e "\toption type 'bridge'"
    for p in $PORTS; do echo -e "\tlist ports '$p'"; done
    echo -e "\toption stp '1'"
    echo -e "\toption ipv6 '0'"
    echo ""
    echo "config interface 'lan'"
    echo -e "\toption device 'br-lan'"
    echo -e "\toption proto 'static'"
    echo -e "\toption ipaddr '$ip'"
    echo -e "\toption netmask '255.255.252.0'"
    echo -e "\toption force_link '1'"
    echo ""
    echo "# ── 第 48 次：网段 172.10.10.241 / 255.255.252.0（/22 = 172.10.8.0~172.10.11.255）──"
    echo "# NTP 源 172.10.10.254 就在本网段，二层直连可达，不需要任何路由。"
    echo "# 另一个源 192.168.1.254 跨网段；纯二层桥无默认网关时不可达，"
    echo "# 但 busybox ntpd 多 -p peer，一个不通会自动用另一个，不影响校时。"
    echo "# 若确实要让 192.168.1.254 也可达，取消下面注释并把 gateway 改成本网段实际网关："
    echo "# config route 'ntp192'"
    echo "#   option target '192.168.1.254/32'"
    echo "#   option gateway '172.10.10.1'"
    echo "#   option interface 'lan'"
  } > "$out"
}
write_network "${AP_IP:-172.10.10.241}" "$F/etc/config/network"
echo "  ✓ network → DSA + STP + 172.10.10.241/22（NTP 172.10.10.254 同网段直连，无需路由）"

# ── 第 47 次：统一 /etc/config/system 的 NTP（客户端，严格只用两个内网源）──
# files.<机型>/etc/config/system 会覆盖 files/etc/config/system，files.ap 又没有
# 自己的 system，所以最后在这里统一重写一遍，保证 WDS / AP / 两台机型四路一致。
SYS="$F/etc/config/system"
if [ -f "$SYS" ]; then
  awk '
    /^config timeserver/ { skip=1; next }
    skip && /^config /   { skip=0 }
    skip                 { next }
    { print }
  ' "$SYS" > "$SYS.tmp47" && mv "$SYS.tmp47" "$SYS"
  cat >> "$SYS" <<'EOF'

config timeserver 'ntp'
	option enabled '1'
	option enable_server '0'
	option use_dhcp '0'
	option poll_interval '300'    # 第 51 次：固定周期循环校时（秒；默认 300 = 5 分钟，可编译期改）
	list server '192.168.1.254'
	list server '172.10.10.254'
EOF
  grep -q "option ttylogin" "$SYS" || sed -i "/^config system/a\\	option ttylogin '0'" "$SYS"
  # 第 47 次：日志简洁 —— log buffer 64KB → 32KB（三份机型覆盖层统一）
  sed -i "s/option log_size '64'/option log_size '32'/" "$SYS" 2>/dev/null || true
  # 第 51 次：编译期可自定义周期（workflow 的 ntp_poll_minutes 经 prepare.sh 转成秒）
  NTP_POLL="${NTP_POLL:-300}"
  case "$NTP_POLL" in ''|*[!0-9]*) NTP_POLL=300 ;; esac
  [ "$NTP_POLL" -ge 30 ] && [ "$NTP_POLL" -le 86400 ] || NTP_POLL=300
  sed -i "s/option poll_interval '300'/option poll_interval '$NTP_POLL'/" "$SYS" 2>/dev/null || true
  echo "  ✓ system → NTP 客户端 192.168.1.254 / 172.10.10.254 + 每 $((NTP_POLL/60)) 分钟循环校时（${NTP_POLL}s）+ log_size 32KB"
fi

# wireless: hwmode(21.02) → band(22.03+)
for w in "$F/etc/config/wireless"; do
  [ -f "$w" ] || continue
  sed -i "s/option hwmode '11g'/option band '2g'/g; s/option hwmode '11a'/option band '5g'/g" "$w"
  sed -i "s/21\.02 用 option hwmode（11g\/11a），不是 22.03+ 的 option band。/25.12 用 option band（2g\/5g）；21.02 的 hwmode 已由本脚本升级。/" "$w" 2>/dev/null || true
  echo "  ✓ wireless: hwmode → band"
done

# uhttpd: 25.12 LuCI 走 ucode，去掉旧 lua sgi 处理器；保留 cgi_prefix（状态页要用）
if [ -f "$F/etc/config/uhttpd" ]; then
  sed -i '/lua_prefix.*sgi\/uhttpd\.lua/d' "$F/etc/config/uhttpd"
  sed -i "s/option commonname 'ImmortalWrt'/option commonname 'Nwrt'/" "$F/etc/config/uhttpd"
  echo "  ✓ uhttpd: 移除 lua sgi，保留 cgi_prefix"
fi

# luci: 编译期只保留确定存在的 bootstrap。
# 【2026-11-24 移除元凶】旧版这里无条件往 /etc/config/luci 塞
#   Footstrap 幽灵主题项，并默认 mediaurlbase=argon；
# 但 argon / footstrap 是社区主题，官方 25.12 luci feed 根本没有，
# make defconfig 静默丢包后下拉里就是两个「幽灵主题」，用户一点就 500，
# 之后 /cgi-bin/luci 再也进不去 —— 老仓库主题页报错的直接原因之一。
# 现在反过来：把幽灵项清掉，真实主题由开机 /usr/sbin/luci-fix 按
# /www/luci-static/ 里实际存在的目录动态生成。
if [ -f "$F/etc/config/luci" ]; then
  sed -i "/^[[:space:]]*option \(Argon\|Footstrap\|Material\) /d" "$F/etc/config/luci" 2>/dev/null || true
  sed -i "s#option mediaurlbase '/luci-static/argon'#option mediaurlbase '/luci-static/bootstrap'#" "$F/etc/config/luci" 2>/dev/null || true
  echo "  ✓ luci: 编译期主题列表只留 bootstrap（argon 等由 luci-fix 运行期探测）"
fi

# 通用：opkg 字样只改注释与自修脚本的 conffile 后缀，不改逻辑
# 不用「grep | while」：无匹配时 grep 返回 1，若开了 pipefail 会直接把
# 整个编译期脚本带走。改成 for + `|| true`，sh / bash 都能跑、永不误退出。
for f in $(grep -rl 'luci\.opkg' "$F" 2>/dev/null || true); do
  sed -i 's/luci\.opkg/luci.*/g' "$f" 2>/dev/null || true
done
echo "  ✓ conffile 自修路径改为通配（apk 时代不再叫 .opkg）"

# 网桥角色脚本里写死 ifname 的少数行 → device（DSA）
for s in "$F/usr/lib/bridge/role.sh" "$F/usr/sbin/bridge-role" "$F/etc/uci-defaults/99-bridge-ready"; do
  [ -f "$s" ] || continue
  sed -i "s/uci set network\.lan\.type='bridge'/uci set network.lan.device='br-lan'/g; \
          s/uci -q set network\.lan\.type='bridge'/uci -q set network.lan.device='br-lan'/g; \
          s/uci set network\.lan\.ifname='eth0 eth1'/uci set network.lan.device='br-lan'/g; \
          s/uci -q set network\.lan\.ifname='eth0 eth1'/uci -q set network.lan.device='br-lan'/g" "$s"
  # 第 47 次防呆：21.02 老兜底会删掉所有 config device 段，25.12 下 br-lan 会建不出来。
  # 源文件已改，这里再兜一层，任何残留的 delete @device 都降级为空操作。
  sed -i "s/^[[:space:]]*uci -q delete network\.@device\[0\].*$/    : # 第47次：25.12 DSA 保留 config device/" "$s"
done
echo "  ✓ bridge-role / 99-bridge-ready: ifname → device + 防呆保留 config device"

# swconfig 只读化：25.12 是 DSA，不能再 set reset/apply
for s in "$F/usr/sbin/nic-guard" "$F/usr/sbin/portstat" "$F/usr/sbin/accel-check"; do
  [ -f "$s" ] || continue
  sed -i 's/swconfig dev "$SWX" set reset 1/swconfig dev "$SWX" show || true/g; \
          s/swconfig dev "$SWX" set enable_vlan 0/true/g; \
          s/swconfig dev "$SWX" set apply 1/true/g' "$s" 2>/dev/null || true
done
echo "  ✓ swconfig 调用降级为只读探测（DSA 下不写寄存器）"

# ── 2026-11-24 第二次修订 ──────────────────────────────────────────
# 关闭防火墙：删掉编译期可能带进来的 firewall 配置，只留 l2-guard 一条二层规则
rm -f "$F/etc/config/firewall" "$F/etc/config/firewall4" 2>/dev/null || true
echo "  ✓ 清空 /etc/config/firewall（firewall4 编译期已 n）"

# 新服务开机启用：两份 99-bridge-ready（WDS 基底 / AP 覆盖层）都要加，
# 否则 sysupgrade 保留配置后 rc.d 链接不会重建。
for u in "$F/etc/uci-defaults/99-bridge-ready"; do
  [ -f "$u" ] || continue
  if ! grep -q 'l2-guard enable' "$u"; then
    cat >> "$u" <<'EOF'

# 2026-11-24：无线端 DHCP 防护 + 无线满速兜底（每次开机由 rc.d 链接拉起）
[ -x /etc/init.d/l2-guard ] && { /etc/init.d/l2-guard enable 2>/dev/null || true; }
[ -x /etc/init.d/wifi-fullspeed ] && { /etc/init.d/wifi-fullspeed enable 2>/dev/null || true; }
[ -x /etc/init.d/firewall ]  && /etc/init.d/firewall disable 2>/dev/null || true
[ -x /etc/init.d/firewall4 ] && /etc/init.d/firewall4 disable 2>/dev/null || true
EOF
  fi
done
echo "  ✓ l2-guard / wifi-fullspeed 已写入开机启用链（含 AP 覆盖层）"

# AP 弱信号剔除默认停用：避免「信号好」的终端被误踢（最稳、最少系统问题）
G="$F/etc/config/ap-rssi-guard"
if [ -f "$G" ]; then
  sed -i "s/option enabled '1'/option enabled '0'/; s/option dryrun '0'/option dryrun '1'/" "$G"
  echo "  ✓ ap-rssi-guard 默认停用（dryrun），防误踢；需要时 uci set 后重启"
fi

# uhttpd 保留 cgi_prefix，ttyd 自己监听 7681（状态页加链接即可，不做反代）
echo "[port-overlay] ✓ 完成。实机端口名若不是 '$PORTS'，用 PORTS=... 重跑本脚本。"
