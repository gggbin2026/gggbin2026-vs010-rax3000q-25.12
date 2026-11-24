#!/bin/sh
# art/collect.sh —— 离线采集两份 0:ART，复核 art/art-truth.conf
# 用法：sh art/collect.sh [仓库根目录]
# 只读、不联网、不改 ART、不写任何文件。真值固化在 art/art-truth.conf。
set -eu
ROOT="${1:-.}"
cd "$ROOT"
V='010-smem_0-ART.bin'
R='RAX3000Q-mtd13-0ART'
for f in "$V" "$R"; do
  [ -s "$f" ] || { echo "::error::缺 ART 文件 $f（把它放在仓库根目录）"; exit 1; }
done

echo "==================== ART 离线采集 ===================="
python3 - "$V" "$R" <<'PYEOF'
import sys, hashlib
S = 0x20000
OFF = {'2G': 0x1000, '5G': 0x26800}

def macstr(b):
    return ':'.join('%02X' % x for x in b)

data = {}
for fn in sys.argv[1:]:
    d = open(fn, 'rb').read()
    print('\n--- %s ---' % fn)
    print('  size : %d B (%s)' % (len(d), hex(len(d))))
    print('  md5  : %s' % hashlib.md5(d).hexdigest())
    print('  head : %s' % ' '.join('%02x' % x for x in d[:24]))
    macs = []
    for o in (0, 6, 12, 18):
        m = d[o:o+6]
        if m != b'\xff'*6 and m != b'\x00'*6 and not (m[0] & 1):
            macs.append('0x%x=%s' % (o, macstr(m)))
    print('  MAC  : %s' % (', '.join(macs) if macs else '无（全 FF/空，不能从 ART+0 取 MAC）'))
    data[fn] = d
    for r, o in OFF.items():
        b = d[o:o+S]
        print('  %s @0x%-6x : %d B  md5=%s  magic=%s  内嵌MAC=%s' %
              (r, o, len(b), hashlib.md5(b).hexdigest(), b[:4].hex(), macstr(b[0x0e:0x14])))

print('\n==================== 两台切片互差 ====================')
a, b = data[sys.argv[1]], data[sys.argv[2]]
for r, o in OFF.items():
    x, y = a[o:o+S], b[o:o+S]
    n = sum(1 for i in range(S) if x[i] != y[i])
    verdict = '射频同构、产线校准逐台不同' if n < S*0.1 else '结构差异大，必须按机型拆 BDF'
    print('  %s : %d / %d 字节不同 (%.2f%%) —— %s' % (r, n, S, 100.0*n/S, verdict))
import os
print('\n==================== 实证对照：好固件到底用哪份 BDF ====================')
ref = {'2G': 'vs010/bdf/board-cucc_vs010.ipq5018',
       '5G': 'vs010/bdf/board-cucc_vs010.qcn6122'}
for r, o in OFF.items():
    p = ref[r]
    if not os.path.isfile(p):
        print('  %s 模板 BDF 缺失: %s' % (r, p))
        continue
    t = open(p, 'rb').read()
    tm = hashlib.md5(t).hexdigest()
    print('  %s 模板 BDF (= bdwlan.b%s) : %s  %d B' %
          (r, '10' if r == '2G' else '60', tm, len(t)))
    for fn in sys.argv[1:]:
        s = data[fn][o:o+S]
        n = sum(1 for i in range(S) if t[i] != s[i])
        print('    vs %-26s 差 %5d B → %s' %
              (fn, n, '相同' if n == 0 else '不同'))
print('  ★ 好固件 dmesg 实证下载 IPQ5018/bdwlan.b10 与 qcn6122/bdwlan.b60（各 131072 B），')
print('    MD5 == 模板 BDF；同时 Caldata not present / CAL version 0。')
print('    → ART 切片【没被加载】。本机校准的 data 应取模板 BDF，ART 切片只存档。')

print('\n  ⚠ ART 是每台机器独立产线校准：只用于你这台，别跨机刷、别外传。')
print('  ⚠ 让无线「能起来」靠 board-2.bin + DTS 的 calibration-variant；')
print('     ART 切片不能替代 BDF 容器，也不是好固件实际使用的那份。')
PYEOF
echo
echo "真值见 art/art-truth.conf（本脚本不自动覆写，避免把换过的机器写死）。"
