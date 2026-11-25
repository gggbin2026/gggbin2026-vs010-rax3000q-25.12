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
has(){ grep -q -- "$1" "$2" 2>/dev/null; }   # -- 兼容以 - 开头的检索词（如 --notes-file）

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
has 'KERNEL_PATCHVER' .github/workflows/build-wds.yml \
  && has 'KERNEL_PATCHVER' .github/workflows/build-ap.yml \
  && ok "内核版本读自源码树（KERNEL_PATCHVER + LINUX_VERSION，不调用 make）" \
  || warn "内核版本未从源码树读取"
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
# 第 52 次：以第 51 次为冻结基线，【只增不减】。原来写死 -eq 1 会拦住以后新增插件。
[ "$n" -ge 1 ] && has 'CONFIG_PACKAGE_luci-app-ttyd=y' config/common.seed \
  && ok "luci-app ≥1 且基线项 luci-app-ttyd 在位（当前 $n 个，允许增加）" \
  || bad "luci-app 数量异常或基线 ttyd 丢失: $n"
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

# ── 第 47 次：SSH / DHCP 防护 / TTYD / 防火墙 / 删 WAN / NTP 客户端 / STP ──
# 用户 7 项要求逐条硬校验，避免后续上传覆盖把配置带回去。

# ① SSH（dropbear 监听 0.0.0.0:22，密码/根登录全开）
for k in "option enable '1'" "option PasswordAuth '1'" "option RootPasswordAuth '1'" "option RootLogin '1'" "option Port '22'"; do
  grep -qF "$k" files/etc/config/dropbear || bad "SSH 配置缺 $k"
done
if grep -E '^[[:space:]]*option Interface' files/etc/config/dropbear >/dev/null 2>&1; then
  bad "SSH 又绑回了 Interface（会随 IP 切换失联）"
else
  ok "SSH：0.0.0.0:22 / root 密码登录 / 不绑 lan 接口"
fi
has '/etc/init.d/dropbear enable' files/etc/uci-defaults/99-bridge-ready \
  && ok "SSH 首启 enable + restart（health-fix 另有兜底）" || bad "SSH 缺首启启用"

# ② 无线 DHCP Snooping（二层 rogue-DHCP 拦截）必须开启
has "option enabled '1'" files/etc/config/l2guard \
  && has "option dryrun '0'" files/etc/config/l2guard \
  && has "option dhcpv6 '1'" files/etc/config/l2guard \
  && ok "无线端 DHCP 防护 enabled=1 / dryrun=0 / 含 DHCPv6" \
  || bad "无线 DHCP 防护未开启或处于 dryrun"
has 'l2-guard enable' scripts/port-overlay.sh && ok "l2-guard 已写入开机启用链" || bad "l2-guard 未开机启用"

# ③ 插件：以第 51 次为冻结基线，只增不减（允许以后新增，不许删基线项）
has 'CONFIG_PACKAGE_luci-app-ttyd=y' config/common.seed && ok "冻结基线 LuCI 插件 luci-app-ttyd 在位（允许增加）" || bad "TTYD 插件丢失"
has 'CONFIG_PACKAGE_ttyd=y' config/common.seed && ok "ttyd 本体保留（:7681）" || bad "ttyd 本体丢失"

# ④ 防火墙 / IPv6 关闭
has 'CONFIG_IPV6=n' config/common.seed && ok "IPv6 编译期关闭" || bad "IPv6 未关"
has 'firewall4' scripts/gen-config.sh && ok "firewall4 显式 n" || bad "防火墙未显式关闭"
has '99-no-firewall' files/etc/uci-defaults/99-bridge-ready || true
[ -s files/etc/uci-defaults/99-no-firewall ] && ok "运行期 99-no-firewall 兜底" || bad "缺 99-no-firewall"

# ⑤ 删除 wan / wan6 三层接口（物理 WAN 端口仍留在 br-lan 的 list ports）
for f in files/etc/config/network files.ap/etc/config/network; do
  if grep -qE "^config interface '(wan|wan6)'" "$f"; then bad "$f 仍定义 wan/wan6 三层接口"; else ok "$(basename $(dirname $(dirname $f)))/… network 无 wan/wan6 接口"; fi
  has "list ports 'wan'" "$f" && ok "  物理 WAN 端口仍在 br-lan（WAN+LAN 同桥）" || bad "  物理 WAN 端口丢失"
done
for f in files/etc/uci-defaults/99-bridge-ready files.ap/etc/uci-defaults/99-bridge-ready files/etc/uci-defaults/99-no-ipv6; do
  has 'uci -q delete network.wan' "$f" && has 'uci -q delete network.wan6' "$f" \
    && ok "$(echo $f | cut -c1-52)… 运行期删 wan/wan6" || bad "$f 缺 wan/wan6 删除"
done

# ⑥ NTP 客户端：只同步两台内网服务器
NTP_OK=1
for f in files/etc/config/system files.vs010/etc/config/system files.rax3000q/etc/config/system; do
  has "list server '192.168.1.254'" "$f" && has "list server '172.10.10.254'" "$f" \
    && has "option use_dhcp '0'" "$f" && has "option enable_server '0'" "$f" && has "option enabled '1'" "$f" \
    || { bad "$f NTP 配置不完整"; NTP_OK=0; }
done
[ "$NTP_OK" = 1 ] && ok "三份 system：NTP 客户端 → 192.168.1.254 / 172.10.10.254（enable_server/use_dhcp=0）"
for f in files/etc/uci-defaults/99-bridge-ready files.ap/etc/uci-defaults/99-bridge-ready; do
  has 'for s in 192.168.1.254 172.10.10.254' "$f" || bad "$f 首启仍写公网 NTP"
done
if grep -rqE 'ntp\.aliyun\.com|cn\.pool\.ntp\.org|time1\.cloud\.tencent\.com' files files.ap files.vs010 files.rax3000q config scripts 2>/dev/null; then
  bad "仍残留公网 NTP 服务器"; else ok "全仓已无公网 NTP 服务器（严格只用内网两源）"; fi
if grep -rqE "^[[:space:]]*config route 'ntp172'|option gateway '192\.168\.1\.254'" files/etc/config/network files.ap/etc/config/network scripts/port-overlay.sh 2>/dev/null; then
  bad "仍保留第 47 次失效的 /32 路由（/22 下 172.10.10.254 已直连，且网关跨网段会被 netifd 拒绝）"
else
  ok "已删除失效 /32 路由；NTP 172.10.10.254 走 /22 二层直连"
fi

# ⑦ STP 开启（DSA 下必须写在 config device 段）+ 25.12 网络兜底不删 device
for f in files/etc/config/network files.ap/etc/config/network; do
  has "option stp '1'" "$f" && has "config device 'br_lan'" "$f" || bad "$f STP 未写在 device 段"
done
has "network.br_lan.stp='1'" files/etc/uci-defaults/99-bridge-ready \
  && has "network.br_lan.stp='1'" files.ap/etc/uci-defaults/99-bridge-ready \
  && ok "首启兜底也会把 STP 设到 br_lan device 段" || bad "STP 首启兜底缺失"
if grep -rqF 'uci -q delete network.@device[0]' files files.ap 2>/dev/null; then
  bad "仍有 21.02 老兜底删除 config device（25.12 会让 br-lan 建不出来、SSH 失联）"; else ok "已无删除 config device 的 21.02 老兜底"; fi
has '第47次：25.12 DSA 保留 config device' scripts/port-overlay.sh \
  && ok "port-overlay 有防呆兜底" || warn "port-overlay 缺防呆兜底"

# ⑧ 干净系统 / 低资源 / 日志简洁
LEAN=1
for f in files/etc/rc.local files/usr/sbin/health-fix; do
  has 'for s in cron ucitrack led gpio_switch' "$f" || { bad "$f 缺精简服务循环"; LEAN=0; }
done
[ "$LEAN" = 1 ] && ok "精简常驻服务 cron/ucitrack/led/gpio_switch（开机 + health-fix 双层兜底）"
# 第 51 次：sysntpd 常驻由 ntp-poller 顶替（两者不能同时改系统时间），
# 所以 sysntpd disable 是允许的；但必须同时有 ntp-poller enable，否则 NTP 会彻底没有。
if grep -rqE '/etc/init.d/(network|dropbear|ttyd|uhttpd|wpad) disable' files files.ap 2>/dev/null; then
  bad "误关了 SSH / TTYD / uhttpd / wpad / network 之一"; else ok "必留服务均未被关（SSH/TTYD/LuCI/无线/网络）"; fi
if grep -rq '/etc/init.d/sysntpd disable' files files.ap 2>/dev/null \
   && ! grep -rq '/etc/init.d/ntp-poller enable' files files.ap 2>/dev/null; then
  bad "停用了 sysntpd 却没启用 ntp-poller（NTP 会彻底失效）"; else ok "sysntpd → ntp-poller 切换成对出现"; fi
LOGOK=1
for f in files/etc/config/system files.vs010/etc/config/system files.rax3000q/etc/config/system; do
  has "option log_size '32'" "$f" || { bad "$f log_size 不是 32"; LOGOK=0; }
done
[ "$LOGOK" = 1 ] && ok "运行期 log buffer 32KB（三份机型覆盖层一致）"
for f in .github/workflows/build-wds.yml .github/workflows/build-ap.yml; do
  has 'build_verbose' "$f" && has 'V=0 > build.log' "$f" && has '失败摘要（只列真实错误' "$f" \
    && ok "$(basename "$f")：默认简洁编译日志 + 可切详细" \
    || bad "$(basename "$f") 仍会刷屏（缺 V=0 / build_verbose / 精准摘要）"
done
[ "$(wc -l < files/etc/banner)" -le 14 ] && ok "登录 banner 已精简（14 行内）" || warn "banner 偏长"

# ── 第 48 次：管理网段统一 172.10.10.241 / 255.255.252.0（/22）──
# 用户指定：所有设备 IP = 172.10.10.241、掩码 = 255.255.252.0。
# 唯一例外：WDS 备机由 bridge-role 自动顺延 172.10.10.242，避免两台同 IP 的 ARP 冲突。
NET_OK=1
for f in files/etc/config/network files.ap/etc/config/network; do
  has "option ipaddr '172.10.10.241'" "$f" && has "option netmask '255.255.252.0'" "$f" \
    && has "config device 'br_lan'" "$f" || { bad "$f 管理地址/掩码不是 172.10.10.241/22"; NET_OK=0; }
done
[ "$NET_OK" = 1 ] && ok "两份 network：172.10.10.241 / 255.255.252.0（DSA device 段）"
has "AP_IP=172.10.10.241" scripts/prepare.sh && ok "prepare.sh AP/WDS 统一 172.10.10.241" \
  || bad "prepare.sh 仍分流不同管理地址"
has 'write_network "${AP_IP:-172.10.10.241}"' scripts/port-overlay.sh \
  && has "option netmask '255.255.252.0'" scripts/port-overlay.sh \
  && ok "port-overlay 产物默认 172.10.10.241/22" || bad "port-overlay 未同步新网段"

# 全仓旧管理网段字面量必须清零（NTP 源 192.168.1.254、取证文档、历史备份名除外）
# 排除 verify.sh 自身（判据文本里本来就写着旧值，避免自命中）
OLDN=$(grep -rlE '192\.168\.1\.(240|241|242|10|100)|255\.255\.255\.0' \
       files files.ap files.vs010 files.rax3000q scripts config .github/workflows art 2>/dev/null \
       | grep -v '^scripts/verify.sh$' || true)
if [ -n "$OLDN" ]; then bad "仍残留旧网段：$OLDN"; else ok "全仓已无旧管理地址与旧掩码"; fi
OLD24=$(grep -rlE '(^|[^0-9])/24([^0-9]|$)' files files.ap scripts .github/workflows 2>/dev/null \
        | grep -v '^scripts/verify.sh$' || true)
if [ -n "$OLD24" ]; then bad "仍有 /24 前缀：$OLD24"; else ok "前缀长度统一 /22（255.255.252.0）"; fi
# 关键运行期文件逐个点名（防止漏改某个回落值）
KEY=1
for f in files/etc/banner files.ap/etc/banner files/etc/bridge.conf files/www/cgi-bin/bridge \
         files.ap/www/cgi-bin/apstatus files/etc/init.d/bridge-netfix \
         files/etc/uci-defaults/99-bridge-ready files.ap/etc/uci-defaults/99-bridge-ready \
         files/usr/lib/bridge/role.sh files/usr/sbin/health-fix files/usr/sbin/nic-guard \
         files.ap/usr/sbin/bridge-ap; do
  has '172.10.10.241' "$f" || { bad "$f 未同步 172.10.10.241"; KEY=0; }
done
[ "$KEY" = 1 ] && ok "12 个运行期文件（banner/CGI/兜底/工具）全部同步"
has "BRIDGE_STA_IP='172.10.10.242'" files/usr/lib/bridge/role.sh \
  && ok "WDS 备机仍自动顺延 172.10.10.242（防两台同 IP 冲突）" \
  || warn "WDS 备机地址可能被改成 .241，成对部署会 ARP 冲突"
# NTP 两源保持不变（用户只改设备 IP，未改 NTP）
NTP2=1
for f in files/etc/config/system files.vs010/etc/config/system files.rax3000q/etc/config/system; do
  has "list server '192.168.1.254'" "$f" && has "list server '172.10.10.254'" "$f" \
    || { bad "$f NTP 源被误改"; NTP2=0; }
done
[ "$NTP2" = 1 ] && ok "两个内网 NTP 源保持不变（172.10.10.254 现同 /22 直连可达）"

# ── 第 50 次：改 IP 不误重启 / 自动发现对端 / 下载页红字 ─────────
IP50=1
for k in "LL_AP='169.254.241.1'" "LL_STA='169.254.241.2'" \
         '_ensure_ll_alias' '_discover_peer' '_refresh_discovery' '_ip_warn' 'resync)'; do
  has "$k" files/usr/sbin/bridge-watchdog || { bad "机器狗缺第50次能力 $k"; IP50=0; }
done
[ "$IP50" = 1 ] && ok "机器狗：别名兜底 + 动态发现对端 + resync + 红字告警齐全"
has 'wd_ll=$(_ll_peer)' files/usr/sbin/bridge-watchdog \
  && has '_peer_ok "$wd_ll"' files/usr/sbin/bridge-watchdog \
  && ok "ping 判据优先走链路本地别名（改管理 IP 不受影响）" \
  || bad "链路本地别名未接入 _wd_ping_ok"
for f in files/etc/init.d/bridge-netfix files/usr/lib/bridge/role.sh files/usr/sbin/health-fix; do
  has '169.254.241' "$f" || bad "$f 未挂 WDS 角色别名"
done
ok "三处冗余挂载 WDS 角色别名（开机 / 角色收敛 / health-fix）"
has 'ip_changed' files/www/cgi-bin/bridge && has 'wdIpWarn' files/www/bridge/index.html \
  && ok "状态页显示本机IP/别名/发现对端 + 改IP红条" || bad "状态页缺第50次展示"
for f in .github/workflows/build-wds.yml .github/workflows/build-ap.yml; do
  has 'CHANGE-IP-NOTICE.txt' "$f" && has '033\[31m' "$f" && has '🔴' "$f" \
    && ok "$(basename "$f")：下载说明红字段落 + Actions 真红日志 + NOTICE 附件" \
    || bad "$(basename "$f") 缺改 IP 说明/标红"
done
has '改网桥 IP 必读' release/RELEASE-NOTES-WDS.md \
  && has 'resync' release/RELEASE-NOTES-WDS.md \
  && ok "WDS Release NOTES（独立 md）明确写「改 IP 不会误重启 + resync」" \
  || bad "WDS Release NOTES 缺改 IP 说明"
has '🔴 改管理 IP 后请跑 bridge-watchdog resync' files/etc/banner \
  && ok "登录 banner 带改 IP 提示" || bad "banner 缺改 IP 提示"
[ "$(wc -l < files/etc/banner)" -le 14 ] && ok "登录 banner 仍精简（14 行内）" || warn "banner 偏长"
# ── 第 58 次：机器狗改成独立插件，配置 100% 由用户设置 ──────────────
# 用户原话：「把机器狗改成插件，配置我自己来设置」。
# 旧实现的三处「替用户做主」：① 编译期 workflow 注入 delay/peer；
# ② 首启 99-bridge-ready 强写 7 个 uci set（用户改的值开机就被冲掉）；
# ③ 脚本缺省硬编码「启用 + 5 分钟」。这次全部收口：
#   · 新增标准 OpenWrt package/bridge-watchdog（可 apk 单独装卸/升级）
#   · 用户配置层 /etc/wdsdog.conf 优先级最高；bridge-watchdog config 生成模板
#   · 未配置时只待命、绝不重启
#   · 基线 82 项一字不动，【追加】[pkg]|bridge-watchdog → 83 项（只增不减）
P58=1
for f in package/bridge-watchdog/Makefile \
         package/bridge-watchdog/files/bridge-watchdog \
         package/bridge-watchdog/files/bridge-watchdog.init \
         package/bridge-watchdog/files/USER-CONFIG.md \
         package/bridge-watchdog/files/wdsdog.conf.example; do
  [ -f "$f" ] && ok "插件包文件存在: $f" || { bad "插件包缺 $f"; P58=0; }
done
has 'CONFIG_PACKAGE_bridge-watchdog=y' config/common.seed \
  && grep -Fq '[pkg]|bridge-watchdog' baseline/frozen-baseline.conf \
  && ok "插件包已进 seed + 冻结基线（追加，不是删减）" \
  || { bad "插件包未进 seed/基线"; P58=0; }
NF58=$(grep -c '^\[' baseline/frozen-baseline.conf)
[ "$NF58" -ge 83 ] \
  && ok "冻结基线 $NF58 项 ≥ 83（旧 82 项全保留 + 新增 1 项，只增不减）" \
  || { bad "冻结基线只有 $NF58 项（应 ≥83）"; P58=0; }
# 包内脚本与 files/ 必须逐字节一致，防止两份逻辑漂移
if cmp -s files/usr/sbin/bridge-watchdog package/bridge-watchdog/files/bridge-watchdog; then
  ok "插件包脚本与 files/ 逐字节一致（单一实现）"
else
  bad "插件包脚本与 files/usr/sbin/bridge-watchdog 不一致"; P58=0
fi
for k in 'USER_CONF=/etc/wdsdog.conf' '_user_cfg' 'UNCONFIGURED' 'CFG_SRC' 'config)'; do
  has "$k" files/usr/sbin/bridge-watchdog || { bad "机器狗缺第58次能力 $k"; P58=0; }
done
[ "$P58" = 1 ] && ok "第 58 次：机器狗=独立插件；编译期不注入 / 首启不覆写 / 未配置不重启 / 配置全归用户"

# ── 第 57 次：实机启动兜底（VS010 Starting kernel 后零输出 + 自动重启）──
# 11-25 刷入 VS010 后 U-Boot 日志止于 "Jumping to AARCH64 kernel via monitor"，
# 无任何内核输出并循环重启。核查结论：
#   · fdt_fixup_qpic / parse_fdt_fixup / Could not find PCI 是【无害 warning】：
#     OpenWrt 官方 commit 3bbb4f6 明确「bootloader tries to fixup the qpic nand
#     node, it actually can't find it as the node was renamed to spi」——
#     6.12 主线节点已从 qpic-nand@79b0000 改名 spi@79b0000，官方 pz-l8 同样
#     打印这几行且实机可启动，不要去补 /soc/qpic-nand 节点。
#   · 真正可疑：/chosen 缺 bootargs 兜底 + 第 44 次从 5.4 闭源 FDT 抄来的
#     nand-ecc-strength/step-size 强行声明（官方 pz-l8 没有）。
P57=1
for d in board/ipq5018-vs010.6.12.dts board/ipq5018-rax3000q.6.12.dts; do
  has 'console=ttyMSM0,115200n8' "$d" && has 'ubi.mtd=rootfs' "$d" \
    && has 'rootfstype=squashfs' "$d" && has 'rootwait' "$d" \
    && ok "$(basename "$d") /chosen 带完整 bootargs 兜底（console/ubi/rootwait）" \
    || { bad "$(basename "$d") 缺 bootargs 兜底"; P57=0; }
  grep -qE '^[[:space:]]*nand-ecc-(strength|step-size)' "$d" \
    && { bad "$(basename "$d") 仍有闭源 ECC 属性"; P57=0; } \
    || ok "$(basename "$d") 无强行 ECC 声明"
done
[ -f docs/TTL-启动诊断.md ] \
  && ok "存在 docs/TTL-启动诊断.md（不重编即可定位根因）" \
  || { bad "缺 TTL 启动诊断文档"; P57=0; }
[ "$P57" = 1 ] && ok "第 57 次：板级 DTS 与官方实机基线对齐 + bootargs 兜底"

# ── 第 56 次：Release 发布步骤不再把 Markdown 塞进 shell 字符串 ─────
# 11-25 08:04 两台编译【其实全部成功】、固件已上传 artifact，却都挂在最后
# Publish Release 步骤 exit 127：
#   line 3: gen-config.sh: command not found
#   line 3: 172.10.10.241: command not found
#   line 3: bridge-watchdog: command not found
#   command substitution: syntax error near unexpected token `newline'
# 根因：NOTES="...`xxx`..." 里的 Markdown 反引号被 bash 当成【命令替换】执行，
# 且步骤是 set -euo pipefail，第一个失败就整个步骤挂掉。
# 修法：说明文本独立成 release/*.md，用 gh release create --notes-file 传入，
#       完全不经过 shell 解释；元信息用几行不含反引号的 echo 追加。
P56=1
for wf in .github/workflows/build-wds.yml .github/workflows/build-ap.yml; do
  # 只看代码行（排除注释），代码行里不允许出现反引号 / 旧 NOTES 赋值
  bad_ticks=$(awk '/^[[:space:]]*#/{next} /`/ {n++} END{print n+0}' "$wf")
  [ "$bad_ticks" = 0 ] \
    && ok "$(basename "$wf") Publish 步骤代码行无反引号（不会再触发命令替换）" \
    || { bad "$(basename "$wf") Publish 步骤代码行仍有 $bad_ticks 个反引号"; P56=0; }
  has --notes-file "$wf" \
    && ok "$(basename "$wf") 使用 --notes-file 传 Release 说明" \
    || { bad "$(basename "$wf") 缺 --notes-file"; P56=0; }
  if grep -qE '^[[:space:]]*NOTES="|printf .%b. "\$NOTES"' "$wf"; then
    bad "$(basename "$wf") 仍残留旧 NOTES 双引号赋值"; P56=0
  else
    ok "$(basename "$wf") 已移除旧 NOTES 双引号赋值"
  fi
  has 'cp "$GITHUB_WORKSPACE/release/' "$wf" \
    && ok "$(basename "$wf") 从独立 md 文件读取说明" \
    || { bad "$(basename "$wf") 未引用 release/*.md"; P56=0; }
done
for n in RELEASE-NOTES-WDS.md RELEASE-NOTES-AP.md; do
  [ -f "release/$n" ] && ok "存在 release/$n（纯 Markdown，不经过 shell）" \
    || { bad "缺 release/$n"; P56=0; }
done
# 说明文件本身允许有反引号（它是文件，不是 shell 字符串），但要确认它没被当成脚本
head -1 release/RELEASE-NOTES-WDS.md | grep -q '^✅' \
  && ok "Release 说明是纯文本 md（首行非 shebang，不会被当脚本执行）" \
  || { bad "Release 说明格式异常"; P56=0; }
[ "$P56" = 1 ] && ok "第 56 次：编译成果能正常发布成 Release（exit 127 已消除）"

# ── 第 55 次：彻底移除「树里查不到包源 → 真缺 → exit 1」─────────────
# 03:2x 编译再次在 make 之前断掉：
#   🔴 冻结基线包在当前源码树里完全找不到（Kconfig 无符号、无包源）：
#      luci-i18n-base-zh-cn kmod-bridge
# 这两个是【平台提供 / 模板生成】，本来就不以独立包目录或符号存在：
#   · luci-i18n-base-zh-cn：luci.mk 按 po/zh-cn 模板生成
#   · kmod-bridge：25.12 内核 CONFIG_BRIDGE=y 内建，netsupport.mk 已无该 kmod 定义
# ★ 定论：「树里能不能找到包源」≠「插件有没有被删」，绝不能当阻断条件。
P55=1
if grep -vE '^[[:space:]]*#' scripts/gen-config.sh | grep -qE 'REAL_MISS|_pkg_known_anywhere|完全找不到'; then
  bad "🔴 仍残留第 54 次「真缺阻断」代码（会再把平台提供项误判成缺包）"; P55=0
else
  ok "已彻底移除第 54 次「真缺阻断」代码（REAL_MISS / _pkg_known_anywhere）"
fi
has 'PLATFORM_PROVIDED' scripts/gen-config.sh \
  && has 'kmod-bridge luci-i18n-base-zh-cn' scripts/gen-config.sh \
  && ok "平台提供项显式归类（内核内建 / luci.mk 模板生成），只计入诊断" \
  || { bad "缺平台提供项归类"; P55=0; }
# B 层之后到文件末尾，除「核心锚点」「设备符号」「defconfig 自身失败」外不应再有包相关 exit 1
n_exit=$(awk '/第 55 次 B 层/{f=1} f && !/^[[:space:]]*#/ && /exit 1/{n++} END{print n+0}' scripts/gen-config.sh)
[ "$n_exit" -le 2 ] && ok "B 层仅保留 $n_exit 处硬退出（核心锚点收敛 / 设备符号丢失），无包相关阻断" \
  || { bad "B 层仍有 $n_exit 处代码 exit 1，可能又加了包相关阻断"; P55=0; }
has 'SEED_DECL_MISS' scripts/gen-config.sh \
  && ok "A 层 seed 声明 29/29 硬阻断仍在（只增不减的真保障）" \
  || { bad "A 层硬阻断被误删"; P55=0; }
[ "$P55" = 1 ] && ok "第 55 次：B 层纯诊断，编译不再因 Kconfig / 包源结构差异停编"

# ── 第 54 次：修复第 52 次「defconfig 后精确 =y」误判 ───────────────
# 2026-11-25 02:28 编译在 make 之前 exit 1：
#   🔴 冻结基线包缺失（只增不减）： luci-i18n-base-zh-cn nftables kmod-bridge（+rax3000q 的 ipq-wifi-cucc_vs010）
# 这 4 个是 make defconfig 的【合法 Kconfig 收敛】，不是谁删了插件：
#   25.12 的 target/linux/generic/config-6.12 里 CONFIG_BRIDGE=y（内核内建），
#   netsupport.mk 已无 KernelPackage/bridge，kmod-bridge 包符号自然隐藏；
#   i18n / nftables 属符号合并；ipq-wifi-cucc_vs010 只在 vs010 生成本地包。
#   上一轮同树同 seed 输出「✓ 760 个 =y 符号」并跑到 make 48 分钟可佐证。
P54=1
has 'SEED_DECL_MISS' scripts/gen-config.sh && has 'A 层 seed 声明' scripts/gen-config.sh \
  && ok "A 层：seed 声明 29/29 硬阻断（防人为删 =y，这才是只增不减的真保障）" \
  || { bad "缺 A 层 seed 声明硬阻断"; P54=0; }
has 'STRICT_PKGS' scripts/gen-config.sh && has 'PLATFORM_PROVIDED' scripts/gen-config.sh \
  && has 'CONVERGED' scripts/gen-config.sh \
  && ok "B 层：defconfig 后只诊断（核心锚点严格 / 其余收敛与平台提供只警告）" \
  || { bad "缺 B 层诊断（第55次口径）"; P54=0; }
if grep -q 'MISSING_PKGS' scripts/gen-config.sh; then
  bad "🔴 仍残留第 52 次的全量精确 =y 阻断（会再次把 Kconfig 收敛误判成缺包）"; P54=0
else
  ok "已移除第 52 次误判逻辑（MISSING_PKGS 全量阻断）"
fi
has 'COND_VS010_ONLY' scripts/gen-config.sh \
  && ok "rax3000q 下本地 BDF 包按机型条件跳过（seed 声明仍在）" \
  || { bad "缺机型条件项处理"; P54=0; }
# 构建树排除野文件（仓库文件一个不删）
has 'KEEP_EXTRA_FILES' scripts/prepare.sh && has '构建树已排除包外野文件' scripts/prepare.sh \
  && ok "prepare.sh 构建树排除 14 个包外野文件（仓库原地保留，KEEP_EXTRA_FILES=1 可逆）" \
  || { bad "缺构建树野文件排除"; P54=0; }
for x in etc/init.d/ntp-sync etc/init.d/dhcp-guard usr/sbin/ntp-sync lib/firmware/IPQ5018/Data.msc; do
  # prepare.sh 的 for 列表用的是相对 $TREE/files/ 的路径，不带 files/ 前缀
  has "    $x " scripts/prepare.sh || { bad "排除名单缺 $x"; P54=0; }
done
[ "$P54" = 1 ] && ok "第 54 次：双 NTP 守护 / 重复 DHCP 防护 / QSDK 闭源固件均不会进镜像"
# nft 功能可见性（nftables 被收敛时不能静默空转）
has 'nft-missing' files/usr/sbin/l2-guard && has '无线 DHCP 防护【未生效】' files/usr/sbin/health-fix \
  && ok "nft 缺失时明确报红（health-fix 可查），防护不静默空转" \
  || { bad "缺 nft 可见性检查"; P54=0; }

# ── 第 52 次：冻结基线「只增不减」（用户：以后插件以第 51 次为准）────
# 单数据源 baseline/frozen-baseline.conf；本段逐项比对当前仓库：
#   · 基线里任何一项消失 → bad（阻断），编译期 gen-config.sh 也会 ::error:: 退出 1
#   · 仓库里出现基线外的新项 → 只提示「新增（允许）」，绝不阻断
#   · 防篡改：条目总数下限 FROZEN_MIN 硬编码，连 manifest 一起删行也拦得住
BASE=baseline/frozen-baseline.conf
FROZEN_MIN=82     # 第 51 次冻结时的有效条目数（29包+4全局+9服务+20工具+4页面+4首启+12配置）
if [ ! -f "$BASE" ]; then
  bad "🔴 缺冻结基线 $BASE（插件只增不减的唯一数据源，必须随仓库保留）"
else
  CNT=$(grep -c '^\[' "$BASE" 2>/dev/null || echo 0)
  [ "$CNT" -ge "$FROZEN_MIN" ] \
    || bad "🔴 冻结基线被删行：$CNT 项 < 下限 $FROZEN_MIN（只允许追加，禁止删除/改名/改值）"
  NF=0; MISS=0; ADDED=""
  while IFS='|' read -r kind a b c; do
    case "$kind" in
      ''|'#'*) continue ;;
      '[pkg]')
        NF=$((NF+1))
        for m in wds ap; do
          if ! grep -q "^CONFIG_PACKAGE_$a=y$" config/common.seed config/themes.seed "config/$m.seed" 2>/dev/null; then
            bad "🔴 冻结基线包丢失 [$m]：$a"; MISS=$((MISS+1)); break
          fi
        done ;;
      '[global]')
        NF=$((NF+1))
        grep -qF "$a" config/*.seed 2>/dev/null || { bad "🔴 冻结基线全局开关丢失：$a"; MISS=$((MISS+1)); } ;;
      '[initd]')
        NF=$((NF+1))
        [ -f "files/etc/init.d/$a" ] || [ -f "files.ap/etc/init.d/$a" ] \
          || { bad "🔴 冻结基线服务丢失 init.d/$a"; MISS=$((MISS+1)); } ;;
      '[sbin]')
        NF=$((NF+1))
        [ -f "files/usr/sbin/$a" ] || [ -f "files.ap/usr/sbin/$a" ] \
          || { bad "🔴 冻结基线工具丢失 usr/sbin/$a"; MISS=$((MISS+1)); } ;;
      '[www]')
        NF=$((NF+1))
        [ -f "files/$a" ] || [ -f "files.ap/$a" ] \
          || { bad "🔴 冻结基线页面丢失 $a"; MISS=$((MISS+1)); } ;;
      '[uci]')
        NF=$((NF+1))
        [ -f "files/etc/uci-defaults/$a" ] || [ -f "files.ap/etc/uci-defaults/$a" ] \
          || { bad "🔴 冻结基线首启脚本丢失 $a"; MISS=$((MISS+1)); } ;;
      '[cfg]')
        NF=$((NF+1))
        grep -qF "$b" "$a" 2>/dev/null || { bad "🔴 冻结基线配置项丢失：$a → $b"; MISS=$((MISS+1)); } ;;
      *) ;;
    esac
  done < "$BASE"
  [ "$MISS" -eq 0 ] && ok "冻结基线 $NF/$NF 项全部在位（第 51 次口径 · 只增不减）"
  # 防「连锚点一起删」：关键项即使 manifest 被整个替换也硬编码再查一遍
  [ -f files/etc/init.d/ntp-poller ] && [ -f files/usr/sbin/bridge-watchdog ] \
    && [ -f files/usr/sbin/l2-guard ] && [ -f files/usr/sbin/ntp-poller ] \
    && has 'CONFIG_PACKAGE_luci-app-ttyd=y' config/common.seed \
    && has 'CONFIG_PACKAGE_dropbear=y' config/common.seed \
    && ok "锚点复核：TTYD / SSH / l2-guard / 机器狗 / ntp-poller 均在" \
    || bad "🔴 锚点复核失败（关键插件或服务被删）"
  # 编译期闭环
  has 'frozen-baseline.conf' scripts/gen-config.sh && has 'SEED_DECL_MISS' scripts/gen-config.sh \
    && ok "gen-config 编译期读同一份基线，删 seed 声明即 ::error:: 阻断" \
    || bad "gen-config 未接入冻结基线"
  # 新增项检测：只允许增加，绝不阻断
  for d in files/etc/init.d files.ap/etc/init.d; do
    for x in "$d"/*; do
      [ -f "$x" ] || continue
      n=$(basename "$x")
      grep -qF "[initd]|$n" "$BASE" || ADDED="$ADDED initd:$n"
    done
  done
  for d in files/usr/sbin files.ap/usr/sbin; do
    for x in "$d"/*; do
      [ -f "$x" ] || continue
      n=$(basename "$x")
      grep -qF "[sbin]|$n" "$BASE" || ADDED="$ADDED sbin:$n"
    done
  done
  [ -n "$ADDED" ] && ok "基线外新增项（允许，只增不减）：$ADDED" \
    || echo "  · 暂无基线外新增项（保持 = 第 51 次基线）"
  # 第 52 次：三份「详细日志（标红）」必须随仓库保留
  for r in baseline/插件与服务冻结基线-详细日志.md \
           baseline/插件基线冻结报告.html baseline/基线摘要.log; do
    [ -s "$r" ] || bad "🔴 缺详细日志 $r"
  done
  has 'color:#d00' baseline/插件基线冻结报告.html \
    && has '🔴' baseline/插件与服务冻结基线-详细日志.md \
    && printf '\033[31m' baseline/基线摘要.log >/dev/null 2>&1 \
    && ok "三份详细日志齐全：MD 🔴 / HTML CSS 真红 / 终端 ANSI 红" \
    || bad "详细日志缺标红"
fi

# ── 第 51 次：NTP 改成「每 5 分钟循环校时一次」──────────────────
# sysntpd(busybox ntpd) 轮询间隔自适应、无 UCI 参数可钉死；
# 改用 ntp-poller：ntpd -q 单次校时 + sleep poll_interval 无限循环。
P51=1
for f in files/etc/config/system files.vs010/etc/config/system files.rax3000q/etc/config/system; do
  has "option poll_interval '300'" "$f" || { bad "$f 缺固定周期 poll_interval=300"; P51=0; }
done
[ "$P51" = 1 ] && ok "三份 system：poll_interval=300（5 分钟）"
has "option poll_interval '300'" scripts/port-overlay.sh \
  && has 'NTP_POLL="${NTP_POLL:-300}"' scripts/port-overlay.sh \
  && ok "port-overlay 产物带周期 + 编译期可覆盖" || bad "port-overlay 未同步 NTP 周期"
has '/usr/sbin/ntp-poller' files/etc/init.d/ntp-poller \
  && has 'procd_set_param command "$PROG" loop' files/etc/init.d/ntp-poller \
  && ok "ntp-poller procd 服务存在（loop 常驻）" || bad "缺 ntp-poller init.d"
for k in 'INTERVAL=300' 'sleep "$INTERVAL"' 'sleep "$RETRY"' 'ntpd -q -n -p' \
         '_ordered_servers' 'set-minutes' 'set-interval' '/proc/uptime'; do
  has "$k" files/usr/sbin/ntp-poller || { bad "ntp-poller 缺 $k"; P51=0; }
done
has 'while :; do' files/usr/sbin/ntp-poller && has '_sync' files/usr/sbin/ntp-poller \
  && ok "成功后 sleep 300 无限循环；失败 30s 重试" || bad "循环结构缺失"
if grep -qE 'ntp\.aliyun\.com|cn\.pool\.ntp\.org|time[0-9]\.cloud\.tencent\.com' files/usr/sbin/ntp-poller 2>/dev/null; then
  bad "ntp-poller 混入公网 NTP 源"; else ok "ntp-poller 仍只用两个内网源"; fi
for f in files/etc/uci-defaults/99-bridge-ready files.ap/etc/uci-defaults/99-bridge-ready \
         files/etc/rc.local files/usr/sbin/health-fix; do
  has '/etc/init.d/sysntpd disable' "$f" && has '/etc/init.d/ntp-poller enable' "$f" \
    || { bad "$f 未做 sysntpd→ntp-poller 切换"; P51=0; }
done
[ "$P51" = 1 ] && ok "首启×2 + rc.local + health-fix 四处切换，sysupgrade 保留配置也生效"
if grep -rqE '/etc/init.d/cron (enable|start)' files files.ap 2>/dev/null; then
  bad "为做 5 分钟轮询又启用了 cron（破坏干净系统/低资源）"; else ok "未启用 cron，一个 sh 循环搞定"; fi
has 'ntp_poll_minutes:' .github/workflows/build-wds.yml \
  && has 'ntp_poll_minutes:' .github/workflows/build-ap.yml \
  && has 'NTP_POLL=' scripts/prepare.sh \
  && ok "编译期可设间隔（workflow input + prepare.sh→port-overlay）" \
  || bad "编译期自定义间隔链路缺失"
for f in files/etc/banner files.ap/etc/banner; do
  has '每 5 分钟循环校时' "$f" || bad "$f 缺 NTP 周期说明"
done
has '每 5 分钟循环校时' release/RELEASE-NOTES-WDS.md \
  && has '每 5 分钟循环校时' release/RELEASE-NOTES-AP.md \
  && ok "两份 Release NOTES（独立 md）也写明 NTP 周期" || bad "Release NOTES 缺 NTP 周期"

# ── 第 46 次：qosmio 树自带坏 DTS 导致 target/linux/install 失败 ──
has '第46次裁剪' scripts/board-inject.sh \
  && has 'unicom_vs010|cmcc_rax3000q' scripts/board-inject.sh \
  && has 'TARGET_DEVICES 裁剪完成' scripts/board-inject.sh \
  && ok "board-inject 会裁剪 TARGET_DEVICES（绕开 wifi0 悬空 label）" \
  || bad "缺 TARGET_DEVICES 裁剪（会重演 wifi0 not found / world Error 2）"
if grep -q '^#include "ipq5018-nss.dtsi"' board/*.dts 2>/dev/null; then
  bad "自定义 DTS include 了 ipq5018-nss.dtsi（该文件引用不存在的 &wifi0）"
else
  ok "两台自定义 DTS 均不 include ipq5018-nss.dtsi"
fi
for f in board/ipq5018-vs010.6.12.dts board/ipq5018-rax3000q.6.12.dts; do
  has '^&wifi {' "$f" && has '^&wifi1 {' "$f" \
    && ok "$(basename "$f") 引用真实存在的 &wifi / &wifi1" \
    || bad "$(basename "$f") wifi label 异常（应为 &wifi / &wifi1，不是 &wifi0）"
done

# ── 第 45 次：编译链致命项 / 必需包误删 / 机器狗自动重启 ──
# (1) 致命：workflow 不得再用 make -s kernel_version（set -euo pipefail 下静默 exit 2）
for f in .github/workflows/build-wds.yml .github/workflows/build-ap.yml; do
  if grep -q 'make -s kernel_version' "$f"; then
    bad "$f 仍用 make -s kernel_version（会在 pipefail 下让 Prepare 静默 exit 2）"
  else
    has 'KERNEL_PATCHVER' "$f" && has 'target/linux/generic/kernel-' "$f" \
      && ok "$f 内核版本改为纯源码树读取（不再调用 make）" \
      || bad "$f 缺内核版本文件级兜底"
  fi
done
# (2) 必需包：gen-config 不再误删 TTYD / ath11k 固件
has 'REQUIRED_PKGS' scripts/gen-config.sh \
  && has '_pkg_present' scripts/gen-config.sh \
  && ok "gen-config 保留必需包、只对主题做存在性剔除" || bad "gen-config 缺第45次必需包保护"
if grep -qE 'for p in .*ath11k-firmware-ipq5018-qcn6122.*ttyd' scripts/gen-config.sh; then
  bad "gen-config 仍在探测并删除必需包"
else
  ok "必需包不在自动删除列表"
fi
# (3) 第 49 次：WDS 机器狗恢复启用 / 全参数可自定义 / 防误重启 / 防无限重启
#     用户明确要求「网桥还是要机器狗，5 分钟不通自动重启，时间可自定义」。
grep -q "^[[:space:]]*option enabled '1'" files/etc/config/wdsdog \
  && ok "WDS 机器狗默认启用（网桥要机器狗）" || bad "WDS 机器狗未启用"
grep -q "^[[:space:]]*option enabled '0'" files.ap/etc/config/wdsdog \
  && ok "AP 机器狗保持停用（刷 AP 不会自动重启）" || bad "AP 机器狗被误启用"
for kv in "option delay '5'" "option grace '6'" "option peer 'auto'" \
          "option mode 'or'" "option max_reboots '3'" "option dryrun '0'"; do
  has "$kv" files/etc/config/wdsdog || bad "WDS 机器狗缺 $kv"
done
has "option delay '5'" files/etc/config/wdsdog && ok "出厂：连续不通 5 分钟重启，宽限 6 分钟"
# 第 58 次：首启【绝不覆写用户配置】（旧版强写 7 个 uci set，把用户改的值冲掉）
has 'bridge-watchdog enable' files/etc/uci-defaults/99-bridge-ready \
  && ok "WDS 首启 enable+start（只启服务，不碰配置）" \
  || bad "WDS 首启链未启用机器狗"
if grep -qE '^[[:space:]]*uci[[:space:]]+-q[[:space:]]+set[[:space:]]+wdsdog\.' files/etc/uci-defaults/99-bridge-ready; then
  bad "WDS 首启仍在 uci set wdsdog.* 覆写用户配置（第 58 次已禁止）"
else
  ok "WDS 首启不再 uci set wdsdog.*（配置归用户）"
fi
has 'bridge-watchdog disable' files.ap/etc/uci-defaults/99-bridge-ready \
  && ok "AP 首启仍显式 stop+disable" || bad "AP 首启未停用机器狗"
if grep -qE '^[[:space:]]*uci[[:space:]]+-q[[:space:]]+set[[:space:]]+wdsdog\.' files.ap/etc/uci-defaults/99-bridge-ready; then
  bad "AP 首启仍在 uci set wdsdog.* 覆写用户配置"
else
  ok "AP 首启不再 uci set wdsdog.*（配置归用户）"
fi
# 代码级：缺省值、多判据、对端自动推导、重启上限、CLI
has 'ENABLED=$(_cfg enabled 1)' files/usr/sbin/bridge-watchdog \
  && has 'DRYRUN=$(_cfg dryrun 0)' files/usr/sbin/bridge-watchdog \
  && ok "配置丢失时也按 WDS 出厂语义（启用 / 真重启）" \
  || bad "bridge-watchdog 缺省仍回落到停用"
for fn in '_resolve_peer' '_wd_ping_ok' '_rb_count' '_rb_reset' '_maybe_reboot' 'max_reboots' 'set-anchor' 'set-max-reboots' 'set-mode' 'set-grace' 'set-interval'; do
  has "$fn" files/usr/sbin/bridge-watchdog || bad "机器狗缺 $fn"
done
has "ap)  echo '172.10.10.242'" files/usr/sbin/bridge-watchdog \
  && has "sta) echo '172.10.10.241'" files/usr/sbin/bridge-watchdog \
  && ok "peer=auto 按主备互 ping【对端】（不是 ping 自己）" \
  || bad "peer auto 推导缺失"
has '_wireless_ok "$i" && return 0' files/usr/sbin/bridge-watchdog \
  && has '_wd_ping_ok && return 0' files/usr/sbin/bridge-watchdog \
  && ok "mode=or：无线关联 / ping 对端 / ping 锚点任一通即通（防误重启）" \
  || bad "多判据 OR 缺失"
has '自动转 dryrun=1，停止重启循环' files/usr/sbin/bridge-watchdog \
  && ok "连续重启达上限自动停手（防无限重启）" || bad "缺重启次数护栏"
# 第 58 次：编译期默认【不注入】，用户自己配；input 保留但默认留空
if grep -A4 'wds_delay:' .github/workflows/build-wds.yml | grep -q "default: ''"; then
  ok "机器狗插件：workflow wds_delay 默认留空（不注入）"
else
  bad "wds_delay 默认值不是留空（第 58 次要求配置归用户）"
fi
has '编译期不注入任何参数' scripts/prepare.sh \
  && has 'package/bridge-watchdog' scripts/prepare.sh \
  && ok "prepare.sh 默认不注入参数 + 装入独立插件包" \
  || bad "prepare.sh 未插件化"
has '配置自己设' files/etc/banner \
  && has '/etc/wdsdog.conf' files/etc/banner \
  && ok "WDS banner 已改为插件说明（配置用户自设）" \
  || bad "WDS banner 仍是旧版预置文案"

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
# 第 57 次：反向判据 —— 不再把 5.4 闭源 FDT 的 ECC 值强行写进 6.12 DTS
if grep -qE '^[[:space:]]*nand-ecc-(strength|step-size)' "$DTS_V"; then
  bad "VS010 DTS 仍强行声明 NAND ECC（6.12 qcom_snand 由芯片 ID 表协商）"
else
  ok "VS010 DTS 未强行声明 NAND ECC（与官方 pz-l8 实机基线对齐）"
fi
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
if grep -qE '^[[:space:]]*nand-ecc-(strength|step-size)' "$DTS_R"; then
  bad "RAX3000Q DTS 仍强行声明 NAND ECC（第 57 次已删除）"
else
  ok "RAX3000Q DTS 未强行声明 NAND ECC（第 57 次对齐）"
fi
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
