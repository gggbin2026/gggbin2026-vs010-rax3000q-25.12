✅ **【第 56 次】** 修复了 Release 发布步骤的 `exit 127`：旧写法把整段 Markdown 塞进 `NOTES="..."`，里面的反引号被 bash 当成命令替换执行（编译本身早已成功、固件也已上传 artifact）。现改为独立 `.md` 文件 + `gh release create --notes-file`，说明文本不再经过 shell 解释。

🔴 **【插件基线已冻结】** 以第 51 次为准：82 项**只增不减**，少一项 `gen-config.sh` 直接 `::error::` 阻断；详见仓库 `baseline/插件基线冻结报告.html`。

🔴 **【改网桥 IP 必读】** 出厂主 `172.10.10.241` / 备 `172.10.10.242`（/22）。**改 IP 本身不会触发机器狗重启**：mode=or 有无线关联判据，且需连续不通 5 分钟；两端链路本地别名 `169.254.241.1`(主) / `.2`(备) 互 ping 与管理 IP 解耦。

> ⚠️ 但改完 IP 请执行 `bridge-watchdog resync`（自动发现对端新 IP，两台各跑一次）或 `bridge-watchdog set-peer <对端新管理IP>`，再用 `status` 复核；状态页 `/bridge/` 会显示红条。详见随附 `CHANGE-IP-NOTICE.txt`。🔴

**命名**：`Nwrt-WDS-<内核版本>-<日期>-<机型>-*.ubi / *.bin`（tag 带内核版本、后缀 `-wds`）

**模式**：WDS 网桥。WAN+LAN+2.4G+5G 全在 `br-lan`；主 `172.10.10.241` / 备 `172.10.10.242`，5G ch36 HE160 4addr，DHCP 1h；NTP：每 5 分钟循环校时一次（`ntp-poller`，开机先同步一次；`set-minutes` 可改）；机器狗默认启用：连续不通 5 分钟重启；`set-delay` 改时间、`set-peer auto` 互 ping【对端】、`resync` 改 IP 后重同步、3 次不通自动停手；`dryrun on` 可临时暂停。

**无线**：NSS FW 12.5 优先（12.2 回退）+ ECM→NSS 双射频卸载；CN / ch36 / HE160 / 本机 BDF / 256M LOW；HE160 在 CN 下覆盖 DFS，开机 5G 需约 60s CAC。

**参考**：mufeng05/openwrt-cmcc-pz-l8-nss 的 QSDK14 驱动口径（有线+双射频 949Mbps / 5G 160MHz 697Mbps / CPU 2.9%）。

⚠ 纯二层桥内被卸载的流量不经过 Linux 网桥：判速看 `eth0/eth1` + NSS debugfs，不要看 `br-lan`；WDS 4addr 在 NSS 下未验证，不通先回退。

**防护**：无线端 rogue DHCP 已拦（独立 nft bridge 表）；firewall4 编译期关闭，无 NAT / 无 filter 规则。

**精简**：只编 SSH(`dropbear`) + TTYD + LuCI 底座/中文/官方 bootstrap 主题 + 状态页，未编任何第三方 `luci-app-*`。

**界面保障**：主题下拉只列真实存在的目录；`luci-fix` 每次开机重建 named main 并清理幽灵主题，不再出现 `dispatcher.lua:427` / 主题切换后 500。

**界面**：CPU 状态新增温度（多传感器 + 配色）、TTYD 入口、NSS 加速与防护状态。

⚠ 刷前确认不死 U-Boot 支持 64 位引导；首次务必 TTL 串口验证 WDS 4addr 是否协商成功。完整说明见仓库 `MIGRATION.md` / `FIRMWARE.md`。
