# DHCP / SSH 边界

## 编译期 + 运行期双层

| 要求 | 编译期 | 运行期 |
|---|---|---|
| 无线侧 DHCP Snooping | — | `files/etc/config/l2guard` `enabled=1`；`l2-guard`(START=22) 建独立 nft bridge 表 |
| 插件只留 TTYD | `common.seed` 里 luci-app-* 只有 `luci-app-ttyd`；`verify.sh` 硬校验 | — |
| 防火墙关闭 | `firewall4` / `firewall` 显式 `is not set` | `no-firewall`(START=23) stop+disable、清空 `/etc/config/firewall`、关软/硬 flow offload |
| IPv6 关闭 | 官方基线 `CONFIG_IPV6=n` + 不编 odhcpd/odhcp6c/luci-proto-ipv6 | `sysctl.d/99-nwrt-no-ipv6.conf` + 删 WAN6 + 关 RA/DHCPv6 |
| SSH / 串口 / TTYD | dropbear + ttyd + luci-app-ttyd | `ttyMSM0 115200n8`（VS010 1.8V 电平）、TTYD :7681 |

## nft 规则

```
table bridge nwrt_l2guard {
  chain input {
    type filter hook input priority 0; policy accept;
    iifname { "wlan*", "phy*-ap*" } udp sport 67 udp dport 68 drop
    iifname { "wlan*", "phy*-ap*" } udp sport 547 udp dport 546 drop
  }
}
```

只丢**无线口**进来的 DHCPv4 Offer/ACK（67→68）与 DHCPv6（547→546）；
有线侧上级 DHCP 正常透传。`nft` 不可用时只记日志，不报错、不阻断启动。

⚠ **NSS 卸载后部分报文不过 host bridge hook，属尽力防护**。
若无线端仍拿到错地址，在上级关闭面向无线的 DHCP，或用 VLAN 隔离。
WDS 主 / 客户端两端都绝不能开本机 DHCP 服务端。

## 写入边界（沿用 5.4 老仓 STANDARDS）

- 所有状态 CGI **公开只读**，未登录能看设备全部状态；
- 修改 SSID / 密码 / 信道 / 模式只在 LuCI `admin` 树（继承 `root.sysauth`），
  字段白名单 + 后端二次校验，零裸 CGI 写入端点；
- 本仓是**单包双模式**：模式切换是唯一的写配置动作，只在 LuCI `admin` 树
  （`/cgi-bin/luci/admin/nwrt`，继承 sysauth）或 TTYD/SSH 固定枚举命令
  `nwrt-apply-mode wds|ap`；`mode` 白名单、零 eval、零参数注入面。
  状态页全只读，不提供任何保存按钮、不做裸 CGI 写入端点。
