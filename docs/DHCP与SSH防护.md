# 无线端 DHCP 防护 / SSH / 防火墙（25.12 版）

对应老仓库：`README_SSH与DHCP防护.md`、`启用真DHCP_Snooping_需重编.sh`、
`files/usr/sbin/dhcp-guard`。老仓库那套依赖 QSDK 5.4 的 `swconfig` +
`iptables`/`ebtables`，在 25.12（DSA + nftables + NSS offload）下不能照搬，本仓换成下面这套。

## 防的是什么

不是「不让自己发 DHCP」，而是防止**无线侧有人私开 DHCP 服务器**：
WDS 对端、误接的二级路由、或无线客户端开热点共享，都会往 `br-lan` 里灌
DHCP Offer/ACK，把终端网关指到错误设备。AP 模式本机本来就不发地址
（`files.ap/etc/config/dhcp` 里 `config dhcp 'lan' option ignore '1'`），
地址由上级路由统一分配。

## 怎么拦

`files/etc/init.d/l2-guard`（START=22）调 `/usr/sbin/l2-guard apply`，
加载一张**独立**的 nft bridge 表 `nwrt_l2`：

```
table bridge nwrt_l2 {
  chain guard {
    type filter hook prerouting priority -150; policy accept;
    iifname { "wlan*", "phy*-ap*" } udp sport 67  udp dport 68  drop
    iifname { "wlan*", "phy*-ap*" } udp sport 547 udp dport 546 drop
  }
}
```

- 只匹配**无线口进入**的报文，有线侧（上级 DHCP）完全不受影响。
- 本机 WDS 主设备自己的 dnsmasq Offer 走 local-out，不匹配 `iifname`，不会被误杀。
- 只 `nft delete table bridge nwrt_l2`，**绝不 flush 全局 ruleset**。
- 配置在 `/etc/config/l2guard`：`enabled` / `wlan_pattern` / `dhcpv6` / `dryrun`。
- 串口命令：`l2-guard status` / `l2-guard off` / `l2-guard on` / `l2-guard apply`。

## 关闭防火墙

- 编译期：`config/common.seed` 注释 + `scripts/gen-config.sh` 的 FORCE_OFF 列表
  把 `firewall4` / `firewall` / `odhcpd-ipv6only` 显式写成 `is not set`。
- 运行期：`files/etc/uci-defaults/99-no-firewall` 清空 `/etc/config/firewall`、
  `stop + disable` 两个服务、删掉 `flow_offloading` / `flow_offloading_hw`
  （NSS/ECM 才是加速器，软件 offload 会抢 conntrack）。
- LuCI 不会出现「网络 → 防火墙」菜单；无 NAT、无 filter 规则。

## SSH 与 TTYD（保留）

| 项 | 包 | 端口 | 开机 |
|---|---|---|---|
| SSH | `dropbear`（`/etc/config/dropbear` 编译期写死） | 22 | enable |
| TTYD | `ttyd` + `luci-app-ttyd` | 7681 | enable |

状态页 `/bridge/` 与 `/ap/` 顶部都有 **TTYD :7681** 一键入口；
CGI 的 `protect.ssh` / `protect.ttyd` 会显示是否 enabled。

## 如实边界

1. **NSS `wifi_offload=1` 时，部分射频报文不经过 host bridge hook**，这条 nft 规则是
   尽力防护，不是硬件级 DHCP Snooping。真正的端口级 snooping 需要 QCA8337 交换芯片或
   NSS 固件支持，社区 NSS 栈目前没有把它做进 IPQ50XX 的 bridge 路径。
2. 老仓库 `启用真DHCP_Snooping_需重编.sh` 的结论在新内核下依然成立：
   想做到「真」snooping，得换数据面，不是加几个包的事。本仓选择**最稳**的折中：
   编译期不编 DHCP 服务端多余能力 + 二层拦截 + 上级 DHCP 单一可信源。
3. 若发现终端仍拿到错误地址，先 `l2-guard status` 看是否 `applied`；
   再 `nft list table bridge nwrt_l2` 看规则在不在；最后才考虑临时
   `uci set nss.general.wifi_offload=0` 验证是不是 offload 绕过了 hook。

## 状态页能看到什么

`protect.dhcp_guard`（applied / skip / off / failed）、`protect.firewall`（off 才算对）、
`protect.ssh`、`protect.ttyd`、`wifi.offload`、CPU 与射频温度，都在扩展区块里。


## PZ-L8 参考之后的重要修正（2026-11-24）

`mufeng05/openwrt-cmcc-pz-l8-nss` 实测：被 NSS 卸载的流量**根本不经过 Linux 网桥**
（一次传输里 eth0/eth1 各 989 Mbps，同一时刻 `br-lan` 只看到 52）。这意味着：

1. 本页那张 `nwrt_l2` 表的 `prerouting` hook **可能完全看不到被卸载的射频报文**。
   `l2-guard status` 显示 `applied` 只代表规则已加载，**不代表拦截生效**。
   这是尽力防护，不是硬件级 DHCP Snooping；边界比上一版写得更明确。
2. 状态页已不再用 `br-lan` 计数判断加速是否生效，改为读
   `/sys/class/net/eth0|eth1/statistics/*` + `cpu_load_ubi` + `connection_count` + `wifili`。
3. 若你必须严格阻断无线侧 rogue DHCP，最可靠的组合仍是：**本机 DHCP 服务端关**
   + **上级 DHCP 单一可信源** + 需要时临时关掉 NSS 卸载让报文回到 host bridge hook：
   仅当基线确有该配置项时 `uci set nss.general.wifi_offload=0; uci commit nss; reboot`。
4. `wifi-fullspeed` 自检现在会同时打印 eth0/eth1 计数与 NSS debugfs，
   并明确提示「br-lan 计数偏低不代表没加速」。

未变：`firewall4`/`firewall` 编译期 n、运行期 disable；只删自己那张 nft 表，
绝不 flush 全局 ruleset；SSH 与 TTYD 保留。
