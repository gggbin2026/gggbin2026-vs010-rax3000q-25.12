#!/usr/bin/env python3
'''把 02_network.inc 的两个 case 分支插入 02_network 的 case 语句内。
兼容 `cmcc,pz-l8|` 这类续行写法：找第一个以 ')' 结尾的 case 模式行，插在它前面。
'''
import sys, pathlib
net = pathlib.Path(sys.argv[1])
inc = pathlib.Path(sys.argv[2]).read_text()
lines = net.read_text().splitlines()
idx = None
for i, l in enumerate(lines):
    s = l.strip()
    if s.endswith(')') and not s.startswith('#') and 'case' not in s and 'esac' not in s:
        idx = i
        break
if idx is None:
    # 兜底：找 "case" 后的第一行模式
    for i, l in enumerate(lines):
        if l.strip().startswith('case ') or 'boardname' in l and 'in' in l:
            idx = i + 1
            break
if idx is None:
    sys.stderr.write('[02_network] 找不到 case 锚点，跳过注入（运行期 bridge-netfix 会兜底）\n')
    sys.exit(0)
lines[idx:idx] = inc.rstrip('\n').splitlines()
net.write_text('\n'.join(lines) + '\n')
print('[02_network] 已在第 %d 行前插入两个机型分支' % (idx + 1))
