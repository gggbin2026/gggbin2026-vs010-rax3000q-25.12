#!/bin/sh
# 第 41 次自检 · sh oem54/verify-oem54.sh（在仓库根目录跑）
ok(){ echo "    OK   $1"; }; no(){ echo "    FAIL $1"; F=1; }; F=0
# 第 48 次加固：根目录说明文档缺失只 WARN（网页上传易漏中文名），
# 其余代码/资产/脚本仍严格 FAIL。
chk(){
  case "$1" in
    README_第*次.md|README_无线修复_第41次.md|README_总包.md)
      [ -s "$1" ] && ok "$1 在位" || echo "    WARN  缺 $1（仅说明文档，不影响编译）" ;;
    *) [ -s "$1" ] && ok "$1 在位" || no "缺 $1" ;;
  esac
}
echo "════════ [1] 5.4.213 好固件资产在位 ════════"
D=3000Q-VS010-固件
for f in "$D/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cucc_vs010-squashfs-nand-factory.bin" \
         "$D/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cmcc_rax3000qy-squashfs-nand-factory.bin"; do
  [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" = 27394048 ] && ok "$(basename "$f") 27394048B" || no "缺/损坏 $f"
done
echo "════════ [2] BDF 对齐（第41次核心修复）════════"
for pair in 'board-cucc_vs010.oem54.ipq5018:4ce1ecfcca3aea1e9df230d192199690' \
            'board-cucc_vs010.oem54.qcn6122:80badcdda4502943cf89ee416cd288ca'; do
  f=${pair%%:*}; w=${pair##*:}; p=vs010/bdf/$f
  [ "$(wc -c < "$p" 2>/dev/null || echo 0)" = 131072 ] && ok "$f 131072B" || no "$f 长度异常"
  [ "$(md5sum "$p" 2>/dev/null | cut -d' ' -f1)" = "$w" ] && ok "$f MD5 对齐好固件" || no "$f MD5 不符"
done
# 旧 BDF 必须仍在（A 段硬校验依赖）
[ "$(md5sum vs010/bdf/board-cucc_vs010.ipq5018 | cut -d' ' -f1)" = c7d89771464322ea39ca290249295af9 ] && ok "旧 2.4G BDF 保留（ath11k 路径）" || no "旧 BDF 被误删"
[ "$(md5sum vs010/bdf/board-cucc_vs010.qcn6122 | cut -d' ' -f1)" = 0aadbd42dc960aefdffe09177dd275b9 ] && ok "旧 5G BDF 保留（ath11k 路径）" || no "旧 BDF 被误删"
grep -q 'board-cucc_vs010.oem54.ipq5018' diy-part2.vs010.sh && ok "diy-part2 已改用新 BDF" || no "diy-part2 未改"
grep -q '4ce1ecfcca3aea1e9df230d192199690' diy-part2.vs010.sh && ok "diy-part2 新 MD5 校验在位" || no "缺新 MD5 校验"
sh -n diy-part2.vs010.sh && ok "diy-part2 sh -n" || no "语法错"
for k in 'VS010 默认【不切】' 'VS010_CALDATA 已永久禁用' 'files/lib/firmware/IPQ5018' 'bdwlan.b10' 'bdwlan.b60' 'files/lib/firmware/ath11k' 'board-2.bin'; do
  grep -qF "$k" diy-part2.vs010.sh && ok "A段锚点 ← $k" || no "A段锚点缺 $k"
done
[ "$(grep -c 'generate-ipq-wifi-package,cucc_vs010' diy-part2.vs010.sh)" = 0 ] && ok "403 反向断言安全" || no "触发 403 断言"
echo "════════ [3] 补齐 5.4 独有 6 个固件 ════════"
for f in Data.msc fw_ini_cfg.bin regdb.bin qcn6122/Data.msc qcn6122/fw_ini_cfg.bin qcn6122/regdb.bin; do
  [ -s "files/lib/firmware/IPQ5018/$f" ] && ok "files/ ← $f" || no "缺 $f"
done
echo "════════ [4] 资产清单与叠加包 ════════"
for f in oem54/manifest/ko-list.txt oem54/manifest/fw-list.txt oem54/manifest/initd-list.txt oem54/manifest/opkg-list.txt oem54/manifest/ubi-layout.txt \
         oem54/oem-overlay.tar.gz oem54/apply-oem-overlay.sh oem54/build-oem-overlay.sh oem54/README_无线修复.md oem54/OEM_5.4.213_资产清单.md; do
  chk "$f"
done
[ "$(grep -c '\.ko' oem54/manifest/ko-list.txt)" -ge 159 ] && ok "159 个 .ko 清单" || no ".ko 清单不全"
grep -q '5.4.213 SMP preempt mod_unload ARMv7 p2v8' oem54/manifest/ko-list.txt && ok "vermagic 已登记" || no "vermagic 缺失"
[ "$(tar tzf oem54/oem-overlay.tar.gz | grep -vc '/$')" -ge 18 ] && ok "叠加包 ≥18 文件" || no "叠加包文件不足"
for k in etc/config/network etc/config/wireless etc/config/dhcp etc/config/dropbear etc/config/uhttpd etc/uci-defaults/99-bridge-ready etc/rc.local usr/sbin/dhcp-guard; do
  tar tzf oem54/oem-overlay.tar.gz | grep -q "$k" && no "危险路径进包 $k" || ok "安全 ← 未含 $k"
done
sh -n oem54/apply-oem-overlay.sh && ok "apply sh -n" || no "apply 语法错"
sh -n oem54/build-oem-overlay.sh && ok "build sh -n" || no "build 语法错"
echo "════════ [5] 真值表 / 判定工具 ════════"
T=vs010/wifi-truth.conf
for k in FW54_VS010_FILE FW54_KERNEL FW54_VERMAGIC FW54_KO_TOTAL FW54_FW_COUNT FW54_NO_ATH11K \
         BDF_54_VS010_2G BDF_54_VS010_5G BDF_54_RAX_2G BDF_54_RAX_5G BDF_54_VERDICT \
         FIX41_VERDICT_PROBE FIX41_VERDICT_CAN FIX41_VERDICT_CANT FIX41_SCOPE FIX41_TOOL; do
  grep -q "^$k=" "$T" && ok "键 ← $k" || no "缺键 $k"
done
grep -q '^VERIFIED=0' "$T" && ok "VERIFIED 保持 0" || no "VERIFIED 被改"
for k in ROOT_CAUSE STACK_COMPATIBLE CALDATA_REQUIRED EVIDENCE_BDF_MD5_2G EVIDENCE_SYNTAX_WARN REF_VS010_FW REF_VS010_ART REF_VS010_UBOOT REF_RAX_FW REF_RAX_ART ART_EVIDENCE_SOURCE WIFI_FW_PARTITION WIFI_FW_UBI_VOLUME; do
  grep -q "^$k=" "$T" && ok "A段键 ← $k" || no "A段键缺 $k"
done
grep -q '5.4.213' files/usr/sbin/wifi-stack-check && ok "wifi-stack-check 含 5.4.213 判定" || no "判定工具未更新"
echo "════════ [5b] 第 42 次：满血业务配置脚本 ════════"
for f in oem54/apply-full-config.sh oem54/README_怎么处理最好.md README_第42次.md; do
  chk "$f"
done
sh -n oem54/apply-full-config.sh && ok "apply-full-config sh -n" || no "语法错"
for k in '5.4.213' '--mode=wds' '--mode=ap' '--dry-run' '--rollback'          'qsdk-dhcp-guard' 'qsdk-rssi-guard' 'rssi_reject' 'rssi_kick'          'uci-rollback.sh' 'wireless_isolated' '不整体覆盖'; do
  grep -qF -- "$k" oem54/apply-full-config.sh && ok "锚点 ← $k" || no "缺锚点 $k"
done
# dry-run 必须完全只读：文件里 mkdir 只能在 dry-run 分支之后
python3 - <<'PYV'
import pathlib,re,sys
s=pathlib.Path('oem54/apply-full-config.sh').read_text()
i_dry=s.find('if [ "$DRY" = 1 ]'); i_mk=s.find('mkdir -p "$BK"')
if i_dry<0 or i_mk<0 or i_mk<i_dry:
    print('    FAIL dry-run 之前就有 mkdir（dry-run 不是只读）'); sys.exit(1)
print('    OK   dry-run 分支在 mkdir 之前（完全只读）')
PYV
[ $? = 0 ] || F=1
for f in oem54/README_无线修复.md oem54/OEM_5.4.213_资产清单.md README_无线修复_第41次.md README_总包.md; do
  grep -qF "$f" .github/workflows/build-oem-bundle.yml && ok "bundle 含 $f" || no "bundle 漏 $f"
done
grep -q 'apply-full-config.sh' .github/workflows/build-oem-bundle.yml && ok "bundle 含 apply-full-config.sh" || no "bundle 漏配置脚本"
echo "════════ [5c] 第 43 次：源码树调研纠错 + PC 端一键配置 ════════"
for f in oem54/源码树调研报告.md oem54/PC端一键配置.py README_第43次.md; do
  chk "$f"
done
python3 -m py_compile oem54/PC端一键配置.py 2>/dev/null && ok "PC端一键配置.py py_compile" || no "py_compile 失败"
rm -rf oem54/__pycache__
python3 oem54/PC端一键配置.py --ip 127.0.0.1 --mode wds --dry-run >/tmp/pc43.log 2>&1 \
  && grep -q 'apply-full-config.sh' /tmp/pc43.log && ok "PC 脚本 dry-run 输出完整" || no "PC 脚本 dry-run 异常"
for k in '标准 UBI CRC' '~zlib.crc32' '06e00000' 'qca-networking-2022-spf-12-2' '404' '25.12-nss' 'RESULT: PASS' '217 PEB'; do
  grep -qF -- "$k" oem54/源码树调研报告.md && ok "调研报告锚点 ← $k" || no "调研报告缺 $k"
done
# 旧错误结论必须已清除
for f in oem54/README_怎么处理最好.md FIRMWARE.md; do
  grep -q '418/418 mismatch' "$f" && no "$f 仍残留错误 CRC 结论" || ok "$f 错误结论已更正"
done
grep -qF 'PC端一键配置.py' .github/workflows/build-oem-bundle.yml && ok "bundle 含 PC 脚本" || no "bundle 漏 PC 脚本"
grep -qF '源码树调研报告.md' .github/workflows/build-oem-bundle.yml && ok "bundle 含调研报告" || no "bundle 漏调研报告"
echo "════════ [5d] 第 43 次：满血融合固件（4 件）════════"
for f in oem54/build-fused.py oem54/build-fused.sh oem54/verify-fused.py \
         .github/workflows/build-fused.yml; do
  chk "$f"
done
sh -n oem54/build-fused.sh && ok "build-fused.sh sh -n" || no "语法错"
python3 -m py_compile oem54/build-fused.py oem54/verify-fused.py 2>/dev/null \
  && ok "两个 .py py_compile" || no "py_compile 失败"
rm -rf oem54/__pycache__
grep -qF 'build-fused.sh --all' .github/workflows/build-fused.yml && ok "CI 含生成步骤" || no "CI 缺生成步骤"
grep -qF 'verify-fused.py' .github/workflows/build-fused.yml && ok "CI 含严格验证" || no "CI 缺验证"
# fused/ 若随包提供则逐个严格验证；不随包提供时提示可由 CI 重建
D=3000Q-VS010-固件
VS=$D/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cucc_vs010-squashfs-nand-factory.bin
RAX=$D/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cmcc_rax3000qy-squashfs-nand-factory.bin
NF=0
for spec in "fused/Nwrt-FUSED-5.4.213-20261124-cucc_vs010-wds-squashfs-nand-factory.bin:$VS:wds:VS010" \
            "fused/Nwrt-FUSED-5.4.213-20261124-cucc_vs010-ap-squashfs-nand-factory.bin:$VS:ap:VS010" \
            "fused/Nwrt-FUSED-5.4.213-20261124-cmcc_rax3000qy-wds-squashfs-nand-factory.bin:$RAX:wds:RAX3000Q" \
            "fused/Nwrt-FUSED-5.4.213-20261124-cmcc_rax3000qy-ap-squashfs-nand-factory.bin:$RAX:ap:RAX3000Q"; do
  IFS=: read -r f r m d <<EOF
$spec
EOF
  if [ -s "$f" ]; then
    if python3 oem54/verify-fused.py "$f" "$r" "$m" "$d" >/tmp/vf43.log 2>&1; then
      ok "融合固件 PASS ← $(basename "$f")"; NF=$((NF+1))
    else
      no "融合固件 FAIL ← $(basename "$f")"; tail -6 /tmp/vf43.log
    fi
  fi
done
[ "$NF" = 0 ] && echo "    INFO 本包未随附 fused/ 二进制（CI 或 sh oem54/build-fused.sh --all 可重建）"
[ "$NF" = 4 ] && ok "4/4 融合固件全部严格验证 PASS"
echo "════════ [6] 打包 workflow / 编译树安全 ════════"
[ -s .github/workflows/build-oem-bundle.yml ] && ok "build-oem-bundle.yml 在位" || no "缺 workflow"
n=$(find files files.ap -name '*.ko' 2>/dev/null | wc -l); [ "$n" = 0 ] && ok "编译树 .ko 数 = 0" || no "编译树混入 $n 个 .ko"
sh check-workflows.sh >/tmp/cw41.log 2>&1 && ok "check-workflows.sh PASS" || { no "check-workflows.sh FAIL"; tail -12 /tmp/cw41.log; }
echo "════════ [7] 既有守卫 ════════"
sh verify-all-39.sh >/tmp/v39.log 2>&1 && ok "verify-all-39.sh PASS" || { no "39 FAIL"; tail -8 /tmp/v39.log; }
sh verify-stack-fix.sh >/tmp/v40.log 2>&1 && ok "verify-stack-fix.sh PASS" || { no "40 FAIL"; tail -8 /tmp/v40.log; }
sh vs010/verify-oem-assets.sh --root "$(pwd)" --json >/tmp/o41.json 2>/dev/null
grep -q '"live_fix":1' /tmp/o41.json && ok "verify-oem-assets live_fix=1" || no "live_fix 异常"
echo
[ "$F" = 0 ] && echo "RESULT: PASS —— 第 41 次（5.4.213 好固件实证 / BDF 对齐 / 满血路径）就位" || echo "RESULT: FAIL"
exit $F
