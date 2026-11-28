# 固件验收标准（r25 起，每版必须遵守）

> 用户原话：「编译出来的固件一定要运行稳定，内存占用低，无线开启快，
> 即精简好用没有 BUG 的固件（以后都要按此标准修复），固件要保证能用 SSH 及串口等」。

这不是愿望清单，是**硬验收项**。`sourcebuild/tools/verify.sh` 与
`sourcebuild/diy-part2.sh` 每版逐条断言，缺任何一条直接 FAIL、不出包。

## 一、稳定（最高优先级，压倒一切新功能）

| # | 标准 | 落实 |
|---|---|---|
| 1 | 官方/实机验证过的东西绝不为了「更漂亮」去改 | switch `ar8327-initvals` 默认保留已验证档；U-Boot 本体不动；BDF 容器头沿用 kkstone 已验证 84 B |
| 2 | 配置每次开机幂等重写，重置后能长回来 | `vs010-mode` 的 `scrub()` 不受 applied stamp 限制 |
| 3 | 删服务不删依赖链 | 只删配置/自启链接/控制器，不动 `libuci`/`uhttpd`/闭源 `.ko` |
| 4 | 🔴 `bootargs-append` 不可删 | U-Boot env 实测只给 `console=ttyMSM0,115200n8`；`ubi.mtd=rootfs swiotlb=1` 必须来自内核 DTS，删了挂载不上 rootfs |
| 5 | 不重建 radio / 不 `wifi down` / 不重启机器 | 只改既有 `wifi-device`/`wifi-iface` 的 option |
| 6 | 一台机器一个常驻 | 仅 `vs010-tick`；机器狗出厂停用、DHCP guard 默认 monitor |
| 7 | 双线不再互相覆盖 | r26 全能包本身即单线（新增可切模式 + 设置面板）：只留 `build-source.yml`，无融合线残留，清空仓库解压即用 |

## 二、内存占用低

- `.config` 关闭 `autocore-arm` 等纯装饰/杂项包；`luci-app-firewall`、`bootstrap`、
  `odhcpd-ipv6only`、`dnsmasq` 冗余特性、`autoreboot` 全关
- **单常驻 `vs010-tick`** 合并 NTP / Snooping / WDS / 机器狗分频，不再一个功能一个 daemon
- `vs010-wds-pair loop` 开机延迟 `35s → 5s`、轮询 `60s → 120s`，少占 CPU
- 不启动 = 不占内存；不为了省几 MB flash 去删二进制冒破坏闭源依赖的风险

## 三、无线开启快

- 去掉开机 `sleep 15` 后台重试收敛，改成同步一次 `converge`
- 5G 单 VAP 收敛（`WDS-Bridge-Z`），同 radio 其余 VAP `disabled=1` 而非删段
- 信道 `auto`（ACS）是用户明确要求，保留；HE160 与 4addr 以实机 `wlanconfig ath1 list` 为准

## 四、精简好用、没有 BUG

- 网桥固件**只有** `/bridge/`，AP 固件**只有** `/ap/`，互不混装（`files.manifest` + `mode-exclude.*` 物理排除）
- Argon **2.4.3**（最后一个 Lua 兼容 tag），内置状态菜单
- 网桥/AP 界面的网卡信息必须显示**链接速率**（netdev 不上报时读交换芯片 PHY 实测并标注来源）
- 网桥/AP 界面必须显示**无线芯片温度**；无传感器时如实留白「—（无温度传感器）」，**绝不报错、绝不写假数值**
- 只列已插网线的口（carrier / operstate / ethtool 三重判定）
- 登录 `root / admin`，IP `172.10.10.241/22`（WDS 主 `.241`、客户端 `.242`、AP 恒 `.241`）

## 五、🔴 管理通道必须可用（每版硬断言）

| 通道 | 编译期 | 运行期 |
|---|---|---|
| SSH | `CONFIG_PACKAGE_dropbear=y` | `PasswordAuth=on` / `RootPasswordAuth=on`，不绑 Interface |
| 串口 | — | `ttyMSM0::askfirst:/bin/ash --login`，115200n8，TTL **1.8V** |
| TTYD | `CONFIG_PACKAGE_ttyd=y` + `luci-app-ttyd=y` | `/ttyd/` |
| LuCI | `uhttpd` + `luci-base` | `/cgi-bin/luci` |

## 六、网络与无线角色

- WAN / WAN6 删除、IPv6 全关、防火墙服务关、DHCP 服务端全关
- 🔴 <u>**WDS 主 / 客户端两端都绝不能开 DHCP 服务端**</u>：日志、下载页、网桥页标红划线
- **网桥模式只用 5G**：5G HE160 / `channel=auto` / `WDS-Bridge-Z`，**2.4G radio `disabled=1`**
- **AP 模式 2.4G 作为 AP 用**：`VS010-AP` / `RAX3000Q-AP`，密码 `AP123456`，5G 同时作为 AP
- MU-MIMO / WMM / 弱信号剔除与拒绝连接，两种模式都有

## 七、实机参数来源

- 全部 GPIO / LED / bootargs / MIBIB / BDF / U-Boot / CDT 参数来自
  `reference/vs010-oem/VS010-实机参数.log`，**实机读取、✅ 可直接使用**，不是推断
- 原始二进制在 `reference/vs010-oem/`（`MANIFEST.json` 带 sha256）
- `0:ART` / `0:APPSBLENV` 含本机 MAC，公开仓库建议脱敏

## 八、效率约定（回应用户「别老重复跑」）

- **不重复拉取远端**：素材已本地落库，后续版本直接复用，不重新 `git clone`、不重新下载上游
- **不重复解包**：`parse-vs010-backup.py` 校验 tar.gz sha256，命中
  `reference/backup/VS010-备份解析.json` 的 `source_sha256` 就直接复用
- 自检只读本地文件；`make` 只在用户显式 `Run workflow` 时跑一次
- 新增版本只做增量修改，不整树重出

## 九、边界（如实说明，不许包装成确定结论）

- 没实机、没跑 GitHub Actions 的 `make` 时，只交静态/注入/自检真跑结果
- `iw dev` 双频接口、HE160、4addr 以刷完实机为准
- 010 按键 GPIO 改的是内核 DTS；U-Boot 单槽（`APPSBL_1` 全 FF），救砖 TTL 在手边

---

## 九、配置入口与工作模式（r26 起，每版强制）

| 项 | 硬要求 |
|---|---|
| **写入必须鉴权** | 所有能改 SSID / 密码 / 角色 / 信道 / 模式的端点**只在 LuCI admin 树下**（继承 `root.sysauth`）；未登录自动 302 到登录页，`save()` 再做一次会话核实 + 403。**零裸 CGI 写入端点** |
| **直接输网址** | 状态页只读可见；配置面板探测到未登录就**锁定保存**并显示登录入口。从主题菜单进入时已登录，可直接操作 |
| **联动唯一入口** | `/usr/sbin/vs010-apply-config`：字段白名单 → 校验 → 原子写 `/etc/vs010/user.cfg`(600) → uci wireless → **一次** `/sbin/wifi reload` |
| **重启不丢** | `vs010-mode` / `vs010-wds-pair` 每次开机重读 `user.cfg`；空字段保持原值，不覆盖用户其它设置 |
| **不重建 radio** | 只改既有 `wifi-iface` 的 option 与 `disabled`；绝不 `wifi down`、绝不新增常驻进程、绝不重启机器 |
| **模式可切换** | `AP ⇄ WDS 桥接` 在面板里选；写 overlay 的 `/etc/vs010/mode` + 清 stamp + 重跑首启配置。两套界面都注入，但**菜单只注册当前模式一套**，两页各带 mode 守卫（不符只显示提示，不渲染另一套）——不串界面 |
| **WDS 主/客** | 左右滑动开关：左 `WDS-Z .241`、右 `WDS-K .242`；客户端可填主端 SSID / 密码 / BSSID 定向桥接 |
| **WiFi 参数** | 5G / 2.4G 信道（`auto` = QSDK ACS）、SSID 信号剔除值 `-100…-30 dBm`、最低连接保持时间 `1–60 s`，两种模式都联动落 `db_rssi_thr` / `db_timeout` |
| 🔴 DHCP | WDS 主 / 客两端都绝不能开 DHCP 服务端；面板、日志、下载页继续标红划线 |

---

## 十、一机型一包 · 双模式 · 界面即控制台（r27 起，每版强制）

| 项 | 硬要求 |
|---|---|
| **产物** | `matrix` 只按 `device` 展开：**VS010 1 个 + 3000Q 1 个，共 2 个固件**。禁止再按 `mode` 编 WDS/AP 两份。固件名带 `YYYYMMDD-HHMM` 与 `-dual` |
| **首启默认** | `default_mode`（默认 `wds`）只写 squashfs 里的 `/etc/vs010/mode`；切模式写 overlay，重启不丢，刷机不勾「保留配置」则回到默认 |
| **模式切换闭环** | 写 mode → 清 `applied` stamp → 重跑首启配置 → **清 `/tmp|/var/luci-indexcache*` + `modulecache` → `uhttpd reload`**（菜单按 `cur_mode()` 重建）→ 前端 2 秒自动跳到 `/bridge/` 或 `/ap/`。缺任一步菜单都不会自动换 |
| **不串界面** | 两套页面都注入；菜单只注册当前模式一套；设置面板带 mode 守卫；**整页** mode 不符时提示并自动跳到对应界面 |
| **常用设置全在页面** | 模式 / WDS 主客 / 桥接目标 / AP 双频独立 SSID 密码 / 5G·2.4G 信道 / 频宽 / 功率 / WMM / MU-MIMO / 弱信号剔除值 / 最低连接值 / 管理 IP·掩码 / 设备名 / STP / NTP / 主题 / 自检·机器狗·Snooping·日志 |
| **留给 LuCI** | 改 root 登录密码（开机脚本会归一为出厂值，页面改会打架）、固件升级、VLAN/静态路由、opkg 装包 —— 页面顶部常驻「🔧 LuCI 高级设置」入口 |
| **安全红线** | 写入与维护端点只在 LuCI `admin` 树（sysauth）；字段白名单 + 后端二次校验；维护动作是**固定命令枚举、零参数**；`user.cfg` 600；**禁止 eval 写值**（SSID 含空格/括号不得被当命令执行）；不提供「开启 DHCP 服务端」按钮 |
| **稳定红线** | 不新增常驻进程、不重建 radio、不 `wifi down`、不重启机器；一次 `wifi reload`；开机脚本重读 `user.cfg` 全字段 |

---

## 十一、界面布局与入口（r28 起，每版强制）

| 项 | 硬要求 |
|---|---|
| **两页排序一致** | 前 3 块必须完全相同：`系统仪表盘 · GAUGE` → `常用设置控制台 · SETUP` → `网络与本机 · NETWORK`。之后才是网桥（WDS/守护·RF·诊断·加速）或 AP（射频·终端·弱信号·BDF·加速）各自的业务显示。自检用 h2 顺序硬断言 |
| **GAUGE 置顶、只留仪表盘** | 三个环形仪表（CPU / 内存 / CPU 温度）+ 运行徽标 + **无线芯片温度**；详细数值微卡与 CPU/内存文字卡片**不显示**（DOM 隐藏/移除均可，但 JS 必须零空引用，删 DOM 就要 guard） |
| **网口命名** | 按实际物理网口顺序显示 `内网LAN1` / `内网LAN2`…（CGI 输出 `lan` 字段；`br-lan` 是二层桥，不占号）。表头 `内网 LAN`，**不要再出现旧的「已插网线 / 连接端口」独立卡片** |
| **速率显示** | `1000 → 1G`、`2500 → 2.5G`、`100 → 100M`、`10 → 10M`、读不到 `—`；必须标注 PHY 实测来源。`node` 真跑断言 `—\|10M\|100M\|1G\|2.5G` |
| **NETWORK 整合** | 网络三卡在前、内网 LAN 表在后，两页同序；AP 页的 LAN 表也从独立区块移进 NETWORK |
| **默认与跳转** | 刷完默认 **网桥**（`default_mode=wds` 写进 squashfs 的 `/etc/vs010/mode`）；新增 `www/index.html`，只输管理 IP 自动跳当前模式界面，CGI 不通 3 秒兜底 `/bridge/` |
| **只读 / 写入分离** | 所有状态 CGI 保持公开只读（未登录能看设备全部状态）；写入与维护端点只在 LuCI `admin` 树（未登录 302 / 403），面板显示「保存与维护已锁定」并引导登录 |
| **右上角开关** | 两页 header 右上角固定「⚙ 高级设置后台」→ `/cgi-bin/luci/`，窄屏回落流式；命名不许再写成 LuCI |
| **日志中注明直达路径** | CHANGELOG、Release 发布日志、使用说明、根跳转页、SETUP 维护区、界面「查看日志 / 一键自检」输出首行、后端 `ACTS.log` 输出末尾，**全部写明** `http://<设备IP>/cgi-bin/luci/`（默认 `172.10.10.241`；`/cgi-bin/luci` 同效），并提示根路径 `/` 已改为状态页跳转、不再直达 LuCI。后端提示必须是固定串、零参数；README 只保留一行可复制入口，不堆修复记录（r29.3） |
| **对比度** | 深色主题里，SETUP 白底卡片的 h3 / label / 滑块文字必须强制深色，避免被页面浅色规则盖成不可读 |

---

## 十二、深度核验红线（r28 起，每版强制）

| 风险 | 硬护栏 |
|---|---|
| **LuCI 后台打不开** | 所有 `*.lua` 必须过 `tools/luacheck.py`（纯标准库词法：字符串内裸换行、未闭合、括号配对）。`jesc()` 这类把真实换行写进字符串字面量的错误，Lua 会直接 `unfinished string` → controller require 失败 → 整个后台 500、probe/save 全挂。禁止只靠 grep 断言 |
| **根路径不跳转** | `vs010-luci-fix` 必须显式 `uci set uhttpd.main.index_page=index.html`。`luci-base` postinst 会把它设成 `cgi-bin/luci`，不覆盖则 `/www/index.html` 永不返回。`/cgi-bin/luci/` 是显式路径，不受影响 |
| **无线起不来** | 本源码线 `.config` 是 `kmod-ath11k + mac80211 + wpad-wolfssl`，但无线脚本沿用 QSDK `qcawifi.sh` 约定（`hwmode=11axa` + `htmode=HT160` 表示 HE160，`vs010-wds-pair` 已验证）。**频宽白名单只放行 `HT160/HT80/HT40`**，禁止把 `HE160/HE80/VHT80` 暴露到界面；`apply_radio()` 对非法残留值必须跳过而不是写入 radio |
| **LAN 名错标** | `vs010-links` 的 `lan` 字段按**物理口固定映射**（`eth0\|lan1 → 内网LAN1` …），不得按「第几个已插线的口」递增；`br-lan` 是二层桥，必须 `continue` 不进表格 |
| **编译链断点** | `verify.sh` 每版跑：workflow 关键项、所有 `run:` 块 `bash -n`、`files.manifest` 每个文件存在、全部 `.lua`/`.sh`/CGI/内联 JS 语法检查 |
| **网页打不开** | 演示站点用真实 HTTP + Chromium 断言：根跳转、两页首个 h2、3 环表、7 分组、右上角按钮、内网LAN1·1G、零 JS 错误；再注入未登录态断言「状态可见 + 保存禁用」 |

---

## 十三、界面文案与视觉基线（r29 起）

- 端口块统称 **「网口状态 / 网口信息」**（`网口状态 · PORT STATUS`），不再叫「网口速率」；「链接速率」只是其中一列，必须保留；1000M 统一显示 `1G`。
- 所有**状态栏、选项卡、徽章、按钮、输入项、滑块**统一 `border-radius:999px`（两端圆弧/胶囊）。大卡片与多行日志输出块保持原圆角，不做全页胶囊化。
- 页面自身 CSS 必须用 `!important` 压住 `vs010-setup.js` 运行时注入的 `<style>`；`vs010-setup.js` 自身也要同步改，保证主题内单独打开设置页一致。
- 每版自检必须断言：两页 6 列表头、状态栏存在、椭圆规则在位、旧标题不残留、setup.js 圆角数 ≥9、LuCI 菜单名统一。


---

## 十四、双向导航基线（r29.2 起）

- **必须双向**：状态页右上角「⚙ 高级设置后台」→ `/cgi-bin/luci/`；LuCI 侧必须有**一级 leaf 菜单**「← 返回网桥/AP 状态」（`{"admin","vs010_home"}` + `call("go_home")`），按 `/etc/vs010/mode` 302 到 `/ap/` 或 `/bridge/`，保证从后台任意页面可回。
- 每个 `vs010_*.htm` 模板顶部必须有 `border-radius:999px` 胶囊返回按钮；独立状态页直链、根跳转页 `/` 按模式自动跳，三者并存。
- LuCI 内嵌 iframe 页保留「也可单独打开」直链；菜单/链接文案与 r29「网口状态」保持一致，禁止引用源码线不存在的命令（如 `vs010-theme`）。
- 每版自检断言：一级菜单与 `go_home()`、6 个模板返回按钮、旧「网口速率」零残留。


## 十五、编译期协议精简基线（r29.4 起）

- **不能只靠运行期关**：`.config.*` 里 `ppp` / `ppp-mod-pppoe` / `kmod-ppp*` / `kmod-pptp` / `luci-proto-ppp` / `kmod-qca-nss-drv-pppoe` / `ipv6helper` / `luci-proto-ipv6` / `odhcp6c` / `6in4` 必须 `is not set`；`firewall` / `ip6tables` / `libip6tc` / `kmod-*6` 尽力关闭。
- **必须连 `target/linux` 的 `DEFAULT_PACKAGES` 一起摘**，否则 `make defconfig` 会把 `CONFIG_DEFAULT_ppp=y` 重新拉回 `CONFIG_PACKAGE_ppp=y`。流程固定：`cp .config → diy-part2(strip) → make defconfig → check-no-protocols.py → make download`。校验发现 MUST_OFF 被拉回直接 `::error::` 拒绝出包。
- **内核 `CONFIG_KERNEL_IPV6=y` / `CONFIG_IPV6=y` 保留**：QSDK 12.2 / NSS 驱动有编译期依赖，删符号会破坏无线与网口加速；实际网络层由 `net.ipv6.conf.*.disable_ipv6=1` + `accept_ra=0` + `autoconf=0` + 运行期 `kill_ipv6()`（删 WAN6、`dhcp.lan.{ra,dhcpv6,ndp}=off`、停 odhcpd）关死，**无 v6 地址、无路由、无协议页面**。
- IPv4 侧 `iptables` 保留（诊断命令与 NSS 依赖需要）；`rpcd-mod-rrdns` / `firewall` 不编入。**r29.7 修正**：`dnsmasq-full` 因 AP 界面要可选 DHCP 服务端而编回，但默认 `dhcp.lan.ignore=1` + init `disable`，**不开时零常驻、不占运行内存**；`kill_dhcp()` 每次开机重读 `user.cfg`，WDS 模式硬禁止开启。
- 每版自检：两份 `.config` 黑名单零 `=y`、`CONFIG_DEFAULT_*` 零 `=y`、两个工具在位、调用顺序正确、负例被拦。


## 十六、极致精简与加速护栏（r29.5 起）

- **协议/插件越少越好**，但有一条硬边界：`MUST_KEEP` 清单（见 `tools/check-no-protocols.py`）里 **NSS 全链路 + LuCI 后台核心 + SSH/串口/TTYD + opkg + ethtool/swconfig** 缺任意一项 → `::error::` 拒绝出包。理由：删了加速包或 `luci-mod-*` 会直接撞「网口速率正常、后台不报错、能自己加插件」三条底线。
- **DNS 编译期移除**：`dnsmasq-full` / `dnsmasq` / `rpcd-mod-rrdns` 不编入；NTP 服务器本就是纯 IP（`172.10.10.254` 等），不依赖本机 DNS。CGI 里读 `/etc/resolv.conf` 的字段在无文件时返回空值，不报错、不伪造 DNS。
- **WAN 编译期删除**：`diy-part2 → strip-protocols.sh` 往源码树 `package/base-files/files/etc/uci-defaults/99-vs010-no-wan` 追加脚本，在 `board.d/02_network` 之后删 `network.wan` / `wan6` / `dhcp.wan6`、清 ULA。**只动 UCI，绝不改 switch/GMAC 寄存器**（改错网口全灭）；运行期 `scrub()` 每次开机再兜底。WAN 物理口仍桥进 `br-lan`。
- **内核保守裁剪**：`tools/slim-kernel.sh` 用**白名单式黑名单**，只关组播路由/PIM/SCTP/DCCP/GRE/IPIP/VLAN/命名空间/IPv6 多表与 Seg6；绝不碰 `CONFIG_IPV6`（QSDK/NSS 编译依赖）、`CONFIG_BRIDGE`/`STP`（防环）、`CONFIG_NF_*`/`NETFILTER`（NSS 依赖）、`MAC80211`/`ATH11K`。符号被 Kconfig 拉回只给 notice，不阻断编译。
- **加速一律保留**：`kmod-qca-nss-dp` / `nss-drv` / `nss-ecm-standard` / `wifi-meshmgr` / `qca-ssdk-nohnat` / `qca-nss-fw-ipq50xx-retail` / `MAC80211_NSS_SUPPORT` / `luci-app-turboacc`。`ppp` 类拨号加速模块已随 PPP 一起删（纯桥用不到）。
- **响应速度**：单常驻 `vs010-tick`；`autocore-arm` 关；`block-mount` / `luci-app-filetransfer` / 科学上网类空壳 `INCLUDE_*` 配置选项清零。`opkg` 必须保留（用户要自行加插件）。
- 每版自检：两份 `.config` DNS 零 `=y`、MUST_KEEP 全在位、内核黑名单无危险符号、源码树真跑生成 uci-defaults 且不误伤依赖符号、两个负例（删 ECM / DNS 回流）被拦。


## 十七、VS010 编译链护栏（r29.6 起，硬性）

- **每版必须自检 `ipq5000-vs010.dts` 花括号配对**：DTS 多/少一个 `};` 会让 dtc 在镜像打包阶段失败，表现是「编译跑了 1 小时才 exit 2」，且只有 VS010 挂、3000Q 正常。`verify.sh` 与 `preflight-vs010.sh` 双重断言，负例必须被拦。
- **`DEVICE_PACKAGES` 只放真实包名**：绝不放 `ATH11K_MEM_PROFILE_256M` 一类的 `.config` 符号（它靠 `DTS_CPPFLAGS-$(CONFIG_...)` 生效）。Device 定义与 `cmcc_rax3000q` 保持逐行对齐，只允许 vendor/model/`ipq-wifi-*` 不同。
- **注入后必须跑 `tools/preflight-vs010.sh`**：`diy-part1.sh` 与 `inject-vs010.py` 双入口调用。检查项：Device 包列表、TARGET_DEVICES 顺序、DTS 配对 + cpp 预处理 + dtc 真编译、ipq-wifi 注册与 BDF 84+131072 字节格式、board.d 不粘连且全 LAN、GNU make 真解析生成 `Package/ipq-wifi-cucc_vs010`。
- **`Compile the firmware` 必须留可定位的失败日志**：`tee /tmp/vs010-build.log`；三轮重试全失败时输出「错误行最后 100 条 + 日志最后 120 行」并 `::error::`。禁止只留 `make -j || make -j1 || make -j1 V=s` 导致页面截断后只剩 `exit code 2`。
- `Node.js 20 is deprecated` 是 GitHub runner 的 warning，与编译失败无关，不要当错误处理。
- `board.d` 的 VS010 case 全 LAN（`1:lan:4`），与 `99-vs010-no-wan` 一致；`generate-ipq-wifi-package` 标题不含括号。


## 十八、AP 可选 DHCP 与时间显示（r29.7 起）

- **AP 界面「⑥ DHCP 服务 · ADDRESS POOL」**：滑动开关（关闭交上级 / 开启本机发地址）+ 地址池起始 IP + 地址数量 1–253 + 租期（1m…24h 或 60–604800 秒）。两页共用 `vs010-setup.js`，分组顺序 ①…⑧ 完全一致，仅「相关设置」不同。
- **网桥模式硬禁止**：前端按当前模式 `disabled` 掉整组输入并给锁定提示；后端 `vs010-apply-config` 与开机 `kill_dhcp()` 双重强制 `dhcp.lan.ignore=1`，即使用户从 WDS 页提交 `dhcp_enabled=1` 也会被关掉。内网始终只允许一台 DHCP。
- **联动链**：面板 → 受 LuCI `admin` 树 sysauth 保护的 `/save` → 字段白名单与校验 → 原子写 `/etc/vs010/user.cfg`(600) → `uci dhcp.lan.{ignore,start,limit,leasetime}` → `dnsmasq` enable/restart（或 stop/disable）；开机 `scrub()` → `kill_dhcp()` 重读 `user.cfg` 恢复，**重启不丢、不新增常驻进程**。
- **编译期**：`CONFIG_PACKAGE_dnsmasq-full=y` + `dnsmasq_full_dhcp=y` 必须在位（`check-no-protocols.py` 的 MUST_KEEP）；`strip-protocols.sh` 不再剥离它。默认 `ignore=1` + disable，符合「低内存」。DNS 转发仍不启用，NTP 三台服务器本来就是纯 IP。
- **两页 GAUGE 内置顶椭圆徽章**：`时间 <本地时间>（未校时）` + `运行 <N天 HH:MM:SS>`，数据来自各自 CGI 已有的 `time` / `uptime` 字段；不复活 r28 删掉的详细信息卡片。未登录仍只读可见。
- **3000Q 6.4 移植基线**：`reference/rax3000q-6.4-baseline/` 固定归档「编译成功那版」的 DTS / BDF / ART / `.config` / Device / board.d / ipq-wifi Makefile / U-Boot，附 `MANIFEST.json`（sha256）与 `README-6.4移植基线.md`。**二进制板级资产可复用，QSDK 5.4 源码/驱动/NSS 必须重做**，说明里写清边界，避免把 21.02 源码树直接升 6.4。
- 每版自检：4 个 DHCP 字段全链路、分组顺序、WDS 锁定、开机重读、dnsmasq MUST_KEEP、两页时间徽章、基线 MANIFEST 逐字节、脚本语法、负例。


## 十九、UBNT 风格概览页与双机型 6.4 基线（r29.8 起）

- **`/ubnt/` 起初是第三入口**：r29.9 用户确认「三个界面都要 UBNT 风格」后，采用共享皮肤方案把 `/bridge/` 与 `/ap/` 视觉整体换成 UBNT，**不推倒重写两页**（GAUGE 时间徽章、模式守卫、共用控制台、几百行 JS 全部保留）。r29.10 用户进一步确认要「替换 + 全互访 + 能登录」，见第二十一节。
- **零写入**：UBNT 页只 GET `/cgi-bin/vs010`、`bridge`/`apstatus`（按模式二选一）、`vs010-links`；**绝不**调用 `vs010_setup/save|act`。设置容器由 `../vs010-setup.js` 自行鉴权，`data-mode="auto"` 不触发跳转。
- **响应式是硬要求**：宽屏 ≥900px 左侧 224px 深色栏；<900px 折叠成顶部横向 pill，外部导航组隐藏但主导航补「高级后台」入口。用户主要在手机上看，竖屏不得出现侧栏挤压主区。
- **离线预览**：`location.protocol==='file:'` 或 `?demo=1` 自动用内嵌 mock，不 fetch、不加载 setup.js，`demo/` 里同时存页面与两种尺寸截图。
- **双机型 6.4 基线**：`reference/rax3000q-6.4-baseline/` 与 `reference/vs010-6.4-baseline/` 成对存在，各自 `MANIFEST.json`（sha256）+ `README-6.4移植基线.md`。VS010 基线额外含实机 `vs010.dtb`、反编译 DTS、OEM `0-*` 分区、board-id 变体 BDF、switch OEM 档、注入脚本。**基线里只能放 r29.6 修正版 DTS（59/59 配对）**，自检会拦花括号不配对。
- 说明必须写清四条边界：二进制板级资产可复用 / QSDK 5.4 源码与 NSS 闭源驱动必须重做 / VS010 与 3000Q 的 GPIO·switch·分区差异 / 建议另起 6.4 仓库。ART、`0-*`、flash 备份含本机 MAC，公开仓库建议脱敏。


## 二十、三界面同款 UBNT 皮肤（r29.9 起）

用户确认「三个界面都要」= **`/ubnt/` / `/bridge/` / `/ap/` 三入口共存，且都要 UBNT 风格**，不是二选一替换。

- **共享两份资源**：`www/vs010-ubnt.css`（只定义 `u-*` 与 `body.ubnt-body`，**绝不覆盖两页任何原有选择器**）、`www/vs010-ubnt-skin.js`（head 同步加载，先于页面内联脚本完成 fetch hook）。
- **零侵入硬约束**：两页 HTML **只加 2 行**（link + script）。注入器在 `DOMContentLoaded` 把 body 非 script 子节点整体搬进 `.u-content`，**不删、不重命名、不改写任何原有节点与 id**，只在外面套侧栏 + 顶栏 KPI。两页几百行 JS 的 `getElementById` 全部照常命中；`script` 节点留在原位，不会重新执行。
- **数据零额外请求**：hook 原生 `window.fetch`，只接 `cgi-bin/bridge` / `cgi-bin/apstatus`，用 `Response.clone().json()` 读一份，原页面 `.then(r=>r.json())` 完全不受影响。**不接 `vs010-links`**（它没有 time/uptime/sys，会冲掉 KPI），且 paint 里空值不覆盖已有值。
- **配色统一深色**：两页原本就是 `--bg:#0e1520` / `#0a1120`，`/ubnt/` 从 r29.8 的浅色同步切到深色，三页一致，不半深半浅。硬编码浅底改 `var(--soft)`，红字改 `#ff7b7b` 保证深底可读。
- **响应式不变**：≥900px 左侧 220px 深色栏（sticky）；<900px 折叠顶部横向 pill，外部导航组隐藏但主导航保留「高级后台」。
- **导航五入口互通**：概览 / 网桥状态 / AP 状态 / 常用设置 / 高级设置后台，当前页高亮。模式守卫 `data-mode` 不变，手动输错网址仍 2 秒自动跳到对应界面。
- **顺带修口径回归**：两页 HTML 里 r28 写死的「本机 WDS 与 AP 均已关闭」红字与 r29.7「AP 可开 DHCP / WDS 硬禁」冲突，统一改成新口径并纳入自检，防止回归。
- 自检覆盖：三页资源注册、两页恰好 2 行新增、原有 id 全在、CSS 零覆盖、clone hook、零写入、三入口导航、深色统一、静态文案、JS 语法、6 张真渲染截图。


## 二十一、四界面全互访与登录贯通（r29.10 起）

用户明确要求：**UBNT 界面正式替换 AP / 网桥界面；所有界面与 OpenWrt（LuCI）界面能互相点开；都要有按钮；都要能登录。**

- **「替换」的落地口径**：`/bridge/` 与 `/ap/` 已是 UBNT 深色界面（共享皮肤外层包裹），但**不推倒重写**——重写会打断已验证的 GAUGE 数据源、模式守卫、DHCP 控制台、网口 6 列等。视觉替换 + 功能全留，是风险最低的等价替换。
- **四类界面、同一排按钮**：`/bridge/`、`/ap/`（由 `vs010-ubnt-skin.js` 动态生成 `.u-jump`）、`/ubnt/`（`.jumpbar`）、根跳转 `/`（`.nav`）、LuCI 六个 `vs010_*.htm` 视图（`.vs010Nav`），**每页都有 6 个入口**：`/ubnt/` 概览、`/bridge/` 网桥状态、`/ap/` AP 状态、`/cgi-bin/luci/admin/status/vs010_setup` 常用设置、`/cgi-bin/luci/` OpenWrt·LuCI、登录/退出。
- **登录态必须真实可用**：未登录显示「🔑 登录 LuCI」→ `/cgi-bin/luci/`（LuCI 登录页）；已登录显示「🔑 已登录 · 退出」→ `/cgi-bin/luci/admin/logout`。会话判定统一走 `vs010_setup/probe`（只读 GET，`{"ok":1}` 即已登录），与 `vs010-setup.js` 的 `AUTH` 同源，不会出现「显示已登录但保存被拒」。
- **两页零新增请求**：注入器在原有 fetch hook 上加一个 `vs010_setup/probe` 分支，用 `Response.clone().json()` 读 `ok`，**复用共用控制台本来就发的那次 probe**；主 CGI 的 `cgi-bin/(bridge|apstatus)` 分支与 `空值不覆盖` 逻辑不动。
- **竖屏硬要求**：互访条 `overflow-x:auto` 横向滚动，**绝不 `display:none`**；手机上也必须能点到全部 6 个入口（顶栏另有登录按钮兜底）。
- **LuCI 侧**：六个视图保留原有 `class="vs010Back"` 胶囊返回按钮与 `border-radius:999px`，新增按钮条只是叠加；`vs010_setup.htm` 的 `data-mode="auto"` 与面板本体不动。LuCI 视图本身在 `admin` 树下，能打开即已登录，故固定给「退出」按钮。控制器一级菜单 `vs010_home` 的 302 回跳保留。
- **零写入红线不变**：注入器里**绝不出现** `vs010_setup/save|act`、`/save`、`/act`；登录/退出只是 GET 跳转。未登录时状态页只读、设置容器仍由受 sysauth 保护的 `vs010-setup.js` 锁定。
- 自检覆盖：四类界面逐页验 6 个入口、登录态 hook、退出链接、两页仍恰好 2 行引入、CSS 零覆盖、LuCI 原返回按钮、Lua 词法、三页 + 根页内联 JS、6 张真渲染截图。


## 二十二、WDS 客户端搜索周边主端与频段跟随（r29.11 起）

用户要：网桥界面作为客户端时，点一下搜索列出一堆 SSID，点选后填密码，并**自动关联 WDS 组的频段**。

- **只读扫描端点**：`/cgi-bin/luci/admin/status/vs010_setup/scan` 挂在 `admin` 树下继承 `sysauth`（未登录 403）。**零 HTTP 参数**：接口由 `/usr/sbin/vs010-scan` 自己按 `ath1/wifi1/wlan1/ath0/wifi0` 顺序探测，命令串写死，不接受 `iface`/`cmd` 之类输入 → 无命令注入面。
- **扫描脚本纯只读**：只做一次主动扫描（`timeout 8 iw dev <iface> scan`，兜底 `wlanconfig list scan`），**不写 UCI、不 reload、不重启**。输出 JSON：`ssid/bssid/freq/channel/band/signal/enc`。隐藏 SSID 过滤；SSID 含空格/括号由 awk 内 `jstr` 转义；`wlanconfig` 兜底结果带 `approx:1` 并标注「估算」，不伪装精确；无工具/无接口/超时一律返回 `ok:0` + 明确 msg，**绝不伪造 SSID**。
- **前端联动（共用 `vs010-setup.js`，三页与 LuCI 设置页同时生效）**：② WDS 分组内加搜索按钮 + 结果表（按信号排序）。点「选用」→ 自动填 `peer_ssid` / `peer_bssid`，把 `ch5g`（2.4G 则 `ch24g`）设成扫描到的信道，若当前是主端则**自动切到 WDS 客户端**并在提示里明说，最后聚焦 `peer_key` 让用户手填密码。未登录时按钮 `disabled`、点击给登录引导。
- **后台闭环（无需新字段）**：`ch5g` / `peer_ssid` / `peer_key` / `peer_bssid` 本来就在 `apply-config` 白名单与 `user.cfg` 里；`vs010-wds-pair` 的 `resolve_wds()` 读 `ch5g` → `uci set wireless.$d.channel=$WDS_CH`，读 `peer_bssid` → `wireless.$primary.bssid`。**WDS 主客必须同信道才能建 4addr 桥**，所以「跟随频段」不是显示效果，是真正落到 5G radio 上。保存后仍是一次 `wifi reload`，开机重读，重启不丢。
- **体验边界**：主动扫描约 2–5 秒，期间桥接可能短暂抖动，前端必须提示；扫描结果**不自动写配置**，必须用户点「选用」+ 填密码 + 保存，避免误连。
- 自检覆盖：manifest 注册、`sh -n`、零参数、纯只读、Lua 词法、四例 mock 真跑（iw 主 / wlanconfig 兜底 / 无工具 / 无接口）、前端按钮与联动字面、后台闭环、既有分组与椭圆未被挤掉、3 张真渲染截图。


## 二十二、双频宽与产品标识（r29.12 起）

### 两个频段必须独立字段，绝不共用一个 htmode

| 字段 | 管谁 | 允许值 | 默认 | 语义 |
|---|---|---|---|---|
| `htmode` | **5.8G** | `HT160` / `HT80` / `HT40` | `HT160` | QSDK `qcawifi.sh` 里 `HT160` = HE160 = **160MHz 满速**；写 `HE160`/`VHT80` 会让 5G radio 起不来（r28 实测） |
| `ht24` | **2.4G** | `HT40` / `HT20` | `HT40` | `HT40` = **20/40MHz 共存**（20MHz 客户端照样能关联）；`HT20` = 强制仅 20MHz |

- **交叉串写必须拒**：2.4G 绝不写 HT160/HT80/HE40，5G 绝不写 HT20。后台 `case` 双白名单 + 开机脚本双 `case` + AP 内联按 `hwmode` 分组，三处都要挡。
- **WDS 回程**：`vs010-wds-pair` 固定 `HT160`（160MHz），2.4G 不参与 4addr 桥接 —— 不因新增 ht24 而改动。
- **非法残留值跳过**：旧 `user.cfg` 里若有 HE160/HT160 落在 2.4G 侧，开机脚本只 log 不写 UCI，保留编译期默认，绝不写非法 `htmode`。
- **面板**：「④ WiFi 射频参数」两个独立下拉（`sel` 5G / `selLabels` 2.4G，值与显示文案分离），hint 必须写明「HT40 = 20/40 共存」与「勿填 HE160」。
- **持久化**：`ht24` 进 `user.cfg`，空字段保持原值，开机重读，重启不丢。

### 产品标识 WDS/AP（仿UBNT）

用户说「生成的固件要添加为 WDS/AP（仿UBNT）」，按**产品命名/标识**落地（不是新增第三种工作模式 —— AP ⇄ WDS 双模式单包架构不变）：

- 编译产物名 `Nwrt-QSDK12.2-5.4-**WDS-AP-UBNT**-<日期>-...-dual-squashfs-nand-factory.ubi`；**前缀/后缀原样保留**，既有下载/校验脚本不受影响。
- Release `name` 与 `body` 标注产品名 + 双频宽口径；tag 不变。
- 固件内 `/etc/vs010/product`（单行产品名）+ `/etc/banner`（SSH 登录横幅），两者必须注册进 `files.manifest`。
- 三界面（`/bridge/`、`/ap/`、`/ubnt/`）侧栏 brand、顶栏 pill、`<title>`，以及根跳转页，统一显示 **WDS/AP（仿UBNT）**。
- 自检覆盖：双白名单、mock 真跑 4 交叉负例、product/banner、manifest 注册、workflow 命名与 Release、界面显示、命名前后缀不回退。
