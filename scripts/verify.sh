#!/bin/sh
# 本地/Actions 自检。分级：真阻断项 FAIL 即停；文档/文案类降为非阻断警告。
set -u
W=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$W"
BLOCK=0; WARN=0
ok(){   printf '  OK   %s\n' "$1"; }
blk(){  printf '  FAIL %s\n' "$1" >&2; BLOCK=$((BLOCK+1)); }
wrn(){  printf '  WARN %s\n' "$1"; WARN=$((WARN+1)); }
has(){ [ -f "$1" ] && ok "$2" || blk "缺文件: $1"; }

echo "=== [1/9] 顶层文件 / 单包回归护栏 ==="
for f in README.md baseline.env feeds.conf.default .gitignore files.manifest \
         .github/workflows/build.yml config/common.seed config/gen-config.sh \
         scripts/board-inject.sh scripts/prepare.sh scripts/resolve-baseline.sh \
         scripts/health-fix scripts/wifi-fullspeed scripts/oem-stack-check \
         scripts/luacheck.py files/usr/sbin/nwrt-apply-mode files/usr/sbin/nwrt-tick \
         files/etc/nwrt/tick.conf files/etc/init.d/nwrt-tick \
         files/usr/lib/lua/luci/controller/admin/nwrt.lua \
         files/usr/lib/lua/luci/view/admin_nwrt/switch.htm; do
  has "$f" "$f"
done
for old in .github/workflows/build-wds.yml .github/workflows/build-ap.yml; do
  [ -f "$old" ] && blk "旧按模式拆包 workflow 还在: $old" || ok "已移除 $old"
done
for d in files.wds files.ap; do
  [ -d "$d" ] && blk "按模式拆包目录还在: $d（单包回归）" || ok "无 $d（单包双模式）"
done
grep -q 'default_mode' .github/workflows/build.yml && ok "workflow 有 default_mode 输入" || blk "缺 default_mode"
grep -q 'Nwrt-WDS-AP-UBNT' .github/workflows/build.yml && grep -q -- '-dual-' .github/workflows/build.yml && ok "产物名是单包 dual" || blk "产物名不是单包 dual"
grep -q '25:nwrt-tick' .github/workflows/build.yml && ok "开机链接含 nwrt-tick" || blk "缺 nwrt-tick 自启链接"

echo "=== [2/9] shell / python / JS 语法 + Lua 词法 ==="
for f in $(find . -type f \( -name '*.sh' -o -path './files/etc/init.d/*' \
            -o -path './files/usr/sbin/*' -o -path './files/www/cgi-bin/*' \) 2>/dev/null); do
  sh -n "$f" 2>/dev/null || blk "shell 语法错误: $f"
done
for f in $(find scripts config -type f -name '*.py' 2>/dev/null); do
  PYTHONDONTWRITEBYTECODE=1 python3 -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$f" 2>/dev/null || blk "python 语法错误: $f"
done
python3 scripts/luacheck.py files/usr/lib/lua/luci/controller/admin/nwrt.lua >/dev/null 2>&1 \
  && ok "Lua controller 词法" || blk "Lua controller 词法不通过（后台会 500）"
command -v node >/dev/null 2>&1 && {
  node --check files/www/app.js 2>/dev/null && ok "app.js 语法" || blk "app.js 语法"
  node --check files/www/vs010-ubnt-skin.js 2>/dev/null && ok "skin.js 语法" || blk "skin.js 语法"
} || wrn "node 不可用，跳过 JS 检查"
ok "shell / python 语法"

echo "=== [3/9] files.manifest 逐文件存在 + 无遗漏 ==="
while IFS= read -r p; do
  case "$p" in ''|'#'*) continue ;; esac
  [ -f "files/$p" ] || blk "manifest 指向不存在: files/$p"
done < files.manifest
ACTUAL=$(find files -type f | sed 's|^files/||' | sort)
MF=$(sort files.manifest)
[ "$ACTUAL" = "$MF" ] && ok "manifest 与 files/ 逐一对齐" || blk "manifest 与 files/ 不一致（有文件不会进固件）"
for p in www/vs010-ubnt.css www/vs010-ubnt-skin.js usr/sbin/health-fix \
         usr/sbin/wifi-fullspeed usr/sbin/oem-stack-check usr/sbin/nwrt-apply-mode \
         usr/sbin/nwrt-tick etc/nwrt/tick.conf etc/init.d/nwrt-tick \
         usr/lib/lua/luci/controller/admin/nwrt.lua usr/lib/lua/luci/view/admin_nwrt/switch.htm; do
  grep -qxF "$p" files.manifest && ok "manifest 已注册 $p" || blk "manifest 未注册 $p（编译后固件里不会有）"
done

echo "=== [4/9] LuCI 防 427 + 模式切换写入鉴权 ==="
grep -q "config core 'main'" files/etc/config/luci && ok "named core main" || blk "缺 named config core 'main'"
grep -q "mediaurlbase.*'/luci-static/ubnt'" files/etc/config/luci && ok "出厂 mediaurlbase=ubnt（UBNT 主题）" || blk "出厂没指向 UBNT 主题"
grep -q "config internal 'themes'" files/etc/config/luci && ok "标准 internal themes 段" || blk "themes 段格式错"
[ -f files/www/luci-static/ubnt/cascade.css ] && ok "UBNT 主题目录真实存在（非指向空气）" || blk "缺 ubnt/cascade.css"
grep -q '^@import url("/luci-static/bootstrap/cascade.css");' files/www/luci-static/ubnt/cascade.css && ok "UBNT 用 @import 引官方完整资源" || blk "缺 @import 底资源"
grep -q '^CONFIG_PACKAGE_luci-theme-bootstrap=y' config/common.seed && ok "bootstrap 底资源仍编入（删了会 404）" || blk "底资源被删，UBNT 会白屏"
grep -q 'theme=ubnt' files/etc/init.d/luci-fix && grep -q '回退' files/etc/init.d/luci-fix && ok "luci-fix UBNT 优先 + 依赖缺失回退" || blk "缺主题回退（白屏风险）"
grep -q 'luci.themes.UBNT' files/etc/init.d/luci-fix && ok "主题下拉含 UBNT" || blk "下拉没 UBNT"
grep -q 'theme=ubnt' files/etc/nwrt/user.cfg && ok "user.cfg 主题=ubnt" || blk "user.cfg 还是 bootstrap"
grep -q "'ubnt','UBNT（仿 UniFi）" files/www/app.js && ok "面板主题下拉 = UBNT" || blk "面板主题下拉未改"
grep -q 'v=="ubnt"' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "LuCI 白名单放行 ubnt" || blk "控制器会拒收 ubnt"
grep -q 'mediaurlbase' files/usr/sbin/nwrt-apply-config && ok "应用器真正落主题到 /etc/config/luci" || blk "主题只存 user.cfg 不生效"

echo "=== [4.6/9] 出厂账号密码（之前只在文档里写过，镜像里没落地）==="
[ -f files/etc/init.d/nwrt-passwd ] && ok "nwrt-passwd 脚本在" || blk "缺 root 密码脚本"
grep -q 'START=19' files/etc/init.d/nwrt-passwd && ok "开机 START=19" || blk "密码脚本没开机顺序"
grep -q 'chpasswd' files/etc/init.d/nwrt-passwd && ok "真设密码（非只写文档）" || blk "没有 chpasswd"
grep -q '用户已设 root 密码，保持不变' files/etc/init.d/nwrt-passwd && ok "不覆盖用户改过的密码" || blk "会反复覆盖用户密码"
grep -q 'FAILED' files/etc/init.d/nwrt-passwd && ok "失败如实记日志" || blk "会假装成功"
grep -q '19:nwrt-passwd' .github/workflows/build.yml && ok "workflow 已建 rc.d 链接" || blk "脚本编进镜像但不开机执行"
grep -q "option PasswordAuth 'on'" files/etc/config/dropbear && grep -q "option RootPasswordAuth 'on'" files/etc/config/dropbear && ok "dropbear 允许 root 密码登录" || blk "dropbear 会拒密码登录"
! grep -qE 'root:admin|^(password|passwd|pass)=' files/etc/nwrt/user.cfg && ok "明文密码不写进 user.cfg" || blk "配置里出现明文密码" 
grep -q 'luci-theme-argon' files/etc/config/luci && blk "luci 配置里出现幽灵 argon 主题" || ok "无幽灵主题"
# 🔴 零裸 CGI 写入端点：状态 CGI 只能读
FOUND=0
for c in files/www/cgi-bin/*; do
  [ -f "$c" ] || continue
  grep -v '^[[:space:]]*#' "$c" | grep -qiE 'uci (set|commit)|nwrt-apply-mode (wds|ap)|> */etc/nwrt/mode' && FOUND=1
done
if [ "$FOUND" = 1 ]; then
  blk "www/cgi-bin 里出现写入动作（必须只在 LuCI admin 树 / 串口）"
else
  ok "CGI 全只读，无裸写入端点"
fi
grep -q 'entry({"admin","nwrt"' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "切换端点在 admin 树（sysauth）" || blk "切换端点不在 admin 树"
grep -q 'mode == "wds" or mode == "ap"' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "mode 白名单校验" || blk "缺 mode 白名单"
grep -q 'case "$ACT" in' files/usr/sbin/nwrt-apply-mode && grep -q 'boot) MODE=' files/usr/sbin/nwrt-apply-mode && ok "apply-mode 固定枚举" || blk "apply-mode 缺固定枚举"
grep -q 'wifi reload' files/usr/sbin/nwrt-apply-mode && \
  ! (grep -v '^[[:space:]]*#' files/usr/sbin/nwrt-apply-mode | grep -q 'wifi down') && \
  ok "一次 reload / 无射频下线" || blk "apply-mode 违反不做射频下线"

echo "=== [4.7/9] 管理 IP：用户改过就保存，绝不自动改回 ==="
! grep -q 'rm -f /etc/nwrt/ipaddr' files/usr/sbin/nwrt-apply-config && ok "不再删除用户 IP 覆盖文件" || blk "会 rm ipaddr → 重启回 .241"
! grep -q '172.10.10.242 > /etc/nwrt/ipaddr' files/usr/sbin/nwrt-apply-config && ok "role=client 不再写死 .242 覆盖用户值" || blk "会写死 .242"
! grep -q 'rm -f /etc/nwrt/netmask' files/usr/sbin/nwrt-apply-config && ok "不删掩码覆盖文件" || blk "会删 netmask"
! grep -qE 'rm -f /etc/nwrt/(ipaddr|netmask)' files/etc/init.d/bridge-netfix && ok "开机脚本不删覆盖文件" || blk "bridge-netfix 会删覆盖文件"
grep -q '/etc/nwrt/ipaddr' files/etc/init.d/bridge-netfix && grep -q "/etc/nwrt/user.cfg" files/etc/init.d/bridge-netfix && ok "bridge-netfix 三级优先级" || blk "bridge-netfix 缺优先级"
grep -q '/etc/nwrt/netmask' files/etc/init.d/bridge-netfix && ok "掩码可覆盖（/etc/nwrt/netmask）" || blk "掩码仍写死"
grep -q 'network.lan.ipaddr' files/usr/sbin/nwrt-apply-config && ok "面板 IP 真正落到 network（非假生效）" || blk "面板 IP 假生效"
grep -q 'network.lan.netmask' files/usr/sbin/nwrt-apply-config && ok "面板掩码真正落到 network" || blk "面板掩码假生效"
grep -q '/etc/init.d/network reload' files/usr/sbin/nwrt-apply-config && ok "改完立刻 reload 生效" || blk "改完要等重启才生效"
grep -q 'sync_override' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "面板 save 同步写覆盖文件" || blk "面板改 IP 不持久"
grep -q 'http.formvalue("ip")' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "只同步显式提交的 ip（不覆盖串口设置）" || blk "每次保存都会覆盖串口 IP"
grep -q 'SETUP=$(printf' files/www/cgi-bin/state && grep -q 'NETIP' files/www/cgi-bin/state && ok "面板回填显示实际生效 IP" || blk "串口覆盖后面板显示旧值"
grep -q '改了就持久保存' files/www/app.js && ok "界面明示不自动改回" || blk "界面未说明"

echo "=== [4.8/9] 编译链真值：按 v25.12.6 实证防缺包 / 防配置被覆盖 ==="
! grep -q 'ipq-wifi-' board/ipq50xx.device.inc && ok "不引用上游不存在的 ipq-wifi-<机型> 包" || blk "引用了 ALLWIFIBOARDS 里没有的 ipq-wifi 包 → make 报缺包"
grep -q 'kmod-ath11k-ahb' board/ipq50xx.device.inc && ok "kmod-ath11k-ahb 保留（ath.mk:339 实证）" || blk "丢了 AHB 绑定驱动"
grep -q 'ath11k-firmware-ipq5018-qcn6122' board/ipq50xx.device.inc && ok "ath11k 固件包保留" || blk "丢了固件包（射频不 probe）"
grep -q 'ART_CALIBRATION=0' board/ipq50xx.device.inc && ok "机型 BDF 不进固件（用官方通用 board-2.bin）" || blk "缺 ART 口径说明"
for f in files.vs010/etc/config/system files.rax3000q/etc/config/system; do
  grep -q "config timeserver 'ntp'" "$f" && ok "$f 保留 timeserver 段（sysntpd 不失效）" || blk "$f 丢了 timeserver 段"
  grep -q "option log_size '64'" "$f" && grep -q "option urandom_seed '0'" "$f" && ok "$f 保留 log_size / urandom_seed" || blk "$f 丢了系统字段"
done
grep -q "option hostname 'VS010'" files.vs010/etc/config/system && grep -q "option hostname 'RAX3000Q'" files.rax3000q/etc/config/system && ok "两机型 hostname 仍各自区分" || blk "hostname 被覆盖成同一个"
grep -q 'apply-nand-patch.sh' .github/workflows/build.yml && ok "nand_patch 已接线（不再是假开关）" || blk "nand_patch 输入没接线"
[ -f scripts/apply-nand-patch.sh ] && ok "NAND 补丁脚本在" || blk "缺 apply-nand-patch.sh"
grep -q '不会把它复制进 openwrt' feeds.conf.default && ok "feeds 口径对齐上游锁 commit feeds" || blk "feeds 文档仍误导"

echo "=== [4.9/9] 无线界面：搜索点选 / 弱信号 / WDS 链路 / ART MAC / WMM·MU ==="
grep -q '"ok":1,"iface"' files/usr/sbin/nwrt-scan && ok "扫描输出结构化 JSON" || blk "扫描不是 JSON（前端无法点选）"
grep -qF 'sub(/\(.*/,"",bssid)' files/usr/sbin/nwrt-scan && ok "BSSID 去掉 (on 残留" || blk "BSSID 会带 (on wlan1)"
grep -q '$(NF-1)+0' files/usr/sbin/nwrt-scan && ok "频宽取 MHz 前的数字（非 MHz 字符串）" || blk "频宽解析取错字段"
grep -q 'HE160' files/usr/sbin/nwrt-scan && grep -q 'HE80' files/usr/sbin/nwrt-scan && grep -q 'HE20' files/usr/sbin/nwrt-scan && ok "160/80/40/20→HE* 映射" || blk "缺频宽自动匹配"
grep -q 'inferred' files/usr/sbin/nwrt-scan && ok "未广播频宽标记 inferred=0（不瞎猜）" || blk "会伪造频宽"
grep -q 'application/json' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "/scan 返回 JSON" || blk "scan 端点不是 JSON"
grep -q '"kick_enabled","kick_rssi"' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "新字段进白名单" || blk "kick 字段没进白名单"
grep -q 'kick_rssi=function' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "kick_rssi 范围校验" || blk "kick 阈值无校验"
grep -q 'data-pick' files/www/app.js && grep -q "set('peer_ssid'" files/www/app.js && ok "点选自动带入 SSID" || blk "搜索结果不能点选带入"
grep -q "set('ch5g'" files/www/app.js && grep -q "set('htmode'" files/www/app.js && ok "点选自动匹配信道/频宽" || blk "点选不带入频道频宽"
grep -q '密码请手动填入' files/www/app.js && ok "密码必须手填、不自动带入" || blk "密码被自动带回"
grep -q "fld('主端 SSID','peer_ssid'" files/www/app.js && grep -q "fld('BSSID 定向'" files/www/app.js && ok "手动填写区保留" || blk "手动填上级 WDS 信息的字段丢了"
grep -q 'WDS 回程 · LINK' files/www/app.js && grep -q '距离(估算)' files/www/app.js && ok "WDS 回程卡片（信号/距离/速率）" || blk "缺 WDS 链路显示"
grep -q '距离为 FSPL 估算' files/www/cgi-bin/state && grep -q '估算，非实测' files/www/app.js && ok "距离如实标注估算（非实测）" || blk "距离被冒充实测"
grep -q '"wds":%s' files/www/cgi-bin/state && grep -q 'iw dev "$IF" link' files/www/cgi-bin/state && ok "WDS 信号/TX·RX 从 iw link 实读" || blk "回程数据不是实读"
grep -q '弱信号控制 · RSSI' files/www/app.js && grep -q 'rssi_reject_assoc_rssi' files/www/app.js && ok "AP 页弱信号显示" || blk "AP 页缺弱信号显示"
grep -q "fld('弱信号拒绝连接阈值'" files/www/app.js && grep -q "fld('弱信号剔除（主动 deauth）'" files/www/app.js && ok "AP 页弱信号设置入口" || blk "缺弱信号设置字段"
grep -q 'rssi_reject_assoc_rssi' files/usr/sbin/nwrt-apply-config && grep -q 'rssi_reject_assoc_timeout' files/usr/sbin/nwrt-apply-config && ok "弱信号拒绝连接用主线真实 UCI" || blk "弱信号没真实下发"
grep -q 'disassoc_low_ack' files/usr/sbin/nwrt-apply-config && ok "disassoc_low_ack=1（hostapd 默认剔除）" || blk "缺无 ACK 解除关联"
grep -q 'WDS 是 STA 模式，hostapd 不运行' files/usr/sbin/nwrt-apply-config && grep -q 'delete "wireless.$sec.rssi_reject_assoc_rssi"' files/usr/sbin/nwrt-apply-config && ok "WDS 模式如实删除 AP-only 项（不伪造）" || blk "WDS 会假装弱信号生效"
grep -q 'station del' files/usr/sbin/nwrt-tick && grep -q 'kick_enabled' files/usr/sbin/nwrt-tick && ok "弱信号剔除走 iw station del（单常驻分频）" || blk "缺主动剔除"
grep -q 'kick_enabled=0' files/etc/nwrt/user.cfg && ok "主动剔除默认关（避免误踢）" || blk "剔除默认开会误踢"
grep -q 'nwrt-mac' files.manifest && [ -f files/usr/sbin/nwrt-mac ] && ok "ART MAC 自动读取脚本进 rootfs" || blk "缺 nwrt-mac"
grep -q '接口 · MAC（ART 自动读取）' files/www/app.js && grep -q '无输入框' files/www/app.js && ok "MAC 表格 + 零手填框" || blk "MAC 仍可手填"
grep -q 'macaddr_art_0' board/ipq5018-rax3000q.6.12.dts && grep -q 'hw_mac_addr' board/ipq5018-vs010.6.12.dts && ok "DTS nvmem-cells 从 ART 装配 MAC" || blk "DTS 丢 ART MAC 装配"
grep -q '"mac":%s' files/www/cgi-bin/state && ok "状态 JSON 输出接口 MAC" || blk "状态页不输出 MAC"
grep -q 'wmm_enabled=1' files/usr/sbin/nwrt-apply-config && grep -q '无独立 UCI 开关' files/usr/sbin/nwrt-apply-config && ok "WMM 已开且不伪造独立开关" || blk "WMM 口径失真"
grep -q 'mu_mimo=1' files/etc/nwrt/user.cfg && grep -q 'MU-MIMO=随 HE160' files/usr/sbin/nwrt-apply-config && ok "MU-MIMO 随 HE 启用（如实说明无独立 UCI）" || blk "MU-MIMO 口径失真"
! grep -qE 'name="?mac"?|fld\('"'"'MAC'"'"'' files/www/app.js && ok "界面无任何 MAC 输入框" || blk "出现 MAC 手填框"

echo "=== [4.10/9] NAND ECC：上游已内置 0401，禁止本仓重复放置 ==="
N=$(find patches -maxdepth 1 -name '*.patch' 2>/dev/null | wc -l | tr -d ' ')
[ "$N" = 0 ] && ok "patches/ 无重复内核补丁（不与上游 0401 冲突）" || blk "patches/ 有 $N 个 .patch，会与上游已内置 0401 重复"
grep -q '0401-spi-spi-qpic-snand-default-to-4-bit-ECC' patches/README.md && ok "口径写明上游 0401 已内置" || blk "缺上游内置说明"
grep -q 'patches-6.18/0401' patches/README.md && ok "口径覆盖 main(6.18) 的 patches-6.18" || blk "6.18 口径缺失"
grep -q 'NAND_PATCH_DEFAULT=0' baseline.env && ok "nand_patch 默认关" || blk "NAND 开关默认被打开"
grep -q 'patches-6.18' scripts/apply-nand-patch.sh && ok "6.18 提示对齐上游内置位置" || blk "6.18 提示仍误导"
grep -q 'nand-ecc-strength = <4>' board/ipq5018-vs010.6.12.dts && ok "VS010 DTS 显式 4-bit ECC（不走 1-bit 回退）" || blk "VS010 缺 4-bit ECC"
grep -q 'nand-ecc-strength = <8>' board/ipq5018-rax3000q.6.12.dts && ok "RAX3000Q DTS 显式 8-bit ECC（417 backport 支持）" || blk "RAX3000Q 缺 8-bit ECC"
grep -q 'nand-ecc-step-size = <512>' board/ipq5018-vs010.6.12.dts && grep -q 'nand-ecc-step-size = <512>' board/ipq5018-rax3000q.6.12.dts && ok "两台 step=512（QPIC 唯一支持值）" || blk "step size 不匹配"
grep -q 'git apply --check' scripts/apply-nand-patch.sh && ok "补丁仍先 check、不过只 warning 不停编" || blk "NAND 接线行为被改"

echo "=== [4.11/9] NSS 基线：包名按上游实证 + 缺包停编（防假加速）==="
grep -q 'NSS_PKGS="kmod-qca-nss-drv kmod-qca-nss-dp kmod-qca-nss-ecm kmod-nss-ifb nss-firmware-ipq50xx"' config/gen-config.sh && ok "NSS 5 包名全为上游实证名" || blk "NSS 包名仍是旧写法"
! grep -v '^#' config/gen-config.sh | grep -qE 'CONFIG_PACKAGE_nss-ecm=|qca-nss-fw-ipq50xx-retail' && ok "无 nss-ecm / qca-nss-fw 幽灵包" || blk "残留幽灵包名（defconfig 会静默丢弃）"
grep -q 'kmod-qca-nss-ecm' config/gen-config.sh && ok "ECM 用 kmod-qca-nss-ecm" || blk "ECM 包名错（加速会落空）"
grep -q 'nss-firmware-ipq50xx' config/gen-config.sh && ok "固件包用 nss-firmware-ipq50xx" || blk "NSS 固件包名错"
grep -q '6.6) NSS 加速包硬校验' config/gen-config.sh && grep -q '不要编一个「选了 NSS 基线却没有加速」的固件' config/gen-config.sh && ok "defconfig 后硬校验、缺包停编" || blk "NSS 缺包仍会静默通过"
grep -q 'nss_packages' README.md && grep -q 'NSS-12.5-K6.x' README.md && ok "口径写明 qosmio feeds 的 nss_packages" || blk "缺 NSS feed 说明"
grep -q '主线 ath11k' FIRMWARE.md && ok "口径区分参考仓 QSDK wifili 与主线 ath11k" || blk "会把 QSDK 实测当本仓保证"
grep -q 'NSS_QOSMIO_25_12_NSS=1' baseline.env && ok "qosmio 基线 NSS=1" || blk "qosmio 没开 NSS"
grep -q 'NSS_OFFICIAL_25_12=0' baseline.env && ok "默认 official-25.12 仍无 NSS（占用最低）" || blk "默认基线被改成 NSS"

echo "=== [4.12/9] nftables 变体：25.12 只有 nojson/json，禁写裸幽灵符号 ==="
grep -q '^CONFIG_PACKAGE_nftables-nojson=y' config/common.seed && ok "seed 用 25.12 默认变体 nftables-nojson" || blk "seed 未改用 nojson"
! grep -q '^CONFIG_PACKAGE_nftables=y' config/common.seed && ok "seed 无裸 CONFIG_PACKAGE_nftables=y 幽灵符号" || blk "裸幽灵符号回归（defconfig 会静默删除）"
grep -q 'nftables-json nftables' config/gen-config.sh && ok "6.5) 接受 nojson/json/裸符号三候选" || blk "6.5) 仍只认裸符号"
grep -q 'NFT_ANY' config/gen-config.sh && grep -qF 'nft=$NFT_ANY' config/gen-config.sh && ok "校验输出实际命中的变体名" || blk "日志看不出命中哪个变体"
grep -q 'PROVIDES' config/gen-config.sh && ok "注释写明 PROVIDES 不生成 CONFIG 符号" || blk "缺根因说明"
grep -q '^CONFIG_PACKAGE_kmod-nft-bridge=y' config/common.seed && ok "kmod-nft-bridge 仍在 MUST" || blk "桥模块丢失"
grep -q 'command -v nft' files/etc/init.d/l2-guard && ok "l2-guard 只依赖 nft 命令（nojson 提供）" || blk "防护脚本依赖被改"
grep -q '25.12 起主树只有' README.md && ok "README 写明变体根因" || blk "README 缺根因"
grep -q '46149348907' FIRMWARE.md && ok "FIRMWARE 记录本次失败 run" || blk "缺失败 run 记录"

echo "=== [4.5/9] 二层防护：DHCP Snooping / STP / WAN / 全内网桥 ==="
# DHCP Snooping 真生效的四道门槛，缺一就编出「假防护」
grep -qE '^CONFIG_PACKAGE_nftables(-nojson|-json)?=y' config/common.seed && ok "nft 用户态是 MUST（25.12 用 nojson 变体）" || blk "nft 未编入 → l2-guard 必然跳过"
grep -q '^CONFIG_PACKAGE_kmod-nft-bridge=y' config/common.seed && ok "kmod-nft-bridge 是 MUST" || blk "缺 bridge 表内核模块"
grep -q '未进 .config' config/gen-config.sh && ok "defconfig 后硬校验（缺包宁可停编）" || blk "缺二层防护硬校验"
grep -q "option enabled '1'" files/etc/config/l2guard && ok "l2guard 出厂 enabled=1" || blk "l2guard 没开"
grep -q 'hook prerouting' files/etc/init.d/l2-guard && ok "nft hook=prerouting（拦桥转发帧）" || blk "hook 不是 prerouting，拦不住私设 DHCP"
! (grep -v '^[[:space:]]*#' files/etc/init.d/l2-guard | grep -q 'hook input') && ok "无失效的 input 钩子" || blk "执行行仍残留 hook input"
grep -q 'FAILED' files/etc/init.d/l2-guard && grep -q 'nft list table' files/etc/init.d/l2-guard && ok "失败如实报 + 规则回读确认" || blk "会假报 OK"
grep -q 'sport 67' files/etc/init.d/l2-guard && grep -q 'sport 547' files/etc/init.d/l2-guard && ok "DHCPv4 67→68 / DHCPv6 547→546 都拦" || blk "缺 v4 或 v6 规则"
grep -q '22:l2-guard' .github/workflows/build.yml && ok "l2-guard 开机自启链接在" || blk "l2-guard 没进 rc.d"
# STP / WAN / 全内网桥
grep -q "option stp '1'" files/etc/config/network && ok "出厂 br-lan STP=1" || blk "出厂 STP 没开"
grep -q "network.br_lan.stp='1'" files/etc/init.d/bridge-netfix && ok "运行期 STP 写在 device 段" || blk "STP 写错段"
grep -q "network.br_lan.ports=" files/etc/init.d/bridge-netfix && ok "桥成员写在 device 段" || blk "ports 仍写在 interface 段（netifd 会忽略）"
! grep -q 'network.lan.ports=' files/etc/init.d/bridge-netfix && ok "无失效的 lan.ports" || blk "残留 lan.ports"
grep -q 'delete network.wan ' files/etc/init.d/bridge-netfix && grep -q 'delete network.wan6' files/etc/init.d/bridge-netfix && ok "运行期删 WAN / WAN6" || blk "没删 WAN/WAN6"
grep -q 'network.wan' files/etc/config/network && blk "出厂 network 里仍有 wan 段" || ok "出厂无 WAN / WAN6 段"
grep -q '/sys/class/net/wan[*]' files/etc/init.d/bridge-netfix && ok "WAN 物理口也进 br-lan" || blk "WAN 物理口没进桥"
grep -q 'head -1 /tmp/nwrt-l2guard.status' files/www/cgi-bin/state && ok "状态页显示实际结果非配置值" || blk "状态页会假装防护已生效"

echo "=== [5/9] 轻量巡检：单常驻、dryrun 默认、红线 ==="
N=$(grep -rl 'USE_PROCD=1' files/etc/init.d/ 2>/dev/null | wc -l | tr -d ' ')
[ "$N" = 1 ] && ok "procd 常驻只有 1 个（nwrt-tick）" || blk "procd 常驻 $N 个（应为 1）"
grep -q '^DRYRUN=1' files/etc/nwrt/tick.conf && ok "出厂 dryrun=1（只记录不动作）" || blk "DRYRUN 不是 1"
grep -q 'RELOAD_COOLDOWN' files/usr/sbin/nwrt-tick && grep -q 'wifi reload' files/usr/sbin/nwrt-tick && ok "限频 reload 冷却" || blk "缺 reload 冷却"
! (grep -v '^[[:space:]]*#' files/usr/sbin/nwrt-tick | grep -qE 'reboot|wifi down') && \
  ok "无重启 / 无射频下线" || blk "tick 里有重启或射频下线动作"
grep -q '/etc/nwrt/ipaddr' files/etc/init.d/bridge-netfix && ok "WDS 客户端 IP 可覆盖" || blk "缺 IP 覆盖机制（两台桥接会 .241 冲突）"

echo "=== [6/9] 插件精简 ==="
N=$(grep -cE '^(OPTIONAL:)?CONFIG_PACKAGE_luci-app-' config/common.seed 2>/dev/null || true)
[ "${N:-0}" -le 1 ] && ok "luci-app 数量 ${N:-0}（含 OPTIONAL 行）" || blk "seed 里 luci-app-* 出现 ${N:-0} 个"
grep -q 'dropbear=y' config/common.seed && ok "SSH 在" || blk "SSH 丢失"
grep -q '^# CONFIG_PACKAGE_firewall4 is not set' config/common.seed && ok "防火墙显式关" || blk "防火墙未显式关"

echo "=== [7/9] 板级 ==="
for d in board/ipq5018-vs010.6.12.dts board/ipq5018-rax3000q.6.12.dts; do
  [ -f "$d" ] || { blk "缺 $d"; continue; }
  o=$(tr -cd '{' < "$d" | wc -c); c=$(tr -cd '}' < "$d" | wc -c)
  [ "$o" = "$c" ] && ok "$(basename "$d") 花括号 $o/$c" || blk "$(basename "$d") 花括号 $o/$c 不配对"
  DIS=$(grep -c 'status = "disabled"' "$d" 2>/dev/null || true)
  [ "${DIS:-0}" -eq 0 ] && ok "$(basename "$d") 无残留 disabled" || blk "$(basename "$d") 仍有 ${DIS:-0} 处 disabled"
done
grep -q 'Device/unicom_vs010' board/ipq50xx.device.inc && ok "VS010 Device" || blk "缺 VS010 Device"
grep -q 'Device/cmcc_rax3000q' board/ipq50xx.device.inc && ok "RAX3000Q Device" || blk "缺 RAX3000Q Device"

echo "=== [8/9] 界面：三页 + 六入口 + mode 提示 + 命令兜底 ==="
for p in www/index.html www/ubnt/index.html www/bridge/index.html www/ap/index.html \
         www/vs010-ubnt.css www/vs010-ubnt-skin.js www/app.js \
         www/cgi-bin/state www/cgi-bin/bridge www/cgi-bin/apstatus; do
  has "files/$p" "$p"
done
grep -q 'u-jump' files/www/vs010-ubnt-skin.js && ok "UBNT 全互访注入器" || blk "UBNT 注入器缺失"
grep -q 'apstatus|state' files/www/vs010-ubnt-skin.js && ok "注入器接本仓 state CGI" || wrn "注入器未识别 state"
grep -q '/cgi-bin/luci/admin/nwrt' files/www/vs010-ubnt-skin.js && ok "六入口指向模式切换页" || blk "六入口仍指向旧 vs010_setup"
! grep -q 'vs010_setup' files/www/vs010-ubnt-skin.js && ok "无旧仓路径残留" || blk "残留 vs010_setup 路径"
grep -q 'data-page' files/www/app.js && grep -q 'mismatch' files/www/app.js && ok "非当前模式提示条（不强制跳）" || blk "缺 mode 提示条"
grep -q 'nwrt-apply-mode' files/www/app.js && ok "TTYD/SSH 命令兜底" || blk "缺命令兜底"
grep -q 'nwrt-tick\|TICK' files/www/app.js && ok "巡检卡片" || blk "缺巡检卡片"

echo "=== [9.5/9] 5.4 老仓界面基线（r28–r29.12）==="
# 前 3 块同序
grep -q '系统仪表盘' files/www/app.js && grep -q '常用设置控制台' files/www/app.js && grep -q '网络与本机' files/www/app.js && ok "前 3 块齐（GAUGE/SETUP/NETWORK）" || blk "缺前 3 块"
# 用 render() 里的真实拼接顺序判定，而不是全文首次出现（注释里也会出现这三个词）
LINE=$(grep -n "gauge(j)+setup(j)+network(j)" files/www/app.js | head -1)
[ -n "$LINE" ] && ok "两页前 3 块严格同序（render 内 gauge→setup→network）" || blk "前 3 块顺序错"
grep -q 'function ring' files/www/app.js && [ "$(grep -c 'ring(' files/www/app.js)" -ge 4 ] && ok "GAUGE 三环仪表" || blk "GAUGE 三环缺"
grep -q '时间 ' files/www/app.js && grep -q '运行 ' files/www/app.js && ok "时间 / 运行徽章" || blk "缺徽章"
grep -q '无线芯片温度' files/www/app.js && ok "无线芯片温度" || blk "缺无线芯片温度"
# SETUP 八分组
N=$(grep -o "grp('①\|grp('②\|grp('③\|grp('④\|grp('⑤\|grp('⑥\|grp('⑦\|grp('⑧" files/www/app.js | wc -l | tr -d ' ')
[ "$N" = 8 ] && ok "SETUP ①…⑧ 八分组" || blk "SETUP 分组 $N 个（应 8）"
grep -q 'HE160' files/www/app.js && grep -q 'HE40' files/www/app.js && grep -q 'HE20' files/www/app.js && ok "6.12 双频宽 HE*" || blk "频宽未升级为 HE*"
! grep -qE "'HT160'|'HT80'|'HT40'" files/www/app.js && ok "无 QSDK HT* 残留" || blk "残留 QSDK HT* 频宽"
grep -q '该基线不支持，不下发' files/www/app.js && ok "不支持字段如实标注" || blk "会伪造弱信号/MU-MIMO 已生效"
grep -q 'demo=1' files/www/app.js && ok "离线 ?demo=1 预览（老仓 r29.8）" || blk "缺离线预览"
# 六入口 / 胶囊 / 内网 LAN 6 列
grep -q "'⚙','常用设置'" files/www/vs010-ubnt-skin.js && grep -q "'⚙','高级设置后台'" files/www/vs010-ubnt-skin.js && ok "六入口文案对齐老仓" || blk "入口文案不一致"
grep -q '高级设置后台' files/www/vs010-ubnt-skin.js && ok "右上角 ⚙ 高级设置后台" || blk "缺右上角入口"
grep -q 'border-radius:999px' files/www/vs010-ubnt.css && ok "胶囊 999px" || blk "缺胶囊规则"
grep -q '内网LAN' files/www/cgi-bin/state && grep -q 'u-tbl6' files/www/app.js && ok "内网LAN1… + 6 列表" || blk "缺内网 LAN 6 列"
grep -q '链接速率' files/www/app.js && grep -q '速率来源' files/www/app.js && ok "链接速率 / 来源列" || blk "缺速率列"
# 写入只在 admin 树
grep -q '/cgi-bin/luci/admin/nwrt/save' files/www/app.js && ok "写入走 admin/save" || blk "写入端点不在 admin 树"
grep -q '/cgi-bin/luci/admin/nwrt/probe' files/www/app.js && ok "会话探测 probe" || blk "缺 probe"
grep -q '零 eval' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "零 eval 声明" || blk "控制器缺零 eval"
grep -q 'ACTS = {' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "维护动作固定枚举" || blk "维护动作未枚举"
grep -q 'nwrt-apply-config' files/etc/init.d/nwrt-mode && ok "开机重读 user.cfg" || blk "重启会丢配置"
grep -q '^CONFIG_PACKAGE_dnsmasq=y' config/common.seed && ok "AP 可选 DHCP 底座" || blk "缺 dnsmasq 底座"
# 🔴 seed 自相矛盾检查：同一符号不能同时 =y 与 is not set（后者会让 defconfig 静默关掉前者）
CONFLICT=$(python3 - <<'PYEOF'
import re,collections
d=collections.defaultdict(set)
for l in open('config/common.seed',encoding='utf-8'):
    s=l.strip()
    if s.startswith('OPTIONAL:'): s=s[9:]
    m=re.match(r'^(CONFIG_[A-Za-z0-9_]+)=y$',s)
    if m: d[m.group(1)].add('y')
    m=re.match(r'^# (CONFIG_[A-Za-z0-9_]+) is not set$',s)
    if m: d[m.group(1)].add('n')
print(','.join(k for k,v in d.items() if len(v)>1))
PYEOF
)
[ -z "$CONFLICT" ] && ok "seed 无符号值冲突" || blk "seed 符号冲突: $CONFLICT"
[ -f files/usr/sbin/nwrt-scan ] && ok "周边主端只读扫描" || blk "缺 nwrt-scan"
grep -q 'vs010_home' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "LuCI 一级返回菜单" || blk "缺 go_home 菜单"

echo "=== [9/9] 非阻断文档 / 参考 ==="
for f in FIRMWARE.md FLASHING.md MIGRATION.md 上传说明.txt 修复总览.md \
         docs/模式切换与巡检.md docs/源仓库取证.md docs/板级真值.md \
         docs/主题与UBNT界面.md docs/ART与无线校准.md docs/DHCP与SSH防护.md \
         reference/xiangye277/build.yml reference/old54/ipq5018-rax3000q.dts; do
  [ -f "$f" ] || wrn "可选文档缺失: $f"
done

echo "================================================"
if [ "$BLOCK" -gt 0 ]; then
  echo "RESULT: FAIL ($BLOCK 项阻断, $WARN 项非阻断警告)"
  exit 1
fi
echo "RESULT: PASS ($WARN 项非阻断警告)"
