/* WDS/AP（仿UBNT）· 6.12 单包双模式状态页
   对齐 5.4 老仓 STANDARDS r28–r29.12：
     前 3 块两页完全同序：系统仪表盘 GAUGE → 常用设置 SETUP → 网络与本机 NETWORK
     之后才是 WDS（守护·RF·诊断·加速）/ AP（射频·终端·弱信号·BDF·加速）业务块
     6 入口互访、胶囊圆角、内网LAN1… 6 列、GAUGE 时间/运行徽章、写入只在 LuCI admin 树
   ?demo=1 / file: 用内嵌演示数据离线渲染（不 fetch），数值标注 DEMO，绝不冒充实机。 */
(function(){
  var D=document, PAGE=D.body.getAttribute('data-page')||'bridge';
  var DEMO = /[?&]demo=1/.test(D.location.search) || D.location.protocol==='file:';
  var E='/cgi-bin/luci/admin/nwrt';
  function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]});}
  function n(v,suf){return (v==null||v===''||v==='?')?'—':esc(v)+(suf||'');}
  function pill(v,c){return '<span class="u-badge '+(c||'')+'">'+esc(v)+'</span>';}

  /* 老仓 r29.8：离线演示数据。图片预览用它，页面上明确标 DEMO。 */
  var DEMOJ={
    ok:1,demo:1,product:'WDS/AP（仿UBNT）',mode:'wds',default_mode:'wds',
    host:'NWRT-VS010',model:'CUCC VS010',kernel:'6.12.112',baseline:'official-25.12',
    source_commit:'v25.12.6',build:'Nwrt-WDS-AP-UBNT-6.12.112-20261128-dual',
    time:'2026-11-28 17:40:12',uptime:'2天 03:12:44',
    sys:{cpu_usage_pct:12,mem_used_pct:38,cpu_temp:'48°C',radio_temps:'52°C / 49°C'},
    net:{ip:'172.10.10.241',mask:'255.255.252.0',stp:'1',wan:'已删除',wan6:'已删除',
         ipv6:'off',firewall:'off',dhcp_server:'关闭（上级透传）'},
    lan:[
      {name:'内网LAN1',speed:'1G',source:'PHY 实测',carrier:1,rx:'989.2 Mbps',tx:'989.1 Mbps',duplex:'全双工'},
      {name:'内网LAN2',speed:'1G',source:'PHY 实测',carrier:1,rx:'12.4 Mbps',tx:'8.1 Mbps',duplex:'全双工'},
      {name:'内网LAN3',speed:'—',source:'PHY 实测',carrier:0,rx:'0',tx:'0',duplex:'—'},
      {name:'WAN(内网)',speed:'1G',source:'PHY 实测',carrier:1,rx:'—',tx:'—',duplex:'全双工'}
    ],
    radios:[
      {band:'5G',ssid:'NWRT-WDS',channel:'36',htmode:'HE160',status:'WDS 4addr · DFS CAC 约 60s'},
      {band:'2.4G',ssid:'—',channel:'1',htmode:'HE40',status:'WDS 模式已关闭'}
    ],
    stations:[{mac:'00:03:7F:12:EF:EF',iface:'wlan1',signal:'-54 dBm',rate:'866 Mbps',band:'5G'}],
    nss:{present:0,fw:'—',conn:'—',load:'—'},
    tick:{enabled:1,dryrun:1,last:'[nwrt-tick] round=17 mode=wds dryrun=1'},
    guard:'已生效：拦截无线侧 DHCPv4/v6 Offer/ACK（hook prerouting）',
    l2guard_status:'已生效：拦截无线侧 DHCPv4/v6 Offer/ACK（hook prerouting）',
    dhcp_server:'关闭（上级透传）',ssh:'dropbear · ttyMSM0 115200n8',ttyd:'已启用',
    bdf:{file:'board-2.bin',source:'官方通用容器',caldata:'off'},
    setup:{mode:'wds',role:'master',peer_ssid:'',peer_bssid:'',peer_key:'',
      ssid5:'NWRT-WDS',key5:'WDS123456',ssid2:'NWRT-AP-2G',key2:'AP123456',
      ch5g:'36',htmode:'HE160',ch24g:'1',ht24:'HE40',txpower:'auto',wmm:'1',mu_mimo:'0',
      rssi_thr:'-85',rssi_timeout:'10',ip:'172.10.10.241',mask:'255.255.252.0',
      hostname:'NWRT-VS010',stp:'1',ntp:'172.10.10.254',theme:'ubnt',
      dhcp_enabled:'0',dhcp_start:'100',dhcp_limit:'150',dhcp_lease:'12h'},
    logs:'[nwrt-tick] round=17 mode=wds dryrun=1\n[l2-guard] OK 无线侧 DHCP 已拦（prerouting）\n[bridge-netfix] OK stp=1 wan/wan6=deleted\n[nwrt-mode] OK act=boot mode=wds 一次 wifi reload\n[DEMO] 以上为演示数据，非实机日志'
  };

  function ring(label,val,unit,color){
    var v=Math.max(0,Math.min(100,parseInt(val,10)||0)), C=2*Math.PI*42;
    var off=C*(1-v/100);
    var txt=(val==null||val===''||val==='?')?'—':esc(val)+(unit||'');
    return '<div class="u-ring '+(color||'')+'"><svg width="104" height="104" viewBox="0 0 104 104">'+
      '<circle class="bg" cx="52" cy="52" r="42" fill="none" stroke-width="9"/>'+
      '<circle class="fg" cx="52" cy="52" r="42" fill="none" stroke-width="9" '+
      'stroke-dasharray="'+C.toFixed(1)+'" stroke-dashoffset="'+off.toFixed(1)+'"/></svg>'+
      '<div class="v"><b>'+txt+'</b><small>'+esc(label)+'</small></div></div>';
  }
  function gauge(j){
    var s=j.sys||{}, b='';
    b+=pill('时间 '+n(j.time),'')+pill('运行 '+n(j.uptime),'');
    b+=pill('无线芯片温度 '+n(s.radio_temps||'—（无温度传感器）'),'ok');
    b+=pill('产品 '+n(j.product||'WDS/AP（仿UBNT）'),'');
    b+=pill('模式 '+(j.mode==='ap'?'AP 模式':'WDS 网桥'),'warn');
    b+=pill('DEMO 演示数据 · 非实机','warn');
    var mismatch=(j.mode==='ap'&&PAGE==='bridge')||(j.mode==='wds'&&PAGE==='ap');
    return '<section class="u-sec" id="gauge"><h2>系统仪表盘 <span class="tag">GAUGE</span></h2>'+
      (mismatch?'<div class="u-card u-hintbar"><b>当前是 '+(j.mode==='ap'?'AP':'WDS 网桥')+' 模式</b>，'+
        '这是'+(PAGE==='bridge'?'网桥状态':'AP 状态')+'页，数据仍为只读实况（不强制跳走，保留三页全互访）。 '+
        '<a class="u-btn2" href="'+E+'">⇄ 去模式切换</a></div><p></p>':'')+
      '<div class="u-gauge">'+ring('CPU',s.cpu_usage_pct,'%')+ring('内存',s.mem_used_pct,'%')+
      ring('CPU 温度',parseInt(s.cpu_temp,10)||0,'°',(parseInt(s.cpu_temp,10)>=70?'r':''))+
      '<div class="u-badges"><div class="row">'+b+'</div>'+
      '<div class="u-hint">三个环形仪表置顶；详细数值微卡与 CPU/内存文字卡片按老仓 r28 基线不显示。'+
      '读不到传感器如实留白，绝不写假数值。</div></div></div></section>';
  }

  /* ── 常用设置控制台：①…⑧ 两页同序（对齐老仓 r27 / r29.7 / r29.11 / r29.12）── */
  function fld(label,name,v,opt){
    var t=opt&&opt.type==='select';
    var inp=t?'<select class="u-select" name="'+name+'"'+(opt.opts||'')+'>'+'</select>'
             :'<input class="u-input" name="'+name+'" value="'+esc(v==null?'':v)+'"'+
              (opt&&opt.ph?' placeholder="'+esc(opt.ph)+'"':'')+'>';
    if(t){
      var o='';
      for(var i=0;i<opt.opts.length;i++){
        var x=opt.opts[i]; o+='<option value="'+esc(x[0])+'"'+(String(v)===String(x[0])?' selected':'')+'>'+esc(x[1])+'</option>';
      }
      inp='<select class="u-select" name="'+name+'">'+o+'</select>';
    }
    return '<div class="u-fld"><label>'+esc(label)+'</label>'+inp+
      (opt&&opt.hint?'<span class="hint">'+opt.hint+'</span>':'')+'</div>';
  }
  function grp(n,title,body){return '<div class="u-grp"><h3><span class="n">'+n+'</span>'+esc(title)+'</h3><div class="body">'+body+'</div></div>';}
  function setup(j){
    var s=j.setup||{}, lock=(j.mode==='wds');
    var g='';
    g+=grp('①','工作模式 · AP ⇄ WDS',
      fld('工作模式','mode',s.mode,{type:'select',opts:[['wds','WDS 网桥（/bridge/）'],['ap','AP（/ap/）']],
        hint:'单包双模式：切换只写 overlay + 一次 wifi reload，不用重刷'})+
      fld('WDS 主 / 客户端','role',s.role,{type:'select',opts:[['master','WDS-Z 主端 .241'],['client','WDS-K 客户端 .242']],
        hint:'第二台改 IP：echo 172.10.10.242 > /etc/nwrt/ipaddr（改了就保存，脚本绝不改回）'})+
      '<div class="u-note">老仓 r27 的左右滑动开关与模式守卫保留；6.12 下切换由 '+
      '<code>nwrt-apply-mode wds|ap</code> 固定枚举执行，零 eval、零参数注入面。</div>');
    g+=grp('②','WDS 桥接目标',
      fld('主端 SSID','peer_ssid',s.peer_ssid,{ph:'NWRT-WDS'})+
      fld('密码','peer_key',s.peer_key,{ph:'WDS123456'})+
      fld('BSSID 定向','peer_bssid',s.peer_bssid,{ph:'可留空'})+
      '<div class="u-fld"><label>搜索周边主端（只读扫描）</label>'+
        '<button class="u-btn2" id="btnScan" type="button">🔍 搜索 SSID</button>'+
        '<span class="hint">点选结果自动填 SSID / BSSID 并跟随信道；不自动写配置。</span></div>'+
      '<div class="u-fld" style="grid-column:1/-1"><div id="scanOut" class="u-hint">尚未扫描。</div></div>');
    g+=grp('③','AP 双频独立 SSID 与密码',
      fld('5G SSID','ssid5',s.ssid5)+fld('5G 密码','key5',s.key5)+
      fld('2.4G SSID','ssid2',s.ssid2)+fld('2.4G 密码','key2',s.key2)+
      '<div class="u-note">WDS 模式只用 5G 4addr（2.4G 关闭）；AP 模式双频同时作为 AP。</div>');
    g+=grp('④','WiFi 射频参数（6.12 主线口径）',
      fld('5G 信道','ch5g',s.ch5g,{type:'select',opts:[['auto','auto（ACS 自动选）'],['36','36'],['44','44'],['149','149'],['165','165']],
        hint:'CN + HE160 需约 60s DFS CAC；改 HE80 可免等，吞吐少约 1/3'})+
      fld('5G 频宽','htmode',s.htmode,{type:'select',opts:[['HE160','HE160 · 160MHz'],['HE80','HE80 · 80MHz'],['HE40','HE40 · 40MHz']],
        hint:'🔴 升级修复：6.12 主线 mac80211 用 HE*，老仓 QSDK 的 HT160/HT80 已弃用'})+
      fld('2.4G 信道','ch24g',s.ch24g,{type:'select',opts:[['auto','auto'],['1','1'],['6','6'],['11','11']]})+
      fld('2.4G 频宽','ht24',s.ht24,{type:'select',opts:[['HE40','HE40 · 20/40 共存'],['HE20','HE20 · 仅 20MHz']],
        hint:'交叉串写会被后端双白名单拒绝；2.4G 绝不写 HE160/HE80'})+
      fld('发射功率','txpower',s.txpower,{type:'select',opts:[['auto','auto'],['20','20 dBm'],['17','17 dBm'],['14','14 dBm']]})+
      fld('WMM','wmm',s.wmm,{type:'select',opts:[['1','开启'],['0','关闭']]})+
      fld('MU-MIMO','mu_mimo',s.mu_mimo,{type:'select',opts:[['0','关闭'],['1','开启']],
        hint:'⚠ 6.12 主线 hostapd 无通用 UCI：字段保留但不下发，如实标注'})+
      fld('弱信号剔除','rssi_thr',s.rssi_thr,{hint:'−100…−30 dBm；⚠ 6.12 无 db_rssi_thr，标注不下发'})+
      fld('最低连接保持','rssi_timeout',s.rssi_timeout,{hint:'1–60 s；⚠ 同上，不下发'})+
      '<div class="u-note red">🔴 内核升级修复：老仓 r29.12 的 <code>HT160/HT80/HT40</code> 是 QSDK '+
      '<code>qcawifi.sh</code> 私有约定，写进 6.12 主线 ath11k 会让 radio 起不来；'+
      '本版统一改 <code>HE160/HE80/HE40/HE20</code>。QSDK 的 <code>db_rssi_thr</code> / '+
      '<code>db_timeout</code> / MU-MIMO 无对应 UCI，字段保留在 user.cfg 但明确标注「该基线不支持，不下发」，'+
      '绝不伪造已生效。</div>');
    g+=grp('⑤','本机与网络',
      fld('管理 IP','ip',s.ip)+fld('子网掩码','mask',s.mask)+
      '<div class="u-note">改了就持久保存：开机脚本只读不删不写覆盖文件，切模式/重启都不会自动改回。'+
      '上级若是 192.168.1.x/24 等非 /22 网段，请同步改掩码。</div>'+
      fld('设备名','hostname',s.hostname)+
      fld('STP 生成树','stp',s.stp,{type:'select',opts:[['1','开启（防两台 WDS 成环）'],['0','关闭']]})+
      fld('NTP 服务器','ntp',s.ntp,{hint:'纯 IP，不依赖本机 DNS'})+
      '<div class="u-note">WAN / WAN6 已删，所有网口（含 WAN 物理口）+ 双频全在 br-lan；'+
      '不改 root 密码、固件升级、VLAN/静态路由、opkg —— 留给 LuCI 高级设置后台。</div>');
    g+=grp('⑥','DHCP 服务 · ADDRESS POOL',
      fld('本机 DHCP 服务端','dhcp_enabled',s.dhcp_enabled,{type:'select',opts:[['0','关闭（交上级，默认）'],['1','开启本机发地址']],
        hint:'WDS 模式硬锁定关闭；AP 模式可选'})+
      fld('地址池起始','dhcp_start',s.dhcp_start)+fld('地址数量 1–253','dhcp_limit',s.dhcp_limit)+
      fld('租期','dhcp_lease',s.dhcp_lease,{type:'select',opts:[['1h','1 小时'],['12h','12 小时'],['24h','24 小时']]})+
      '<div class="u-note red">🔴 WDS 主 / 客户端两端都绝不能开 DHCP 服务端；内网始终只允许一台 DHCP。'+
      '本机不开时 dnsmasq 不启动，零常驻、不占运行内存。无线侧私设 DHCP 由 l2-guard（prerouting）拦。</div>');
    g+=grp('⑦','主题与界面',
      fld('LuCI 主题','theme',s.theme,{type:'select',opts:[['ubnt','UBNT（仿 UniFi）· 深色'],['bootstrap','Bootstrap（官方原样）']],
        hint:'UBNT 是真·主题目录：@import 官方 bootstrap 完整资源 + 深色覆盖，不指向空气；依赖缺失自动回退'})+
      '<div class="u-fld"><label>界面入口</label><div class="u-inline">'+
        '<a class="u-btn2" href="/ubnt/">◧ 概览</a><a class="u-btn2" href="/bridge/">⇄ 网桥状态</a>'+
        '<a class="u-btn2" href="/ap/">≋ AP 状态</a><a class="u-btn2" href="/cgi-bin/luci/">⚙ 高级设置后台</a>'+
        '</div><span class="hint">三页同款 UBNT 深色皮肤 + 六入口互访；竖屏横向滚动不隐藏。</span></div>');
    g+=grp('⑧','自检 · 机器狗 · Snooping · 日志',
      '<div class="u-fld"><label>维护动作（固定枚举、零参数）</label><div class="u-inline">'+
        '<button class="u-btn2" data-act="health" type="button">🩺 一键自检</button>'+
        '<button class="u-btn2" data-act="wifi" type="button">📶 无线全速核对</button>'+
        '<button class="u-btn2" data-act="l2" type="button">🛡 Snooping 状态</button>'+
        '<button class="u-btn2" data-act="oem" type="button">🔍 栈自检</button>'+
        '<button class="u-btn2" data-act="logs" type="button">📜 查看日志</button>'+
        '</div><span class="hint">只在 LuCI admin 树执行；未登录锁定。</span></div>'+
      '<div class="u-fld" style="grid-column:1/-1"><label>输出</label><div class="u-log" id="actOut">点上面的按钮查看结果。</div></div>'+
      '<div class="u-note">轻量机器狗 <code>nwrt-tick</code> 单常驻，出厂 <code>DRYRUN=1</code> 只记录不动作；'+
      'NTP / WDS 关联 / 状态快照分频。命令兜底：<code>nwrt-apply-mode wds|ap</code>、'+
      '<code>/etc/init.d/l2-guard status</code>。</div>');
    return '<section class="u-sec" id="setup"><h2>常用设置控制台 <span class="tag">SETUP</span></h2>'+
      '<div class="u-setup"><div class="u-lock" id="lockBar">🔒 正在确认 LuCI 会话… 未登录时保存与维护锁定（状态仍只读可见）。 '+
      '<a class="u-btn2" href="/cgi-bin/luci/">🔑 登录 LuCI</a></div>'+
      g+'<div class="foot"><button class="u-btn2 pri" id="btnSave" type="button" disabled>💾 保存并应用</button>'+
      '<button class="u-btn2" id="btnRevert" type="button">↺ 还原</button>'+
      '<span class="u-msg" id="saveMsg">写入只在 /cgi-bin/luci/admin/nwrt/save（sysauth），零裸 CGI 写入端点。</span>'+
      '</div></div>'+
      (lock?'<p class="u-hint">WDS 模式下 ⑥ DHCP 服务整组锁定（前端 disabled + 后端二次强制 ignore=1）。</p>':'')+
      '</section>';
  }

  function network(j){
    var t=j.net||{}, lan=j.lan||[];
    var rows=lan.map(function(x){
      return '<tr><td>'+esc(x.name)+'</td><td>'+esc(x.speed||'—')+'</td><td>'+esc(x.source||'—')+'</td>'+
        '<td>'+(x.carrier?pill('已连接','ok'):pill('未连接'))+'</td><td>'+esc(x.rx||'—')+'</td><td>'+esc(x.tx||'—')+'</td></tr>';
    }).join('')||'<tr><td colspan="6" class="none">—（读不到端口，不伪造）</td></tr>';
    var cards='<div class="u-grid">'+
      '<div class="u-card"><h3>本机 · DEVICE</h3><table class="u-tbl">'+
        '<tr><td>管理地址</td><td><code>'+n(t.ip)+' / '+n(t.mask)+'</code></td></tr>'+
        '<tr><td>机型 / 主机名</td><td>'+esc(j.model||'')+' / '+esc(j.host||'')+'</td></tr>'+
        '<tr><td>内核 / 基线</td><td><code>'+n(j.kernel)+'</code> · '+esc(j.baseline||'')+'</td></tr>'+
        '<tr><td>编译标识</td><td>'+esc(j.build||'—')+'</td></tr></table></div>'+
      '<div class="u-card"><h3>桥 · BR-LAN</h3><table class="u-tbl">'+
        '<tr><td>STP</td><td>'+pill(t.stp==='1'?'开启（防环）':'关闭',t.stp==='1'?'ok':'warn')+'</td></tr>'+
        '<tr><td>WAN / WAN6</td><td>'+esc(t.wan||'已删除')+' / '+esc(t.wan6||'已删除')+'</td></tr>'+
        '<tr><td>全部网口</td><td>内网（含 WAN 物理口）+ 双频同桥</td></tr>'+
        '<tr><td>本机 DHCP 服务端</td><td>'+esc(t.dhcp_server||'关闭（上级透传）')+'</td></tr></table></div>'+
      '<div class="u-card"><h3>防护 · GUARD</h3><table class="u-tbl">'+
        '<tr><td>无线侧 DHCP Snooping</td><td>'+esc(j.guard||'—')+'</td></tr>'+
        '<tr><td>防火墙 / IPv6</td><td>'+pill('已关')+' / '+pill('已关')+'</td></tr>'+
        '<tr><td>SSH / 串口</td><td>'+esc(j.ssh||'dropbear · ttyMSM0 115200n8')+'</td></tr>'+
        '<tr><td>TTYD</td><td><a class="u-btn2" href="http://'+esc(D.location.hostname||'172.10.10.241')+':7681/" target="_blank">打开 :7681</a></td></tr>'+
        '</table></div></div>';
    return '<section class="u-sec" id="network"><h2>网络与本机 <span class="tag">NETWORK</span></h2>'+cards+
      '<div class="u-card" style="margin-top:13px"><h3>内网 LAN · 物理口固定命名</h3>'+
      '<table class="u-tbl6"><thead><tr><th>端口</th><th>链接速率</th><th>速率来源</th><th>链路</th><th>RX</th><th>TX</th></tr></thead>'+
      '<tbody>'+rows+'</tbody></table>'+
      '<p class="u-hint">1000→1G / 2500→2.5G / 100→100M / 10→10M / 读不到「—」；br-lan 是二层桥不占号，'+
      '不进表。判速看 eth0/eth1，不看 br-lan（NSS 卸载流量不过 Linux 网桥）。</p></div></section>';
  }

  function wdsBlocks(j){
    var r=j.radios||[], st=j.stations||[], ns=j.nss||{}, tk=j.tick||{};
    var rr=r.map(function(x){return '<tr><td>'+esc(x.band)+'</td><td>'+esc(x.ssid||'—')+'</td><td>'+
      esc(x.channel||'—')+'</td><td>'+esc(x.htmode||'—')+'</td><td>'+esc(x.status||'—')+'</td></tr>'}).join('')||
      '<tr><td colspan="5" class="none">—</td></tr>';
    var ss=st.map(function(x){return '<tr><td>'+esc(x.mac||'—')+'</td><td>'+esc(x.iface||'—')+'</td><td>'+
      esc(x.signal||'—')+'</td><td>'+esc(x.rate||'—')+'</td><td>'+esc(x.band||'—')+'</td></tr>'}).join('')||
      '<tr><td colspan="5" class="none">—（无关联客户端 / iw 不可用，如实留白）</td></tr>';
    return '<section class="u-sec"><h2>网桥业务 <span class="tag">WDS · 守护 · RF · 诊断 · 加速</span></h2><div class="u-grid">'+
      '<div class="u-card"><h3>WDS 守护 · WATCHDOG</h3><table class="u-tbl">'+
        '<tr><td>单常驻</td><td>'+(tk.enabled?pill('nwrt-tick 已启用','ok'):pill('未启用','warn'))+'</td></tr>'+
        '<tr><td>自愈动作</td><td>'+(tk.dryrun?pill('dryrun=1 · 只记录','warn'):pill('允许限频 reload'))+'</td></tr>'+
        '<tr><td>最近一轮</td><td><code>'+esc(tk.last||'—')+'</code></td></tr>'+
        '<tr><td>红线</td><td>不 wifi down · 不重启 · 30 轮冷却</td></tr></table>'+
        '<p class="u-hint">老仓 vs010-tick + bridge-watchdog（停用）合并为单个 nwrt-tick。</p></div>'+
      '<div class="u-card"><h3>射频 · RF</h3><table class="u-tbl"><tr><th>频段</th><th>SSID</th><th>信道</th><th>频宽</th><th>状态</th></tr>'+rr+'</table>'+
        '<p class="u-hint">5G 4addr 回程，2.4G 关闭；CN + HE160 开机约 60 秒 DFS CAC。</p></div>'+
      '<div class="u-card"><h3>诊断 · DIAG</h3><table class="u-tbl">'+
        '<tr><td>关联客户端</td><td>'+st.length+' 台</td></tr>'+
        '<tr><td>客户端表</td><td>见下方终端</td></tr>'+
        '<tr><td>自检命令</td><td><code>wifi-fullspeed</code></td></tr>'+
        '<tr><td>栈自检</td><td><code>oem-stack-check</code></td></tr></table>'+
        '<table class="u-tbl" style="margin-top:9px"><tr><th>MAC</th><th>接口</th><th>信号</th><th>速率</th><th>频段</th></tr>'+ss+'</table></div>'+
      '<div class="u-card"><h3>加速 · DATA PLANE</h3><table class="u-tbl">'+
        '<tr><td>加速栈</td><td>'+(ns.present?pill('已加载','ok'):pill('未加载 / 官方无 NSS 基线','warn'))+'</td></tr>'+
        '<tr><td>固件版本</td><td>'+esc(ns.fw||'—')+'</td></tr>'+
        '<tr><td>加速连接数</td><td>'+esc(ns.conn||'—')+'</td></tr>'+
        '<tr><td>NSS 占用</td><td>'+esc(ns.load||'—')+'</td></tr></table>'+
        '<p class="u-hint">默认 official-25.12 无 NSS；要 5G 160MHz 满速再单独跑 qosmio-25.12-nss。</p></div>'+
      '</div></section>';
  }

  function apBlocks(j){
    var r=j.radios||[], st=j.stations||[], ns=j.nss||{}, b=j.bdf||{};
    var rr=r.map(function(x){return '<tr><td>'+esc(x.band)+'</td><td>'+esc(x.ssid||'—')+'</td><td>'+
      esc(x.channel||'—')+'</td><td>'+esc(x.htmode||'—')+'</td><td>'+esc(x.status||'—')+'</td></tr>'}).join('')||
      '<tr><td colspan="5" class="none">—</td></tr>';
    var ss=st.map(function(x){return '<tr><td>'+esc(x.mac||'—')+'</td><td>'+esc(x.iface||'—')+'</td><td>'+
      esc(x.signal||'—')+'</td><td>'+esc(x.rate||'—')+'</td><td>'+esc(x.band||'—')+'</td></tr>'}).join('')||
      '<tr><td colspan="5" class="none">—（无关联客户端 / iw 不可用，如实留白）</td></tr>';
    return '<section class="u-sec"><h2>AP 业务 <span class="tag">射频 · 终端 · 弱信号 · BDF · 加速</span></h2><div class="u-grid">'+
      '<div class="u-card"><h3>射频 · RADIO</h3><table class="u-tbl"><tr><th>频段</th><th>SSID</th><th>信道</th><th>频宽</th><th>状态</th></tr>'+rr+'</table></div>'+
      '<div class="u-card"><h3>终端 · STATIONS</h3><table class="u-tbl"><tr><th>MAC</th><th>接口</th><th>信号</th><th>速率</th><th>频段</th></tr>'+ss+'</table>'+
        '<p class="u-hint">读不到关联一律留白，不伪造客户端。</p></div>'+
      '<div class="u-card"><h3>弱信号剔除 · RSSI</h3><table class="u-tbl">'+
        '<tr><td>阈值字段</td><td><code>rssi_thr</code>（已保存）</td></tr>'+
        '<tr><td>6.12 下发</td><td>'+pill('该基线不支持，不下发','warn')+'</td></tr>'+
        '<tr><td>原因</td><td>QSDK db_rssi_thr / db_timeout 无对应主线 UCI</td></tr></table>'+
        '<p class="u-hint">升级修复：保留老仓字段与按钮，但不假装生效。</p></div>'+
      '<div class="u-card"><h3>BDF · 校准</h3><table class="u-tbl">'+
        '<tr><td>容器</td><td><code>'+esc(b.file||'board-2.bin')+'</code></td></tr>'+
        '<tr><td>来源</td><td>'+esc(b.source||'官方通用容器')+'</td></tr>'+
        '<tr><td>本机 ART 校准</td><td>'+esc(b.caldata||'off')+'</td></tr></table>'+
        '<p class="u-hint">5.4 QSDK 单 BDF / 闭源 .ko 不能搬到 6.12 主线 ath11k；默认官方通用 board-2.bin。</p></div>'+
      '<div class="u-card"><h3>加速 · DATA PLANE</h3><table class="u-tbl">'+
        '<tr><td>加速栈</td><td>'+(ns.present?pill('已加载','ok'):pill('未加载 / 官方无 NSS','warn'))+'</td></tr>'+
        '<tr><td>固件</td><td>'+esc(ns.fw||'—')+'</td></tr>'+
        '<tr><td>连接数</td><td>'+esc(ns.conn||'—')+'</td></tr></table></div>'+
      '</div></section>';
  }

  function render(j){
    var e=D.getElementById('app'); if(!e)return;
    var head=(j.demo?'<div class="u-card u-hintbar" style="margin-bottom:13px"><b>DEMO 演示数据</b> · '+
      '离线界面预览（?demo=1），数值仅用于展示布局与按钮，<b>不是实机读数</b>；刷机后由 /cgi-bin/state 提供真实值。</div>':'');
    e.innerHTML='<div class="wrap">'+head+gauge(j)+setup(j)+network(j)+
      (PAGE==='ap'?apBlocks(j):wdsBlocks(j))+
      '<p class="u-hint" style="margin-top:12px">本页状态只读。写入与维护只在 LuCI admin 树'+
      '（<code>/cgi-bin/luci/admin/nwrt/*</code>，继承 sysauth）；若该基线未编 luci-compat 导致 404，'+
      '用 TTYD / SSH 的 <code>nwrt-apply-mode wds|ap</code> 与 <code>nwrt-apply-config</code>，'+
      '效果一致，<b>不用重刷</b>。根路径 / 按当前模式自动跳 /bridge/ 或 /ap/。</p></div>';
    bind(j);
  }

  /* ── 写入/维护：只在 LuCI admin 树；失败如实提示并给命令兜底 ── */
  function bind(j){
    var msg=D.getElementById('saveMsg'), out=D.getElementById('actOut');
    function say(t,c){if(msg){msg.textContent=t;msg.className='u-msg'+(c?' '+c:'');}}
    function log(t){if(out)out.textContent=t;}
    var locked=true;
    if(DEMO){
      if(D.getElementById('lockBar')) D.getElementById('lockBar').innerHTML=
        '🔒 <b>DEMO 预览：保存与维护已锁定</b>（离线渲染，不发起任何请求）。 '+
        '<a class="u-btn2" href="/cgi-bin/luci/">🔑 登录 LuCI</a>';
      say('DEMO 预览：写入端点已禁用，界面与按钮与实机一致。','');
      return;
    }
    /* r29.10：会话探测（只读），与老仓 probe 同源；404 时如实说明而非假装能点 */
    /* 会话探测：/cgi-bin/luci/admin/nwrt/probe（只读，admin 树继承 sysauth） */
    fetch('/cgi-bin/luci/admin/nwrt/probe',{credentials:'same-origin'}).then(function(r){
      return r.ok?r.json():{ok:0,msg:'HTTP '+r.status};
    }).then(function(d){
      locked=!d.ok;
      var lb=D.getElementById('lockBar');
      if(lb) lb.innerHTML=locked
        ? '🔒 <b>保存与维护已锁定</b>：'+esc(d.msg||'未登录 / 该基线未提供会话探测')+
          '。状态仍只读可见。 <a class="u-btn2" href="/cgi-bin/luci/">🔑 登录 LuCI</a>'
        : '🔓 已登录 LuCI 会话，保存与维护可用。 <a class="u-btn2" href="/cgi-bin/luci/admin/logout">🔑 退出</a>';
      var bs=D.querySelectorAll('.u-setup input,.u-setup select,.u-setup button[data-act],#btnSave,#btnScan');
      for(var i=0;i<bs.length;i++) bs[i].disabled=locked;
      /* WDS 模式 DHCP 整组硬锁（老仓 r29.7） */
      if(j.mode==='wds'){
        var dh=D.querySelector('[name=dhcp_enabled]');
        if(dh){dh.value='0';dh.disabled=true;}
        ['dhcp_start','dhcp_limit','dhcp_lease'].forEach(function(k){
          var x=D.querySelector('[name='+k+']'); if(x)x.disabled=true;
        });
      }
      if(D.getElementById('btnSave')) D.getElementById('btnSave').disabled=locked;
      say(locked?'未登录：保存与维护锁定（状态只读）。':'已解锁：可保存，字段白名单 + 后端二次校验。',locked?'':'ok');
    }).catch(function(e){
      if(D.getElementById('lockBar')) D.getElementById('lockBar').innerHTML=
        '🔒 <b>保存与维护已锁定</b>：'+esc(String(e))+'。若该基线未编 luci-compat，'+
        '请用 TTYD/SSH 的 <code>nwrt-apply-config</code> 兜底（效果一致）。 '+
        '<a class="u-btn2" href="/cgi-bin/luci/">🔑 登录 LuCI</a>';
      say('会话探测失败，写入端点不可用；命令兜底见面板说明。','bad');
    });
    D.getElementById('btnSave').onclick=function(){
      if(locked){say('未登录，保存已锁定。','bad');return;}
      var fd=new FormData(), els=D.querySelectorAll('.u-setup [name]');
      for(var i=0;i<els.length;i++) fd.append(els[i].name,els[i].value);
      say('正在保存…','');
      fetch(E+'/save',{method:'POST',body:fd,credentials:'same-origin'}).then(function(r){
        return r.text();
      }).then(function(t){
        say('保存完成：'+String(t).slice(0,160),'ok');
        log(String(t).slice(0,2000)||'（无输出）');
      }).catch(function(e){say('保存失败：'+esc(String(e))+'。可用 TTYD/SSH 执行 nwrt-apply-config 兜底。','bad');});
    };
    D.getElementById('btnRevert').onclick=function(){render(j);say('已还原为设备当前值。','');};
    var scan=D.getElementById('btnScan');
    if(scan) scan.onclick=function(){
      if(locked){say('未登录，扫描已锁定。','bad');return;}
      var o=D.getElementById('scanOut'); if(o)o.textContent='扫描中（约 2–5 秒，桥接可能短暂抖动）…';
      fetch(E+'/scan',{credentials:'same-origin'}).then(function(r){return r.text();}).then(function(t){
        if(o)o.textContent=String(t).slice(0,1500)||'无结果';
      }).catch(function(e){if(o)o.textContent='扫描失败：'+String(e);});
    };
    var acts=D.querySelectorAll('.u-setup button[data-act]');
    for(var k=0;k<acts.length;k++) acts[k].onclick=function(){
      if(locked){say('未登录，维护动作已锁定。','bad');return;}
      var a=this.getAttribute('data-act');
      fetch(E+'/act?act='+encodeURIComponent(a),{credentials:'same-origin'}).then(function(r){return r.text();})
        .then(function(t){log(String(t).slice(0,3000)||'（无输出）');})
        .catch(function(e){log('执行失败：'+String(e));});
    };
  }

  if(DEMO){
    /* 两张预览图各自展示「当前模式」的界面；非当前模式提示条仍保留在实机逻辑里 */
    DEMOJ.mode = (PAGE==='ap'?'ap':'wds');
    DEMOJ.setup.mode = DEMOJ.mode;
    render(DEMOJ); return;
  }
  fetch('/cgi-bin/state').then(function(r){return r.json();}).then(render).catch(function(e){
    var a=D.getElementById('app');
    if(a)a.innerHTML='<div class="wrap"><div class="u-card"><h3>状态读取失败</h3>'+
      '<p class="u-hint">'+esc(String(e))+'。CGI 取不到数据时如实显示原因，不静默留一片「—」。</p></div></div>';
  });
})();
