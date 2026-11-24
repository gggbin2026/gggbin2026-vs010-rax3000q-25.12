#!/bin/sh
# 上传 GitHub / 点 Run workflow 之前跑一次：sh scripts/verify.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
FAIL=0
WARN=0
STRICT="${VERIFY_STRICT:-0}"      # 1 = 本地严格自检（警告也算失败）；CI 默认 0
ok(){ echo "  ✓ $1"; }
bad(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }
warn(){ echo "  ⚠ $1（非阻断，不停止编译）"; WARN=$((WARN+1)); }
has(){ grep -q "$1" "$2" 2>/dev/null; }

echo "==================== [verify] 新内核改造包自检 ===================="

# ── 第 42 次：网页上传最容易把 .github 传成 github（少个点）→ Actions 完全不识别 ──
if [ -d github/workflows ] && [ ! -d .github/workflows ]; then
  bad "workflow 目录少了前导点：github/workflows 应改名为 .github/workflows，否则 Actions 里看不到任何 workflow"
elif [ -d github/workflows ]; then
  bad "存在多余的 github/workflows（误传），请删除整个 github/ 目录，只保留 .github/workflows"
elif [ ! -d .github/workflows ]; then
  bad "缺 .github/workflows 目录，Actions 无法 Run workflow"
else
  ok "workflow 目录为 .github/workflows（带前导点）"
fi

for f in README.md MIGRATION.md FIRMWARE.md baseline.env feeds.conf.default \
         .github/workflows/build-wds.yml .github/workflows/build-ap.yml \
         scripts/prepare.sh scripts/board-inject.sh scripts/gen-config.sh \
         scripts/port-overlay.sh scripts/wifi-fullspeed.sh \
         config/common.seed config/wds.seed config/ap.seed config/themes.seed config/plugins.seed \
         board/ipq5018-vs010.6.12.dts board/README.md docs/DHCP与SSH防护.md \
         files/etc/config/l2guard files/etc/init.d/l2-guard files/usr/sbin/l2-guard \
         files/etc/init.d/wifi-fullspeed files/usr/sbin/wifi-fullspeed \
         files/etc/wifi-profile files/etc/uci-defaults/99-no-firewall; do
  [ -s "$f" ] && ok "存在 $f" || bad "缺文件 $f"
done

# ── 命名：模式字样 + 实际内核版本 + 日期 + 机型 ──
has 'PREFIX="Nwrt-WDS-${KTAG}-${STAMP}-"' .github/workflows/build-wds.yml \
  && ok "WDS 文件名 = 模式+内核版本+日期+机型" || warn "WDS 命名缺内核版本"
has 'PREFIX="Nwrt-AP-${KTAG}-${STAMP}-"' .github/workflows/build-ap.yml \
  && ok "AP 文件名 = 模式+内核版本+日期+机型" || warn "AP 命名缺内核版本"
has 'make -s kernel_version' .github/workflows/build-wds.yml \
  && has 'make -s kernel_version' .github/workflows/build-ap.yml \
  && ok "内核版本由 make kernel_version 实际抓取（含兜底）" || warn "未抓实际内核版本"
has 'fw-${KVER:-kernel}-' .github/workflows/build-wds.yml \
  && has 'fw-${KVER:-kernel}-' .github/workflows/build-ap.yml \
  && ok "Release tag 也带内核版本" || warn "tag 缺内核版本"
has 'FW_MODE: "wds"' .github/workflows/build-wds.yml && ok "WDS workflow 锁 wds" || warn "WDS 未锁模式"
has 'FW_MODE: "ap"'  .github/workflows/build-ap.yml  && ok "AP workflow 锁 ap"  || warn "AP 未锁模式"
has 'workflow_dispatch' .github/workflows/build-wds.yml && ok "push 不触发编译" || warn "触发方式异常"
grep -q '}-wds"' .github/workflows/build-wds.yml && ok "Release tag 后缀 -wds" || warn "tag 缺 -wds"
grep -q '}-ap"'  .github/workflows/build-ap.yml  && ok "Release tag 后缀 -ap"  || warn "tag 缺 -ap"
# 只查编译链里把旧 SDK 编号当【产物命名】用；取证文档里提及来源不算残留
if grep -rniE 'Nwrt-QSDK12|name:.*QSDK|PREFIX=.*QSDK|Nwrt-QSDK.*ubi' \
     .github config scripts board --exclude='verify.sh' 2>/dev/null | grep -q .; then
  bad "仓库仍残留旧 SDK 编号命名"; else ok "旧 SDK 编号前缀已彻底清除"; fi

# ── 新内核 / 无线加速（PZ-L8 参考口径）──
has 'BASE_A_KERNEL="6.12.116"' baseline.env && ok "推荐基线 6.12.116" || warn "基线 A 内核不对"
has 'BASE_C_KERNEL="6.18.60"'  baseline.env && ok "更高内核基线 6.18.60" || warn "基线 C 内核不对"
has 'WIFI_NSS_FW="12.5"' baseline.env && ok "NSS 固件 12.5 优先（12.2 仅回退）" || warn "未锁定 12.5"
has 'WIFI_OFFLOAD_PATH="ecm-nss"' baseline.env && ok "加速路径 ECM→NSS" || warn "加速路径口径不对"
has 'REF_PZL8_URL=' baseline.env && ok "PZ-L8 参考实现已记录（不作可编译基线）" || warn "缺参考实现"
has 'WIFI_DFS_CAC="60s"' baseline.env && ok "CN+HE160 的 60s DFS-CAC 已写明" || warn "缺 DFS 代价"
has 'WIFI_2G_NOSCAN="0"' baseline.env && ok "2.4G noscan 默认关（共存优先）" || warn "2.4G 口径不对"
has 'WIFI_SPEED_SOURCE="eth0/eth1"' baseline.env && ok "判速用 eth0/eth1，不用 br-lan" || warn "判速口径不对"
has 'DFS_CAC=60s' files/etc/wifi-profile && ok "运行期档案带 DFS/12.5" || warn "wifi-profile 缺新字段"
has 'uci -q get nss.general.wifi_offload' files/etc/init.d/wifi-fullspeed \
  && ok "wifi_offload 仅在配置已存在时才拉回（不凭空造 UCI）" || warn "仍会凭空创建 nss 配置"
if has 'uci -q set nss.general.enabled' files/etc/init.d/wifi-fullspeed; then
  bad "init.d 仍在造 nss.general.enabled"; else ok "init.d 不再造无用 UCI 段"; fi
has 'CONFIG_ATH11K_MEM_PROFILE_256M=y' config/common.seed && ok "256M 低内存 profile" || warn "缺 256M profile"
has 'ath11k-firmware-ipq5018-qcn6122=y' config/common.seed && ok "正确 ath11k 固件变体" || warn "固件包名不对"
has 'DEVICE_PACKAGES' scripts/board-inject.sh && ok "DEVICE_PACKAGES 已补（射频才会 probe）" || bad "缺 DEVICE_PACKAGES"

# ── 精简：只留 SSH + TTYD，关防火墙，不编无用插件 ──
has 'CONFIG_PACKAGE_dropbear=y' config/common.seed && ok "SSH(dropbear) 保留" || bad "缺 SSH"
has 'CONFIG_PACKAGE_ttyd=y' config/common.seed && has 'CONFIG_PACKAGE_luci-app-ttyd=y' config/common.seed \
  && ok "TTYD 保留（ttyd + luci-app-ttyd）" || bad "缺 TTYD"
has 'for k in firewall4 firewall' scripts/gen-config.sh && ok "防火墙编译期显式 n" || bad "防火墙未关"
n=$(grep -c '^CONFIG_PACKAGE_luci-app-.*=y$' config/common.seed || true)
[ "$n" -eq 1 ] && ok "luci-app 仅 1 个（ttyd），无第三方插件" || bad "luci-app 数量异常: $n"
has 'CONFIG_PACKAGE_kmod-nft-bridge=y' config/common.seed && ok "二层防护所需 nft bridge" || bad "缺 nft bridge"
has 'list ports' scripts/port-overlay.sh && ok "WAN+LAN 全部在 br-lan" || bad "未生成 DSA 同桥"

# ── 无线端 DHCP 防护 + 关闭防火墙 ──
has 'option enabled' files/etc/config/l2guard && ok "l2guard 配置存在" || bad "缺 l2guard 配置"
has 'udp sport 67' files/usr/sbin/l2-guard && ok "拦无线端 DHCP Offer/ACK" || bad "缺 DHCP 拦截规则"
has 'udp sport 547' files/usr/sbin/l2-guard && ok "拦 DHCPv6 Advertise" || bad "缺 DHCPv6 拦截"
has 'disable' files/etc/uci-defaults/99-no-firewall && ok "firewall4/firewall 运行期 disable" || bad "未 disable 防火墙"
has 'flow_offloading' files/etc/uci-defaults/99-no-firewall && ok "软/硬 flow offload 已关" || bad "未关 flow offload"
has 'l2-guard enable' scripts/port-overlay.sh && ok "防护服务写入开机启用链" || warn "防护未开机启用"
has 'PZ-L8 参考之后的重要修正' docs/DHCP与SSH防护.md \
  && ok "防护文档已写明「卸载流量不过 host bridge hook」" || warn "防护边界未更新"

# ── 主题页面 / LuCI 不报错（老仓库 dispatcher.lua:427 专项）──
has 'CONFIG_PACKAGE_luci-theme-bootstrap=y' config/common.seed \
  && ok "默认只编官方 bootstrap" || bad "未锁定官方 bootstrap"
if grep -qE '^CONFIG_PACKAGE_luci-theme-(argon|footstrap)=y' config/common.seed config/themes.seed; then
  bad "仍把社区主题写成 =y（feed 里没有，会白屏）"
else
  ok "argon / footstrap 显式关闭（官方 25.12 feed 不含）"
fi
has 'for seed in common themes "$MODE"' scripts/gen-config.sh \
  && ok "themes.seed 真正参与 .config 生成" || bad "themes.seed 没被读取（摆设）"
has '已从 .config 显式关闭' scripts/gen-config.sh \
  && ok "feed 里不存在的包会被显式移除（不是只 warning）" || bad "未知主题包仍会被静默丢弃"
has 'option Bootstrap' files/etc/config/luci \
  && has "config core 'main'" files/etc/config/luci \
  && has "option mediaurlbase '/luci-static/bootstrap'" files/etc/config/luci \
  && ok "编译期 luci 配置：named main + bootstrap + 单一主题" || bad "luci 配置仍指向空气"
if grep -qE "^[[:space:]]*option (Argon|Footstrap|Material) " files/etc/config/luci; then
  bad "编译期 themes 段仍列幽灵主题"; else ok "themes 段无幽灵项"; fi
has 'STATIC=/www/luci-static' files/usr/sbin/luci-fix \
  && has "config internal 'themes'" files/usr/sbin/luci-fix \
  && has 'awk -v blk' files/usr/sbin/luci-fix \
  && ok "luci-fix 按真实目录探测并每次重写主题下拉" || bad "luci-fix 缺动态探测"
if grep -q 'set -o pipefail' scripts/port-overlay.sh; then
  bad "port-overlay 仍用 pipefail（无匹配时会中断编译）"; else ok "port-overlay 无 pipefail 隐患（sh/bash 都能跑）"; fi
if grep -q 'option Footstrap' scripts/port-overlay.sh; then
  bad "port-overlay 仍往配置里塞 Footstrap（老仓库元凶）"; else ok "port-overlay 改为清理幽灵主题"; fi
has '/etc/luci-entry-enable' files/usr/sbin/luci-entry \
  && ok "luci-entry 默认不修改主题模板" || bad "luci-entry 仍会改主题模板"
has '主题目录' files/usr/sbin/health-fix && ok "health-fix 逐项核对主题目录" || bad "health-fix 缺主题检查"
for f in files/www/bridge/index.html files.ap/www/ap/index.html files.ap/www/bridge/index.html; do
  has '扩展数据未返回' "$f" && ok "CGI 失败有可见提示: $f" || warn "CGI 失败会静默空白: $f"
  if grep -qE '<script[^>]+src="https?://|<link[^>]+href="https?://' "$f"; then
    bad "页面依赖外链 CDN（断网会白屏）: $f"; else ok "页面零外链: $f"; fi
done
for c in files/www/cgi-bin/bridge files.ap/www/cgi-bin/apstatus; do
  sh -n "$c" 2>/dev/null && ok "CGI sh 语法: $c" || bad "CGI 语法错误: $c"
done
# 页面 <script> 块语法（有 node 就真检，没有就跳过，不误报）
if command -v node >/dev/null 2>&1; then
  JSOK=1
  for f in files/www/bridge/index.html files.ap/www/ap/index.html files.ap/www/bridge/index.html; do
    n=$(python3 -c 'import re,sys;print(len(re.findall(r"<script>(.*?)</script>",open(sys.argv[1],encoding="utf-8").read(),re.S)))' "$f" 2>/dev/null || echo 0)
    i=0
    while [ "$i" -lt "$n" ]; do
      python3 -c 'import re,sys;b=re.findall(r"<script>(.*?)</script>",open(sys.argv[1],encoding="utf-8").read(),re.S)[int(sys.argv[2])];open(sys.argv[3],"w",encoding="utf-8").write(b)' \
        "$f" "$i" /tmp/_vjs.js 2>/dev/null
      node --check /tmp/_vjs.js >/dev/null 2>&1 || JSOK=0
      i=$((i+1))
    done
  done
  rm -f /tmp/_vjs.js 2>/dev/null || true
  [ "$JSOK" = 1 ] && ok "三份页面全部 <script> 块通过 node --check" || warn "页面 JS 语法错误"
else
  echo "  · 无 node，跳过 JS 语法检查（上传前建议本地跑一次）"
fi

# ── ART 采集 / 校准边界（2026-11-24）──
for f in art/art-truth.conf art/oem-bootlog.txt art/collect.sh art/make-board2.py \
         art/README.md art/tools/ath11k-bdencoder docs/ART与无线校准.md \
         files/usr/sbin/art-check; do
  [ -s "$f" ] && ok "ART 资产: $f" || bad "缺 ART 资产: $f"
done
python3 -m py_compile art/make-board2.py >/dev/null 2>&1 \
  && ok "make-board2.py 语法" || bad "make-board2.py 语法错误"
sh -n art/collect.sh >/dev/null 2>&1 && ok "art/collect.sh 语法" || bad "collect.sh 语法错误"
sh -n files/usr/sbin/art-check >/dev/null 2>&1 && ok "art-check 语法" || bad "art-check 语法错误"
has 'CALDATA_DEFAULT=off' art/art-truth.conf \
  && ok "默认不启用 caldata（不砸已验证的无线路径）" || bad "caldata 默认值不是 off"
has 'ART_CALIBRATION_DEFAULT=0' art/art-truth.conf \
  && ok "默认不把 ART 校准编进固件" || bad "ART_CALIBRATION 默认不是 0"
has 'install_board2' scripts/board-inject.sh \
  && has '严格按机型取' scripts/board-inject.sh \
  && ok "board-inject 按机型装配、禁止跨机校准" || bad "board-inject 存在跨机误用风险"
has 'DEVICE_PACKAGES' scripts/board-inject.sh \
  && grep -q 'cmcc_rax3000q' scripts/board-inject.sh \
  && ok "RAX3000Q 补 DEVICE_PACKAGES（防射频不 probe）" || bad "RAX3000Q 仍缺固件包检查"
has 'QCA-ATH11K-BOARD' scripts/board-inject.sh \
  && ok "拒绝把单个 BDF 改名当 board-2.bin" || bad "缺容器签名校验"
has 'art-truth.conf' scripts/board-inject.sh \
  && ok "ART 文本真值进 rootfs 供自检" || bad "art-check 无真值可读"
has 'art-check' files/usr/sbin/health-fix \
  && ok "health-fix 集成 art-check" || bad "health-fix 未集成 art-check"
# 容器可解析性：用【实证在用的模板 BDF】造容器，官方工具交叉验证
# （不依赖根目录有没有 ART，模板 BDF 一定在；顺便验证第 40 次的方向纠正）
if python3 art/make-board2.py from-oem --out /tmp/_vboard.bin >/dev/null 2>&1 \
   && python3 art/tools/ath11k-bdencoder --info /tmp/_vboard.bin 2>/dev/null | grep -q 'BoardLength'; then
  ok "from-oem 产物通过官方 ath11k-bdencoder 解析（实证模板 BDF）"
else
  bad "from-oem 容器格式与官方工具不兼容"
fi
rm -f /tmp/_v.bdf /tmp/_vboard.bin /tmp/v2g.bdf /tmp/v5g.bdf /tmp/r2g.bdf /tmp/r5g.bdf \
      /tmp/base.bin /tmp/merged.bin /tmp/vs010-board-2.bin 2>/dev/null || true

# ── 实机日志一手证据 / 第 40 次方向纠正（2026-11-24）──
[ -s art/oem-bootlog.txt ] && grep -q 'Downloading BDF' art/oem-bootlog.txt \
  && ok "实机日志存档含 BDF 下载行" || warn "缺实机日志 / 无 BDF 下载行"
has 'OEM_BDF_IN_USE=unknown' art/art-truth.conf \
  && has 'ART_SLICE_IN_FIRMWARE=forbidden' art/art-truth.conf \
  && ok "第 41 次纠正：BDF 来源未实证 / ART 切片禁止进固件" || warn "BDF 结论未纠正"
has 'OEM_BOOTLOG_CALDATA' vs010/wifi-truth.conf \
  && has 'OEM_BDF_VERDICT' vs010/wifi-truth.conf \
  && ok "wifi-truth.conf 补入实机日志真值" || warn "wifi-truth.conf 缺一手实证"
has 'from-oem' art/make-board2.py \
  && has '实验性可选' art/make-board2.py \
  && ok "from-oem 已降级为实验性可选（不宣称实证等价）" || warn "from-oem 未纠正定位"
has '实证对照' art/collect.sh \
  && ok "collect.sh 输出模板 BDF vs ART 切片对照" || warn "缺实证对照段"
has 'ART 切片 BDF' scripts/board-inject.sh \
  && ok "装配前检出 ART 切片会警告并指引 from-oem" || warn "缺 ART 切片禁用校验"
has '00:03:7F:12' files/usr/sbin/art-check \
  && ok "art-check 检测 BDF 占位 MAC 家族" || warn "缺占位 MAC 检测"
has 'mem mode' docs/ART与无线校准.md \
  && has '不要抄' docs/ART与无线校准.md \
  && ok "文档写明闭源 mem mode 不能抄进主线 DTS" || warn "缺驱动栈边界说明"
has 'FM25LS01' patches/README.md && has 'U-Boot' patches/README.md \
  && ok "NAND 章节补 U-Boot 闪存表实证" || warn "NAND 章节未升级"
has '第 40 次' README.md \
  && ok "README 含本次方向纠正说明" || warn "README 缺第 40 次说明"

# ── 第 41 次：5.4.213 闭源好固件取证 / 累积总修复包 ──
for f in docs/OEM-QSDK12.2-取证报告.md vs010/oem-qsdk-truth.conf \
         files/etc/config/oem-qsdk-truth.conf files/usr/sbin/oem-stack-check \
         art/oem-qsdk-bdf/MD5清单.txt art/oem-qsdk-bdf/vs010-2g-bdwlan.b10 \
         art/oem-qsdk-bdf/vs010-5g-bdwlan.b60 \
         art/oem-qsdk-bdf/rax3000q-2g-bdwlan.b10 \
         art/oem-qsdk-bdf/rax3000q-5g-bdwlan.b60 \
         art/oem-qsdk-bdf/regdb.bin 修复总览.md; do
  [ -s "$f" ] && ok "第41次资产: $f" || bad "缺第41次资产: $f"
done
sh -n files/usr/sbin/oem-stack-check >/dev/null 2>&1 \
  && ok "oem-stack-check 语法" || bad "oem-stack-check 语法错误"
sh -n files/usr/sbin/health-fix >/dev/null 2>&1 \
  && ok "health-fix 语法" || bad "health-fix 语法错误"
has 'oem-stack-check' files/usr/sbin/health-fix \
  && has '[7/7]' files/usr/sbin/health-fix \
  && ok "health-fix 第 7 段挂了 OEM 栈自检" || bad "health-fix 未挂自检"
has 'BDF_CORRECTION' vs010/oem-qsdk-truth.conf \
  && has 'BDF_CLAIM_40' vs010/wifi-truth.conf \
  && ok "第 40 次 BDF 断言已标注推翻" || warn "缺方向纠正留痕"
has 'KERNEL=5.4.213' vs010/oem-qsdk-truth.conf \
  && has 'K_NEWREPO=6.12' vs010/oem-qsdk-truth.conf \
  && ok "真值含 5.4.213 vs 6.12 内核对照" || warn "缺内核对照"
has 'PORTABLE_BINARIES=0' vs010/oem-qsdk-truth.conf \
  && has 'PORTABLE_KNOWLEDGE=1' vs010/oem-qsdk-truth.conf \
  && ok "结论：二进制不可搬、工作方式可迁移" || warn "缺可迁移性结论"
has 'qcom,bdf-addr' docs/OEM-QSDK12.2-取证报告.md \
  && has '禁止抄进主线 ath11k DTS' docs/OEM-QSDK12.2-取证报告.md \
  && ok "DTB bdf-addr / 不能抄进 ath11k 已写明" || warn "缺 DTB 边界"
# 取证 BDF 绝不能被编译链引用
if grep -q 'oem-qsdk-bdf' scripts/board-inject.sh scripts/prepare.sh 2>/dev/null; then
  bad "取证 BDF 被装配链引用（应只作存档）"
else
  ok "取证 BDF 只作存档（board-inject/prepare 无引用）"
fi
has '第 41 次' 修复总览.md && has '累积' 修复总览.md \
  && ok "修复总览为累积清单" || warn "修复总览不是累积版"
has 'openwrt/' .gitignore && has 'firmware_out/' .gitignore \
  && ok ".gitignore 含第40次末尾 3 行（修仓库差异）" || warn ".gitignore 缺末尾 3 行"
has '第 41 次' README.md && has '第 41 次' FIRMWARE.md \
  && ok "README / FIRMWARE 含第 41 次说明" || warn "文档缺第 41 次"

# ── 第 43 次：CI 自检分级 + qosmio 25.12 编译链适配 ──
# (1) verify 自身：纯文档/卫生项不能阻断编译（第 43 次之前的致命问题）
has 'warn()' scripts/verify.sh && has 'VERIFY_STRICT' scripts/verify.sh \
  && has 'RESULT: PASS' scripts/verify.sh \
  && ok "verify.sh 已分级：非阻断项只警告，不 exit 1" || bad "verify.sh 未分级（一个文档项就能卡死编译）"
has '.gitignore 缺末尾 3 行' scripts/verify.sh \
  && grep -q 'warn ".gitignore 缺末尾 3 行"' scripts/verify.sh \
  && ok ".gitignore 卫生项已降级为警告" || bad ".gitignore 仍是硬失败"
# (2) 25.12 布局：DTS 在 files/arch/arm64/boot/dts/qcom，不是旧的 qualcommax/dts
has 'qualcommax-files' scripts/board-inject.sh \
  && has 'files/arch/arm64/boot/dts/qcom' scripts/board-inject.sh \
  && ok "board-inject 适配 25.12 的 DTS 目录（否则报「不是 ipq50xx 源码树」停编）" \
  || bad "board-inject 未适配 25.12 DTS 布局"
grep -Fq 'cmcc,pz-l8[|)]' scripts/board-inject.sh \
  && ok "02_network 锚点同时兼容 pz-l8| 与 pz-l8) 两种写法" || bad "02_network 锚点仍写死"
# (3) RAX3000Q 板级：qosmio 树里没有，必须本仓注入
RQDTS=board/ipq5018-rax3000q.6.12.dts
[ -s "$RQDTS" ] && ok "第43次资产: $RQDTS" || bad "缺 RAX3000Q 板级 DTS"
has 'cmcc,rax3000qy' "$RQDTS" && has 'status = "okay"' "$RQDTS" \
  && ok "RAX3000Q DTS 用实证 compatible 且 wifi/q6v5 已启用" || bad "RAX3000Q DTS 身份或射频状态不对"
if grep -qE 'KEY_RESTART|label[[:space:]]*=[[:space:]]*"reset"' "$RQDTS"; then
  bad "RAX3000Q DTS 含复位键（悬空 GPIO 会误进 failsafe）"
else
  ok "RAX3000Q DTS 不定义 keys/leds（避免悬空 GPIO 误进 failsafe）"
fi
has 'define Device/cmcc_rax3000q' scripts/board-inject.sh \
  && has 'TARGET_DEVICES += cmcc_rax3000q' scripts/board-inject.sh \
  && ok "board-inject 会注入 Device/cmcc_rax3000q（gen-config 符号才有效）" \
  || bad "缺 RAX3000Q 设备定义注入"
has 'inject:pz-l8-skeleton' baseline.env \
  && ok "baseline.env 已纠正「树内原生 RAX3000Q」的错误断言" || bad "baseline.env 仍是错误断言"
# (4) gawk / defconfig 诊断
has 'GNU awk' scripts/gen-config.sh \
  && has 'tmp/.targetinfo 为 0 字节' scripts/gen-config.sh \
  && ok "gen-config 会诊断 gawk 缺失导致的设备符号丢失" || bad "缺 gawk/defconfig 诊断"
# (5) 报告
[ -s docs/编译链预检与板级缺口.md ] \
  && ok "第43次资产: docs/编译链预检与板级缺口.md" || bad "缺编译链预检报告"

# ── 第 44 次（配置收口）：IPv6 关闭 / DHCP 防护 / 插件精简 ──
# (1) IPv6：编译期全局开关 + 运行期三层兜底
has 'CONFIG_IPV6=n' config/common.seed \
  && ok "编译期 CONFIG_IPV6=n（官方全局开关，非 5.4 ECM hack）" || bad "IPv6 编译期未关"
for k in odhcpd odhcpd-ipv6only odhcp6c luci-proto-ipv6 ip6tables kmod-ip6tables; do
  grep -qE "^CONFIG_PACKAGE_$k=n$" config/common.seed \
    && ok "编译期不编 $k" || bad "缺 CONFIG_PACKAGE_$k=n"
done
has 'luci-proto-ipv6' scripts/gen-config.sh \
  && has 'CONFIG_IPV6=n 由 common.seed' scripts/gen-config.sh \
  && ok "gen-config.sh 兜底再写一遍 IPv6 包" || bad "gen-config 缺 IPv6 兜底"
IP6=files/etc/uci-defaults/99-no-ipv6
[ -s "$IP6" ] && sh -n "$IP6" 2>/dev/null \
  && has 'disable_ipv6=1' "$IP6" && has 'ula_prefix' "$IP6" \
  && has 'dhcp.lan.ra' "$IP6" && has 'odhcpd' "$IP6" \
  && ok "运行期 99-no-ipv6（sysctl + UCI + 停 odhcpd）" || bad "缺/错 99-no-ipv6"
# (2) 无线 DHCP 防护：默认开 + IPv6 关闭后的降级容错
has "option enabled '1'" files/etc/config/l2guard \
  && ok "无线端 DHCP 防护默认开启（l2-guard）" || bad "无线 DHCP 防护未开启"
has 'sport 547' files/usr/sbin/l2-guard \
  && has 'applied-v4-only' files/usr/sbin/l2-guard \
  && ok "l2-guard 有 DHCPv6 失败时降级仅拦 IPv4 的容错" || bad "l2-guard 缺 v4 降级容错"
if grep -q "^config odhcpd" files.ap/etc/config/dhcp 2>/dev/null; then
  bad "files.ap/etc/config/dhcp 仍留 config odhcpd 段（包已不编）"
else
  ok "AP 模式 dhcp 配置已删 odhcpd 段"
fi
# (3) 精简复核：插件只有 ttyd、防火墙关、WAN/LAN 同桥
n=$(grep -c '^CONFIG_PACKAGE_luci-app-.*=y$' config/common.seed)
[ "$n" -eq 1 ] && has 'CONFIG_PACKAGE_luci-app-ttyd=y' config/common.seed \
  && ok "插件仅 luci-app-ttyd 一个（+ dropbear/TTYD）" || bad "插件数量异常: $n"
has 'for k in firewall4 firewall' scripts/gen-config.sh \
  && ok "防火墙编译期显式 n" || bad "防火墙未关"
has 'list ports' scripts/port-overlay.sh \
  && ok "WAN+LAN 全部在 br-lan" || bad "未生成同桥"

# ── 第 44 次：用户上传的 DTS/DTB 板级真值核对 ──
DTS_V=board/ipq5018-vs010.6.12.dts
DTS_R=board/ipq5018-rax3000q.6.12.dts
# (1) 只读取证资产（缺了说明包没传全 → 硬判据）
for f in docs/oem-dts/README.md docs/oem-dts/vs010.dtb \
         docs/oem-dts/VS010_原厂MTD分区表.txt \
         docs/oem-dts/VS010与CMCC机型DTS资料核查报告.md \
         docs/oem-dts/VS010_DTS获取清单与来源.md \
         docs/oem-dts/ipq5018-pz-l8.dts docs/oem-dts/ipq5018-rax3000q.dts \
         docs/oem-dts/ipq5018-rax3000q.MAIN.dts; do
  [ -s "$f" ] && ok "第44次取证资产: $f" || bad "缺第44次取证资产: $f"
done
# 文档报告只警告，不阻断编译（第 43 次教训：纯文档项不能卡死 CI）
[ -s docs/板级真值-第44次.md ] \
  && ok "第44次资产: docs/板级真值-第44次.md" \
  || warn "缺 docs/板级真值-第44次.md（不阻断编译）"
# (2) VS010：实机 FDT 的 LED / NAND ECC 已落地，且仍无复位键
has 'led_mesh: led-0' "$DTS_V" && has 'led_pwr: led-1' "$DTS_V" \
  && has '"gpio33", "gpio31"' "$DTS_V" \
  && ok "VS010 LED 已按 vs010.dtb 实机改为 mesh33/pwr31" || bad "VS010 LED 仍是 PZ-L8 的 GPIO35"
has 'nand-ecc-strength = <4>' "$DTS_V" && has 'nand-ecc-step-size = <512>' "$DTS_V" \
  && ok "VS010 NAND ECC 4bit/512（实机 FDT）" || bad "VS010 缺 4bit/512 ECC"
if sed -E '/^[[:space:]]*(\/\/|\/\*|\*|\*\/)/d' "$DTS_V" \
     | grep -qE 'KEY_RESTART|label[[:space:]]*=[[:space:]]*"reset"'; then
  bad "VS010 DTS 含复位键（悬空 GPIO 会误进 failsafe）"
else
  ok "VS010 DTS 仍无复位键（实机 FDT 只有 WPS GPIO34）"
fi
has 'xiangye277' "$DTS_V" && ok "VS010 头注释已纠正 fork 来源被否定的问题" \
  || warn "VS010 头注释未标注来源纠正（不阻断）"
has '0x4d300000' "$DTS_V" && ok "VS010 已标注 5G bdf-addr 跨栈差异（不改）" \
  || warn "VS010 缺 bdf-addr 跨栈差异说明（不阻断）"
# (3) RAX3000Q：按官方 main 原文校正端口 / ECC / 双 compatible
has '"cmcc,rax3000q", "cmcc,rax3000qy"' "$DTS_R" \
  && ok "RAX3000Q compatible 双写（官方名 + QY 变体）" || bad "RAX3000Q compatible 未双写"
has 'nand-ecc-strength = <8>' "$DTS_R" && has 'nand-ecc-step-size = <512>' "$DTS_R" \
  && ok "RAX3000Q NAND ECC 8bit/512（GD5F1GQ5REYIG）" || bad "RAX3000Q 缺 8bit/512 ECC"
if grep -qE '^[[:space:]]*(keys|leds) \{' "$DTS_R"; then
  bad "RAX3000Q DTS 定义了 keys/leds（变砖案例：复位键 GPIO 冲突）"
else
  ok "RAX3000Q DTS 故意不定义 keys/leds（防硬砖）"
fi
has 'label = "wan"' "$DTS_R" && has 'phy-handle = <&qca8337_0>' "$DTS_R" \
  && has 'label = "lan3"' "$DTS_R" && has 'phy-handle = <&qca8337_4>' "$DTS_R" \
  && ok "RAX3000Q 端口按官方映射：PHY0=WAN / PHY4=LAN3" \
  || bad "RAX3000Q 端口仍是 PZ-L8 的 PHY3=WAN"
has 'label-mac-device = <&dp2>' "$DTS_R" \
  && ok "RAX3000Q label-mac-device 指向单链路 gmac1(=&dp2)" || bad "RAX3000Q MAC 设备引用不对"
# (4) 编译期注入双分支（否则 board_name 匹配不到 → 不进 br-lan）
grep -Fq 'cmcc,rax3000q|' scripts/board-inject.sh \
  && grep -Fq 'cmcc,rax3000qy|' scripts/board-inject.sh \
  && ok "02_network 注入两个 compatible 分支" || bad "02_network 缺双分支"
has '第 44 次补证' baseline.env && ok "baseline.env 已补「官方 main 有但 25.12 稳定分支无」实证" \
  || warn "baseline.env 缺第 44 次补证（不阻断）"

# ── NAND 补丁（V2 批次，默认关）──
for f in patches/README.md patches/440-mtd-spinand-add-support-for-FudanMicro-FM25LS01.patch scripts/apply-nand-patch.sh; do
  [ -s "$f" ] && ok "NAND 资产: $f" || bad "缺 NAND 资产: $f"
done
bash -n scripts/apply-nand-patch.sh >/dev/null 2>&1 \
  && ok "apply-nand-patch.sh 语法" || bad "apply-nand-patch.sh 语法错误"
has 'NAND_PATCH:-0' scripts/apply-nand-patch.sh \
  && ok "NAND 补丁默认关闭（V1/ESMT 板子不碰）" || bad "NAND 补丁默认值不是关"
has 'git apply --check' scripts/apply-nand-patch.sh \
  && has 'git apply' scripts/apply-nand-patch.sh \
  && ok "先 check 再 apply，失败只警告不停编" || bad "缺补丁预检/容错"
has '不是 6.12' scripts/apply-nand-patch.sh \
  && ok "6.18 基线自动跳过（pending-6.12 不适用）" || bad "缺基线门"
has 'FM25LS01' scripts/apply-nand-patch.sh \
  && ok "幂等（已含 FM25LS01 不重复打）" || bad "缺幂等判断"
has 'EUCLEAN' patches/README.md \
  && has '未' patches/README.md \
  && ok "EUCLEAN 风险与未实机验证已写明" || warn "缺风险说明"
has 'apply-nand-patch.sh' scripts/prepare.sh \
  && ok "prepare.sh 已接入 NAND 补丁" || bad "prepare.sh 未接入"
for w in .github/workflows/build-ap.yml .github/workflows/build-wds.yml; do
  has 'nand_patch:' "$w" && has 'NAND_PATCH:' "$w" \
    && ok "$(basename "$w") 有 nand_patch 开关" || bad "$(basename "$w") 缺 NAND 开关"
done

# ── 温度 / NSS 实况 / 界面 ──
for f in files/www/bridge/index.html files.ap/www/ap/index.html files.ap/www/bridge/index.html; do
  has 'extTempBig' "$f" && has 'sysTempBig' "$f" && has 'extTtyd' "$f" \
    && has 'ethRate' "$f" && has 'DFS-CAC' "$f" \
    && ok "温度 + NSS 实况 + DFS 扩展: $f" || warn "界面扩展缺失: $f"
done
for f in files/www/cgi-bin/bridge files.ap/www/cgi-bin/apstatus; do
  has 'ath11k_hwmon' "$f" && has 'type.*cpu' "$f" \
    && has 'cpu_load_ubi' "$f" && has 'connection_count' "$f" && has 'wifili' "$f" \
    && has 'NSS_ETH_JSON' "$f" && has 'temp_rf_count' "$f" \
    && ok "PZ-L8 温度口径 + NSS debugfs 字段: $f" || warn "CGI 字段缺失: $f"
  has '"nss"' "$f" && ok "顶层 nss 段: $f" || warn "缺 nss 段: $f"
done
if grep -rn '纯二层桥不做三层转发\|offload 规则用不上' files/www/cgi-bin files.ap/www/cgi-bin >/dev/null 2>&1; then
  bad "CGI 仍有「桥内 offload 用不上」错误口径"; else ok "加速文案已按 ECM→NSS 修正"; fi
has 'br-lan/brif' files/www/cgi-bin/bridge && ok "端口按 sysfs 动态发现（不猜默认路由）" || warn "端口仍写死"
if grep -rn 'Linux 5.4 / QSDK NHSS' files files.ap >/dev/null 2>&1; then bad "页面残留旧基线写死文案"; else ok "无旧基线写死文案"; fi

# ── 板级 / BDF ──
DTS=board/ipq5018-vs010.6.12.dts
has 'qcom,ath11k-calibration-variant' "$DTS" && ok "DTS 是 6.12 ath11k 风格" || bad "DTS 仍是旧风格"
sed -E '/^[[:space:]]*(\/\/|\/\*|\*|\*\/)/d' "$DTS" | grep -qE 'KEY_RESTART|label[[:space:]]*=[[:space:]]*"reset"' \
  && bad "DTS 含复位键" || ok "DTS 无 KEY_RESTART（WPS GPIO34）"
for pair in "board-cucc_vs010.ipq5018:c7d89771464322ea39ca290249295af9" \
            "board-cucc_vs010.qcn6122:0aadbd42"; do
  f="${pair%%:*}"; m="${pair##*:}"
  [ -s "vs010/bdf/$f" ] || { bad "缺 BDF $f"; continue; }
  md5=$(md5sum "vs010/bdf/$f" | awk '{print $1}')
  case "$md5" in "$m"*) ok "BDF $f ($md5)" ;; *) echo "  ℹ BDF $f MD5=$md5（确认是否换批次）" ;; esac
done
has 'board-2.bin 正确合成途径' board/README.md && ok "board-2.bin 合成途径已写明" || warn "缺 BDF 容器说明"
has 'DEVICE_PACKAGES 必须补' board/README.md && ok "板级文档含 PZ-L8 教训" || warn "板级文档未更新"
has 'ipq-wifi-cucc_vs010' scripts/board-inject.sh && ok "本地 BDF 包（不联网、不 403）" || bad "缺本地包"

# ── 无旧栈残留符号 ──
if grep -rE 'CONFIG_LINUX_5_4|CONFIG_TARGET_ipq50xx_arm|CONFIG_ATH11K_NSS_SUPPORT|MAC80211_NSS_SUPPORT|qca-nss-fw-ipq50xx-retail|kmod-qca-ssdk-nohnat|CONFIG_PACKAGE_luci-lib-ipkg' config scripts .github/workflows 2>/dev/null | grep -v '不要\|不搬\|老\|#' | grep -q .; then
  bad "种子/脚本残留旧 QSDK 专用符号"; else ok "无旧 QSDK 残留符号"; fi

n=$(find files files.ap files.vs010 files.rax3000q -type f | wc -l)
[ "$n" -ge 55 ] && ok "运行期 overlay 资产 $n 个" || bad "overlay 资产偏少: $n"

echo "=========================================================="
if [ "$STRICT" = 1 ] && [ "$WARN" -gt 0 ]; then
  echo "VERIFY_STRICT=1：$WARN 项警告按失败处理（本地严格自检用）"
  FAIL=$((FAIL+WARN))
fi
if [ "$FAIL" -eq 0 ]; then
  echo "RESULT: PASS（$WARN 项非阻断警告）—— 可以上传并 Run workflow"
else
  echo "RESULT: FAIL ($FAIL 项阻断 / $WARN 项警告)"
fi
exit "$FAIL"
