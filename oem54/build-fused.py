#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第 43 次 · 产物级融合固件构建器
────────────────────────────────────────────────────────────────────
以 NWRT QSDK12.2 / 5.4.213 官方 factory.bin 为底座：
  · kernel FIT 卷（闭源无线 + NSS 驱动所在的内核）原样保留
  · rootfs squashfs 解包 → 注入仓库定制 → 重新打包
  · 按原镜像完全相同的 UBI 字节布局重建（EC/VID/卷表 CRC 用已实证的标准算法）
  · rootfs 卷按需扩 LEB（mtd15 rootfs 分区 110MB，镜像仅 26MB，余量充足）
  · 不碰 ART / 分区表 / 内核 / 驱动 / BDF

用法：
  python3 build-fused.py <官方factory.bin> <注入目录> <输出factory.bin> [--mode=wds|ap] [--model=VS010|RAX3000Q]

UBI 头事实（逐字节实测 418/418 校验通过）：
  hdr_crc = zlib.crc32(data) ^ 0xFFFFFFFF   （Linux kernel crc32(~0,...) 无 final xor）
  EC 头  : magic@0 version@4 ec@8 vid_hdr_offset@16(2048) data_offset@20(4096) image_seq@24 crc@60
  VID 头 : magic@0 version@4 vol_type@5 copy_flag@6 compat@7 vol_id@8 lnum@12
           data_size@20 used_ebs@24 data_pad@28 data_crc@32 sqnum@40 crc@60
  本镜像 VID 的 data_size/data_crc/sqnum 全为 0（NWRT factory 扁平布局），
  因此替换数据区不影响任何 CRC —— 这是能安全重打包的关键。
  卷表记录步长 172：reserved_pebs@0 alignment@4 data_pad@8 vol_type@12
           upd_marker@13 name_len@14 name@16(128) flags@144 crc@168
"""
import sys, os, struct, zlib, math, pathlib, hashlib, subprocess, shutil, tempfile

PEB = 131072
VID_OFF = 2048
DATA_OFF = 4096
LEB = PEB - DATA_OFF          # 126976
VTBL_STRIDE = 172
LAYOUT_VID = 0x7fffefff       # 本镜像实测（非标准 0x7fffffff）
CRC = lambda d: (zlib.crc32(d) & 0xffffffff) ^ 0xffffffff

def log(*a): print('[fused]', *a, flush=True)
def die(*a): print('::error::', *a, flush=True); sys.exit(1)

def parse_image(path):
    b = pathlib.Path(path).read_bytes()
    if len(b) % PEB: die('镜像大小不是 PEB 倍数', len(b))
    pebs = []
    for i in range(len(b) // PEB):
        p = b[i*PEB:(i+1)*PEB]
        ec = p[:64]; vid = p[VID_OFF:VID_OFF+64]
        if ec[:4] != b'UBI#': die('PEB %d 无 EC 头' % i)
        if vid[:4] != b'UBI!': die('PEB %d 无 VID 头' % i)
        if struct.unpack_from('>I', ec, 60)[0] != CRC(ec[:60]): die('PEB %d EC crc 不符' % i)
        if struct.unpack_from('>I', vid, 60)[0] != CRC(vid[:60]): die('PEB %d VID crc 不符' % i)
        pebs.append({
            'idx': i, 'ec': ec, 'vid': vid,
            'vol': struct.unpack_from('>I', vid, 8)[0],
            'lnum': struct.unpack_from('>I', vid, 12)[0],
            'data': p[DATA_OFF:],
        })
    return b, pebs

def make_vid(template, lnum):
    v = bytearray(template)
    struct.pack_into('>I', v, 12, lnum)
    struct.pack_into('>I', v, 60, CRC(bytes(v[:60])))
    return bytes(v)

def patch_vtbl(leb_data, new_reserved):
    """把 rootfs 记录的 reserved_pebs 改大，重算记录 crc；两个 layout 副本都改"""
    d = bytearray(leb_data)
    found = False
    for off in range(0, VTBL_STRIDE * 8, VTBL_STRIDE):
        r = d[off:off+172]
        if len(r) < 172: break
        nl = struct.unpack_from('>H', r, 14)[0]
        if nl == 0 or nl > 127: continue
        name = bytes(r[16:16+nl]).decode('latin1', 'replace')
        if name == 'rootfs':
            old = struct.unpack_from('>I', r, 0)[0]
            struct.pack_into('>I', d, off, new_reserved)
            struct.pack_into('>I', d, off+168, CRC(bytes(d[off:off+168])))
            log('  卷表 rootfs reserved_pebs: %d → %d' % (old, new_reserved))
            found = True
            break
    if not found: die('卷表里找不到 rootfs 记录')
    return bytes(d)

def inject_rootfs(orig_sqfs, inject_dir, out_sqfs):
    tmp = tempfile.mkdtemp(prefix='fused-root-')
    try:
        r = subprocess.run(['unsquashfs', '-d', tmp, '-f', orig_sqfs],
                           capture_output=True, text=True)
        n0 = sum(1 for _ in pathlib.Path(tmp).rglob('*') if _.is_file())
        # 非 root 环境下 unsquashfs 无法创建 /dev/console 字符设备，会返回非 0；
        # 只要文件都解出来了就继续，设备节点稍后用 mksquashfs 伪文件补回。
        if n0 < 2000:
            die('unsquashfs 解包不完整 (%d 文件):' % n0, r.stdout[-800:], r.stderr[-800:])
        if r.returncode:
            log('  unsquashfs 非致命告警（设备节点跳过）：%s' %
                (r.stderr.strip().splitlines()[-1] if r.stderr.strip() else 'rc=%d' % r.returncode))
        # 复制注入树（保留目录结构）
        src = pathlib.Path(inject_dir)
        nadd = 0
        for p in src.rglob('*'):
            if p.is_file():
                rel = p.relative_to(src)
                dst = pathlib.Path(tmp) / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(p, dst)
                nadd += 1
        log('  rootfs 原 %d 文件，注入 %d 个' % (n0, nadd))
        # 与官方 superblock 对齐：squashfs4 / xz / blocksize 262144 / uid=gid=1000
        # -p 补回官方 rootfs 的 /dev/console（字符设备 5:1，600）；
        # -force-uid/gid 1000 保持官方 rootfs 的 owner（沙盒里 unsquashfs 无法保留 uid）。
        cmd = ['mksquashfs', tmp, out_sqfs, '-comp', 'xz', '-b', '262144',
               '-noappend', '-no-progress', '-force-uid', '1000', '-force-gid', '1000',
               '-p', 'dev/console c 600 1000 1000 5 1']
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode: die('mksquashfs 失败:', r.stdout[-1200:], r.stderr[-1200:])
        sz = pathlib.Path(out_sqfs).stat().st_size
        log('  新 squashfs = %d B (%.2f MB) → 需要 %d 个 LEB' % (sz, sz/1048576, math.ceil(sz/LEB)))
        return sz
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def build(src, inject_dir, out, mode, model):
    b, pebs = parse_image(src)
    log('源镜像: %s  %d B / %d PEB' % (pathlib.Path(src).name, len(b), len(pebs)))
    vols = {}
    for p in pebs: vols.setdefault(p['vol'], []).append(p)
    log('卷分布: %s' % {hex(k): len(v) for k, v in vols.items()})
    if 0 not in vols or 1 not in vols: die('缺 kernel/rootfs 卷')
    kernel = sorted(vols[0], key=lambda x: x['lnum'])
    rootfs = sorted(vols[1], key=lambda x: x['lnum'])
    layout = sorted(vols.get(LAYOUT_VID, []), key=lambda x: x['lnum'])
    if not layout: die('缺 layout 卷')
    if [p['lnum'] for p in rootfs] != list(range(len(rootfs))): die('rootfs lnum 不连续')

    # 1) 抽出原 rootfs squashfs（拼 LEB）
    tmpd = tempfile.mkdtemp(prefix='fused-raw-')
    orig_sqfs = os.path.join(tmpd, 'orig.sqfs')
    new_sqfs = os.path.join(tmpd, 'new.sqfs')
    with open(orig_sqfs, 'wb') as f:
        for p in rootfs: f.write(p['data'])
    # 官方 squashfs 真实长度（superblock bytes_used）
    with open(orig_sqfs, 'r+b') as f:
        raw = f.read()
    used = struct.unpack_from('<Q', raw, 40)[0]  # squashfs superblock bytes_used @40
    log('  原 squashfs bytes_used = %d B' % used)

    # 2) 注入定制并重打包
    inject_rootfs(orig_sqfs, inject_dir, new_sqfs)
    ns = pathlib.Path(new_sqfs).read_bytes()
    nleb = math.ceil(len(ns) / LEB)
    new_lebs = []
    for i in range(nleb):
        chunk = ns[i*LEB:(i+1)*LEB]
        if len(chunk) < LEB:
            chunk += b'\xff' * (LEB - len(chunk))
        new_lebs.append(chunk)
    assert all(len(c) == LEB for c in new_lebs)

    # 3) 卷表：reserved_pebs 扩到 nleb（两个副本）
    layout_out = [patch_vtbl(p['data'], max(nleb, len(rootfs))) for p in layout]

    # 4) 组装新镜像
    ec_tpl = rootfs[0]['ec']
    vid_tpl = rootfs[0]['vid']
    outb = bytearray()
    def emit(ec, vid, data):
        assert len(ec) == 64 and len(vid) == 64 and len(data) == LEB
        peb = bytearray(b'\xff' * PEB)
        peb[0:64] = ec
        peb[VID_OFF:VID_OFF+64] = vid
        peb[DATA_OFF:] = data
        return bytes(peb)

    # ── 第 45 次纠错：严格按【原镜像物理 PEB 顺序】输出 ──────────────
    # 官方 NWRT factory 布局实测：PEB 0..1 = layout 卷表，2..33 = kernel FIT，
    # 34..208 = rootfs。第 43/44 次错误地按 kernel→rootfs→layout 重排，
    # 把卷表挪到末尾、kernel 挪到 PEB0。UBI 规范虽靠 EC/VID 头识别卷，
    # 但 QSDK U-Boot / nand write / sysupgrade 常按固定偏移读卷表与 FIT，
    # 挪位后可能沿用 flash 上旧卷表 → 实际挂载旧 rootfs（表现为「刷完没变动」）。
    # 现在：layout 与 kernel 的物理位置与官方逐字节同位，只在末尾扩 rootfs。
    orig_order = sorted(pebs, key=lambda x: x['idx'])
    head_layout = [p for p in orig_order if p['vol'] == LAYOUT_VID]
    head_kernel = [p for p in orig_order if p['vol'] == 0]
    assert len(head_layout) == len(layout) and len(head_kernel) == len(kernel)
    # ① layout 卷：原头 + 改过的卷表数据（仍在 PEB 0..1）
    for i, p in enumerate(head_layout):
        outb += emit(p['ec'], p['vid'], layout_out[i][:LEB].ljust(LEB, b'\xff'))
    # ② kernel 卷原样（连数据区一起，仍在 PEB 2..33）
    for p in head_kernel: outb += emit(p['ec'], p['vid'], p['data'])
    # ③ rootfs 卷：新数据；前 len(rootfs) 个复用原 EC/VID 头，追加的用模板
    for i, data in enumerate(new_lebs):
        if i < len(rootfs):
            ec, vid = rootfs[i]['ec'], rootfs[i]['vid']
        else:
            ec, vid = ec_tpl, make_vid(vid_tpl, i)
        outb += emit(ec, vid, data)
    outp = pathlib.Path(out)
    outp.write_bytes(bytes(outb))
    log('输出: %s  %d B / %d PEB (%.2f MB)' % (outp.name, len(outb), len(outb)//PEB, len(outb)/1048576))

    # 5) 自检：用同一解析器回读
    _, chk = parse_image(out)
    cv = {}
    for p in chk: cv.setdefault(p['vol'], []).append(p)
    assert len(cv[0]) == len(kernel), 'kernel 卷 LEB 数变化'
    assert len(cv[1]) == nleb, 'rootfs 卷 LEB 数不对'
    assert [x['lnum'] for x in sorted(cv[1], key=lambda a:a['lnum'])] == list(range(nleb))
    assert len(cv[LAYOUT_VID]) == len(layout)
    # 第 45 次：物理位置必须与官方一致（layout/kernel 不挪位）
    orig_seq = [(p['vol'], p['lnum']) for p in sorted(pebs, key=lambda x: x['idx'])
                if p['vol'] in (0, LAYOUT_VID)]
    new_seq = [(p['vol'], p['lnum']) for p in sorted(chk, key=lambda x: x['idx'])
               if p['vol'] in (0, LAYOUT_VID)]
    if orig_seq != new_seq:
        die('layout/kernel 卷物理位置被挪动，禁止出包')
    log('  ✓ layout/kernel 卷物理 PEB 位置与官方逐位一致（未挪位）')
    # squashfs 可解、注入文件在位
    joined = b''.join(x['data'] for x in sorted(cv[1], key=lambda a:a['lnum']))
    probe = os.path.join(tmpd, 'probe.sqfs')
    pathlib.Path(probe).write_bytes(joined)
    r = subprocess.run(['unsquashfs', '-ll', probe, '/usr/sbin/wifi-stack-check'],
                       capture_output=True, text=True)
    if 'wifi-stack-check' not in (r.stdout + r.stderr):
        die('新 squashfs 里找不到注入文件')
    log('  ✓ 回读自检通过：所有 EC/VID CRC 有效、卷 LEB 连续、注入文件可读')
    log('  ✓ kernel FIT 卷逐 PEB 原样保留（5.4.213 内核 / 闭源驱动 / NSS 未动）')
    shutil.rmtree(tmpd, ignore_errors=True)
    return {'size': len(outb), 'pebs': len(outb)//PEB, 'rootfs_lebs': nleb,
            'sha256': hashlib.sha256(bytes(outb)).hexdigest()}

if __name__ == '__main__':
    a = sys.argv[1:]
    if len(a) < 3: die(__doc__)
    mode = next((x.split('=')[1] for x in a if x.startswith('--mode=')), 'wds')
    model = next((x.split('=')[1] for x in a if x.startswith('--model=')), 'VS010')
    build(a[0], a[1], a[2], mode, model)
