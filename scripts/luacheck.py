#!/usr/bin/env python3
"""极简 Lua 词法护栏：字符串内裸换行、引号/括号未闭合。
   r29.6 教训：字符串里一个裸换行会让 controller require 失败 → 整个后台 500。
"""
import sys, pathlib

PAIRS = {')': '(', ']': '[', '}': '{'}

def check(p):
    s = p.read_text(encoding='utf-8')
    errs = []
    i = 0; n = len(s); line = 1; stack = []; state = 'code'; q = ''
    while i < n:
        c = s[i]; nxt = s[i + 1] if i + 1 < n else ''
        if c == '\n':
            if state in ('str',):
                errs.append('%s:%d 字符串内裸换行（Lua unfinished string）' % (p, line))
                state = 'code'
            line += 1
        if state == 'code':
            if c == '-' and nxt == '-':
                j = s.find('\n', i)
                if j < 0:
                    break
                i = j
                continue
            if c in ('"', "'"):
                state = 'str'; q = c
            elif c == '[' and nxt == '[':
                state = 'lstr'; i += 1
            elif c in '([{':
                stack.append((c, line))
            elif c in ')]}':
                if not stack or stack[-1][0] != PAIRS[c]:
                    errs.append('%s:%d 括号不配对 %s' % (p, line, c))
                else:
                    stack.pop()
        elif state == 'str':
            if c == '\\':
                i += 1
            elif c == q:
                state = 'code'
        elif state == 'lstr':
            if c == ']' and nxt == ']':
                state = 'code'; i += 1
        i += 1
    if state != 'code':
        errs.append('%s 结尾字符串未闭合' % p)
    if stack:
        errs.append('%s 结尾括号未闭合 %s' % (p, stack[-3:]))
    return errs

bad = []
for a in sys.argv[1:]:
    bad += check(pathlib.Path(a))
if bad:
    print('\n'.join(bad))
    sys.exit(1)
print('luacheck OK')
