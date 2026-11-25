#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第 43 次 · 融合固件严格验证（对每个 factory.bin 独立跑）"""
import sys, os, struct, zlib, pathlib, subprocess, tempfile, shutil, hashlib
PEB=131072; VID_OFF=2048; DATA_OFF=4096; LEB=126976; VTBL=172
LAYOUT=0x7fffefff
CRC=lambda d:(zlib.crc32(d)&0xffffffff)^0xffffffff
F=0
def ok(s): print('    OK   '+s)
def no(s): global F; print('    FAIL '+s); F=1
def die(s): print('::error:: '+s); sys.exit(1)

def parse(p):
    b=pathlib.Path(p).read_bytes()
    if len(b)%PEB: die('大小非 PEB 倍数')
    out=[]
    for i in range(len(b)//PEB):
        peb=b[i*PEB:(i+1)*PEB]
        ec,vid=peb[:64],peb[VID_OFF:VID_OFF+64]
        if ec[:4]!=b'UBI#' or vid[:4]!=b'UBI!': die('PEB%d 缺头'%i)
        if struct.unpack_from('>I',ec,60)[0]!=CRC(ec[:60]): die('PEB%d EC crc'%i)
        if struct.unpack_from('>I',vid,60)[0]!=CRC(vid[:60]): die('PEB%d VID crc'%i)
        out.append({'ec':ec,'vid':vid,'vol':struct.unpack_from('>I',vid,8)[0],
                    'lnum':struct.unpack_from('>I',vid,12)[0],'data':peb[DATA_OFF:]})
    return b,out

def squashfs_of(pebs,vol=1):
    d=b''.join(x['data'] for x in sorted([p for p in pebs if p['vol']==vol],key=lambda a:a['lnum']))
    return d

def extract_one(sqfs_bytes,rel,outdir):
    """从内存里的 squashfs 抽一个文件"""
    tmp=tempfile.mkdtemp(prefix='vf-',dir='/tmp')
    try:
        p=pathlib.Path(tmp)/'img.sqfs'; p.write_bytes(sqfs_bytes)
        subprocess.run(['unsquashfs','-d',outdir,'-f',str(p),rel],
                       capture_output=True,text=True)
        return pathlib.Path(outdir)/rel.lstrip('/')
    finally:
        shutil.rmtree(tmp,ignore_errors=True)

def main(fw,ref,mode,model):
    global F
    print('\n════════ %s ════════'%pathlib.Path(fw).name)
    b,pebs=parse(fw); rb,rpebs=parse(ref)
    vols={}
    for p in pebs: vols.setdefault(p['vol'],[]).append(p)
    rvols={}
    for p in rpebs: rvols.setdefault(p['vol'],[]).append(p)
    # 1 结构
    if len(b)//PEB==217: ok('217 PEB / %.2f MB（< rootfs 分区 110MB）'%(len(b)/1048576))
    else: no('PEB 数异常 %d'%(len(b)//PEB))
    if [x['lnum'] for x in sorted(vols[1],key=lambda a:a['lnum'])]==list(range(len(vols[1]))): ok('rootfs LEB 连续 0..%d'%(len(vols[1])-1))
    else: no('rootfs lnum 不连续')
    if len(vols[0])==len(rvols[0])==32: ok('kernel 卷 32 LEB')
    else: no('kernel 卷数 '+str(len(vols[0])))
    # 2 kernel FIT 逐字节
    k_new=b''.join(x['data'] for x in sorted(vols[0],key=lambda a:a['lnum']))
    k_ref=b''.join(x['data'] for x in sorted(rvols[0],key=lambda a:a['lnum']))
    if k_new==k_ref: ok('kernel FIT 与原官方固件逐字节一致（5.4.213 内核/闭源驱动/NSS 全部原样）')
    else: no('kernel FIT 被改动！')
    # 3 卷表
    lay=sorted(vols[LAYOUT],key=lambda a:a['lnum'])
    found=False
    for off in range(0,VTBL*8,VTBL):
        r=lay[0]['data'][off:off+172]
        nl=struct.unpack_from('>H',r,14)[0]
        if nl and bytes(r[16:16+nl])==b'rootfs':
            rp=struct.unpack_from('>I',r,0)[0]
            crc=struct.unpack_from('>I',r,168)[0]
            if rp>=len(vols[1]): ok('卷表 rootfs reserved_pebs=%d ≥ 实际 %d'%(rp,len(vols[1])))
            else: no('卷表 reserved_pebs %d < %d'%(rp,len(vols[1])))
            if crc==CRC(lay[0]['data'][off:off+168]): ok('卷表记录 CRC 有效')
            else: no('卷表记录 CRC 错误')
            found=True; break
    if not found: no('卷表无 rootfs 记录')
    if len(lay)==2 and lay[0]['data'][:172]==lay[1]['data'][:172]: ok('卷表两个副本一致')
    else: no('卷表副本不一致')
    # 4 rootfs 完整性：官方关键文件逐字节
    sq_new=squashfs_of(pebs); sq_ref=squashfs_of(rpebs)
    tmp=tempfile.mkdtemp(prefix='vf-root-',dir='/tmp')
    p=pathlib.Path(tmp)/'a.sqfs'; p.write_bytes(sq_new)
    subprocess.run(['unsquashfs','-d',tmp+'/new','-f',str(p)],capture_output=True)
    p2=pathlib.Path(tmp)/'b.sqfs'; p2.write_bytes(sq_ref)
    subprocess.run(['unsquashfs','-d',tmp+'/old','-f',str(p2)],capture_output=True)
    N,O=pathlib.Path(tmp)/'new',pathlib.Path(tmp)/'old'
    keys=['lib/modules/5.4.213/qca_ol.ko','lib/modules/5.4.213/umac.ko',
          'lib/modules/5.4.213/ipq_cnss2.ko','lib/modules/5.4.213/wifi_3_0.ko',
          'lib/modules/5.4.213/qca-nss-drv.ko','lib/modules/5.4.213/qca-ssdk.ko',
          'lib/modules/5.4.213/ecm.ko','lib/modules/5.4.213/cfg80211.ko',
          'lib/firmware/IPQ5018/bdwlan.b10','lib/firmware/IPQ5018/qcn6122/bdwlan.b60',
          'lib/firmware/IPQ5018/q6_fw.mdt','lib/firmware/IPQ5018/qcn6122/regdb.bin',
          'etc/config/dropbear','usr/sbin/dropbear','usr/sbin/wlanconfig',
          'usr/sbin/wifitool','etc/init.d/load_cnss2','etc/init.d/qca-nss-drv']
    def same_file(a,c):
        # dropbear / wlanconfig / wifitool 在官方 rootfs 里是符号链接，
        # 比较链接目标字符串；普通文件才比字节。
        if a.is_symlink() or c.is_symlink():
            return a.is_symlink() and c.is_symlink() and os.readlink(a)==os.readlink(c)
        return a.is_file() and c.is_file() and a.read_bytes()==c.read_bytes()
    same=0
    for k in keys:
        if same_file(N/k,O/k): same+=1
        else: no('官方关键文件被改/缺失: '+k)
    ok('官方 %d/%d 个关键驱动/固件/服务逐字节未变'%(same,len(keys)))
    # 固件总数
    nfw=len(list((N/'lib/firmware/IPQ5018').rglob('*')))
    nfw=[x for x in (N/'lib/firmware/IPQ5018').rglob('*') if x.is_file()]
    # VS010 好固件 58 个（独有 q6_fw.b22/b23/b25/b26）；RAX3000Q 好固件 54 个
    expect = 58 if model=='VS010' else 54
    if len(nfw)>=expect: ok('官方 %d 个无线固件在位（实测 %d）'%(expect,len(nfw)))
    else: no('无线固件只有 %d 个，应为 %d'%(len(nfw),expect))
    # 5 注入文件
    inj=['usr/sbin/wifi-stack-check','usr/sbin/qsdk-dhcp-guard','usr/sbin/qsdk-rssi-guard',
         'etc/config/qsdk-guard','etc/init.d/qsdk-guard','etc/init.d/oem54-firstboot',
         'etc/firmware_mode','usr/lib/oem54/apply-full-config.sh',
         'usr/lib/oem54/oem-overlay.tar.gz','usr/sbin/health-fix']
    if mode=='wds':
        inj+=['www/bridge/index.html','www/cgi-bin/bridge']
    else:
        inj+=['www/ap/index.html','www/cgi-bin/apstatus','www/bridge/index.html']
    # 第 44 次：自动一主一备 / 机器狗 / 网口守护 / 双栈 CGI 适配
    inj44=['usr/lib/oem54/qsdk-wifi.sh','usr/sbin/qsdk-nic-guard',
           'usr/sbin/qsdk-bridge-dhcp','etc/init.d/qsdk-nic-guard',
           'usr/lib/oem54/payload/common/usr/lib/oem54/qsdk-wifi.sh',
           # 第 45 次：网口速率纠偏工具（两模式都带）
           'usr/sbin/qsdk-link-rate',
           'usr/lib/oem54/payload/common/usr/sbin/qsdk-link-rate',
           'usr/sbin/qsdk-overlay-clean',
           'usr/lib/oem54/payload/common/usr/sbin/qsdk-overlay-clean',
           # 第 46 次：刷完即成型的业务配置（实机官方配置未改的缺口）
           'usr/sbin/qsdk-firstboot-config',
           'usr/sbin/qsdk-slim',
           'etc/config/qsdk-firstboot.conf',
           'usr/lib/oem54/payload/common/usr/sbin/qsdk-firstboot-config',
           'usr/lib/oem54/payload/common/etc/config/qsdk-firstboot.conf',
           'usr/lib/oem54/fdt-rate-feasibility.py',
           'etc/firmware_build']
    # 第 45 次：AP 简版 /bridge/ 页依赖 bridge CGI，以前漏注入
    if mode=='ap': inj44+=['www/cgi-bin/bridge']
    if mode=='wds':
        inj44+=['usr/sbin/qsdk-bridge-role','usr/sbin/qsdk-watchdog',
                'etc/init.d/qsdk-bridge-role','etc/init.d/qsdk-watchdog',
                'etc/config/wdsdog']
    else:
        inj44+=['usr/sbin/qsdk-bridge-ap','etc/config/ap-rssi-guard']
    for k in inj+inj44:
        if (N/k).is_file(): ok('注入 ← '+k)
        else: no('注入缺失 '+k)
    # 双栈 CGI：必须内建 wlanconfig/iwinfo 回退
    cg='www/cgi-bin/bridge' if mode=='wds' else 'www/cgi-bin/apstatus'
    c=(N/cg).read_text(errors='replace') if (N/cg).is_file() else ''
    if 'wsd_dump' in c and 'wlanconfig' in c: ok('CGI 双栈关联读取在位 ← '+cg)
    else: no('CGI 缺双栈关联读取 '+cg)
    # 第 45 次：速率纠偏（两个 CGI 里 bridge 才有端口段）
    bc=(N/'www/cgi-bin/bridge').read_text(errors='replace') if (N/'www/cgi-bin/bridge').is_file() else ''
    if 'port_rate' in bc and 'speed_note' in bc and 'STACK_CLOSED' in bc:
        ok('网口速率纠偏：不显示误导值 + 实测吞吐')
    else: no('bridge CGI 缺第 45 次速率纠偏')
    # 三页渲染：速率行不再直接拼 Mbps 误导值
    ph='www/bridge/index.html'
    h=(N/ph).read_text(errors='replace') if (N/ph).is_file() else ''
    if '实测吞吐' in h and 'speed_note' in h: ok('页面已显示「实测吞吐 / 未上报」')
    else: no('页面缺速率纠偏渲染')
    fb=(N/'etc/init.d/oem54-firstboot').read_text(errors='replace') if (N/'etc/init.d/oem54-firstboot').is_file() else ''
    if 'qsdk-nic-guard enable' in fb: ok('首启自动 enable 网口守护')
    else: no('首启未 enable 网口守护')
    if mode=='wds' and 'qsdk-bridge-role enable' not in fb: no('WDS 首启未 enable 自动主备')
    if mode=='ap' and 'qsdk-bridge-role enable' in fb: no('AP 固件误装 WDS 主备')
    # 第 45 次硬纠错：物理 PEB 顺序必须与官方一致（第43/44次整体挪过位）
    def volseq(data):
        s=[]
        for i in range(len(data)//PEB):
            v=data[i*PEB+VID_OFF:i*PEB+VID_OFF+64]
            if v[:4]==b'UBI!':
                vol=struct.unpack_from('>I',v,8)[0]
                if vol in (0,LAYOUT): s.append(vol)   # rootfs 扩卷必然变长，只比 layout/kernel 位置
        return s
    if volseq(b)==volseq(rb): ok('物理 PEB 卷顺序与官方逐位一致（layout/kernel 未挪位）')
    else: no('物理 PEB 卷顺序被挪动 —— 这是「刷完没变动」的根因')
    # 构建号：刷完一眼判版本（文件名也带 r45）
    fbp=N/'etc/firmware_build'
    if fbp.is_file() and fbp.read_text(errors='replace').startswith('r47-'):
        ok('固件内构建号 '+fbp.read_text().strip())
    else: no('缺 r47 构建号（旧固件/旧包）')
    # 第 47 次：交换芯片 PHY 真值速率（不再只显示「未上报」）
    bc3=(N/'www/cgi-bin/bridge').read_text(errors='replace') if (N/'www/cgi-bin/bridge').is_file() else ''
    if 'phy_link_probe' in bc3 and 'speed_src' in bc3 and 'swconfig' in bc3:
        ok('bridge CGI 从交换芯片 PHY 读真实协商速率并标注来源')
    else: no('bridge CGI 缺 PHY 真值探测')
    lk=(N/'usr/sbin/qsdk-link-rate').read_text(errors='replace') if (N/'usr/sbin/qsdk-link-rate').is_file() else ''
    if 'phy_probe' in lk and 'speed_src' in lk:
        ok('qsdk-link-rate 同步显示 PHY 真值')
    else: no('qsdk-link-rate 缺 PHY 真值探测')
    for ph in ['www/bridge/index.html']:
        hh=(N/ph).read_text(errors='replace') if (N/ph).is_file() else ''
        if '速率来源' in hh and '交换芯片 PHY' in hh: ok('页面显示速率来源（'+ph+'）')
        else: no('页面缺速率来源标注 '+ph)
    # 第 46 次：首启业务配置必须被调用、VAP 识别必须排除 wifi*/soc*
    fbs=N/'etc/init.d/oem54-firstboot'
    f=(fbs.read_text(errors='replace') if fbs.is_file() else '')
    if 'qsdk-firstboot-config' in f and 'lan.proto dhcp' not in f:
        ok('首启自动应用业务配置（已删会丢管理地址的 dhcp 改动）')
    else: no('首启未调业务配置或仍含 lan.proto dhcp')
    if 'qsdk_firstboot' in f or 'BID' in f:
        ok('首启 STAMP 按构建号判定（保留配置升级也会重跑）')
    else: no('首启 STAMP 仍用日期，保留配置升级会挡住新配置')
    qw=N/'usr/lib/oem54/qsdk-wifi.sh'
    q=(qw.read_text(errors='replace') if qw.is_file() else '')
    if 'wifi1（radio）' in q and 'ath[0-9]*|wlan[0-9]*' in q:
        ok('VAP 识别已排除 wifi*/soc*（实机 ath0/ath1）')
    else: no('VAP 识别仍会把 wifi1 radio 当 VAP')
    bc2=(N/'www/cgi-bin/bridge').read_text(errors='replace') if (N/'www/cgi-bin/bridge').is_file() else ''
    if 'AUTO_VAP' in bc2 and 'wlan1' in bc2:
        ok('端口列表自动补真实 VAP（ath0/ath1），不再显示未注册灰卡')
    else: no('端口列表未做实机适配')
    bcg=N/'www/cgi-bin/bridge'
    if bcg.is_file() and '"build"' in bcg.read_text(errors='replace'):
        ok('CGI 输出 build 字段（页脚显示版本）')
    else: no('CGI 缺 build 字段')
    # overlay 清理工具（应对勾了保留配置）
    if (N/'usr/sbin/qsdk-overlay-clean').is_file(): ok('overlay 残留清理工具在位')
    else: no('缺 qsdk-overlay-clean')
    # 模式标记
    fm=(N/'etc/firmware_mode').read_text().strip() if (N/'etc/firmware_mode').is_file() else ''
    if fm==mode: ok('firmware_mode='+fm)
    else: no('firmware_mode=%s 应为 %s'%(fm,mode))
    qg=(N/'etc/config/qsdk-guard').read_text() if (N/'etc/config/qsdk-guard').is_file() else ''
    if "option mode '%s'"%mode in qg and "option model '%s'"%model in qg: ok('qsdk-guard mode/model 正确')
    else: no('qsdk-guard mode/model 错误')
    # 6 设备节点
    r=subprocess.run(['unsquashfs','-ll',str(p),'dev/console'],capture_output=True,text=True)
    if '5,  1' in r.stdout or '5, 1' in r.stdout: ok('/dev/console 字符设备节点已补回 (5,1)')
    else: no('/dev/console 设备节点缺失')
    # 7 危险路径绝不能被覆盖
    bad=['etc/config/network','etc/config/wireless','etc/config/dhcp','etc/config/firewall',
         'etc/config/luci','etc/config/uhttpd','etc/rc.local','etc/uci-defaults/99-bridge-ready']
    hit=[k for k in bad if (N/k).is_file() and k.startswith('etc/') and
         (O/k).is_file() and (N/k).read_bytes()!=(O/k).read_bytes()]
    if not hit: ok('官方 network/wireless/dhcp/dropbear/luci/uhttpd/firewall 未被覆盖')
    else: no('官方配置被改: '+','.join(hit))
    # 8 注入脚本语法
    for k in ['usr/sbin/qsdk-dhcp-guard','usr/sbin/qsdk-rssi-guard','etc/init.d/qsdk-guard',
              'etc/init.d/oem54-firstboot','usr/sbin/wifi-stack-check',
              'usr/lib/oem54/apply-full-config.sh','usr/lib/oem54/apply-oem-overlay.sh',
              'usr/lib/oem54/qsdk-wifi.sh','usr/sbin/qsdk-nic-guard',
              'usr/sbin/qsdk-bridge-dhcp','etc/init.d/qsdk-nic-guard',
              'usr/sbin/qsdk-bridge-role','usr/sbin/qsdk-watchdog',
              'etc/init.d/qsdk-bridge-role','etc/init.d/qsdk-watchdog',
              'usr/sbin/qsdk-bridge-ap','usr/sbin/qsdk-link-rate',
              'usr/sbin/qsdk-overlay-clean','usr/sbin/qsdk-firstboot-config',
              'usr/sbin/qsdk-slim',
              'www/cgi-bin/bridge','www/cgi-bin/apstatus']:
        if not (N/k).is_file(): continue
        f=N/k
        if f.is_file():
            r=subprocess.run(['sh','-n',str(f)],capture_output=True)
            if r.returncode==0: ok('sh -n ← '+k)
            else: no('sh -n 失败 '+k+' '+r.stderr.decode()[:80])
    shutil.rmtree(tmp,ignore_errors=True)
    print('    sha256 = %s'%hashlib.sha256(b).hexdigest())

if __name__=='__main__':
    if len(sys.argv)<5:
        print('用法: verify-fused.py <fw.bin> <原官方.bin> <wds|ap> <VS010|RAX3000Q>'); sys.exit(2)
    main(*sys.argv[1:5]); print('\nRESULT:','PASS' if F==0 else 'FAIL'); sys.exit(F)
