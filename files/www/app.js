/* WDS/AP（仿UBNT）· 6.12 单包双模式状态页：只读 CGI，零写入、零额外请求
   vs010-ubnt-skin.js 已把本页外层包成 UBNT 深色侧栏 + 顶栏 KPI。
   模式切换走 LuCI admin 树（sysauth）或 TTYD/SSH 固定命令，本页绝不写配置。 */
(function(){
  var D=document;
  function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]});}
  function n(v,f){return (v==null||v===''||v==='?')?'—':(f?f(v):esc(v));}
  function card(title,rows){
    return '<section class="u-card"><h3>'+esc(title)+'</h3><table class="u-tbl">'+
      rows.map(function(r){return '<tr><td>'+esc(r[0])+'</td><td>'+r[1]+'</td></tr>'}).join('')+'</table></section>';
  }
  function pill(v,t){return '<span class="u-pill'+(t?' '+t:'')+'">'+esc(v)+'</span>';}
  function rows(j){
    var s=j.sys||{}, p=j.ports||[], r=j.radios||[], ns=j.nss||{}, tk=j.tick||{};
    var mode=j.mode||'wds', page=D.body.getAttribute('data-page')||'';
    var out=[];
    // 非当前模式的页面：只提示、不强制跳走（保留三界面全互访）
    var mismatch=(page==='bridge'&&mode==='ap')||(page==='ap'&&mode==='wds');
    if(mismatch){
      out.push('<section class="u-card u-hintbar"><b>当前是 '+(mode==='ap'?'AP':'WDS 网桥')+' 模式</b>，'+
        '这是'+(page==='bridge'?'网桥状态':'AP 状态')+'页，数据仍为只读实况。'+
        ' <a class="u-btn" href="/cgi-bin/luci/admin/nwrt">⇄ 去切换模式</a></section>');
    }
    out.push(card('系统 · SYSTEM',[
      ['产品', esc(j.product||'WDS/AP（仿UBNT）')],
      ['当前模式', pill(mode==='ap'?'AP 模式':'WDS 网桥')],
      ['出厂默认', pill((j.default_mode||'wds')==='ap'?'AP':'WDS 网桥','w')+' <small>刷机不勾「保留配置」回到默认</small>'],
      ['机型 / 主机名', esc(j.model||'')+' / '+esc(j.host||'')],
      ['内核', '<code>'+esc(j.kernel||'')+'</code>'],
      ['源码基线', esc(j.baseline||'')+' <small>'+esc((j.source_commit||'').slice(0,12))+'</small>'],
      ['编译标识', esc(j.build||'')],
      ['时间 / 运行', esc(j.time||'')+' · '+esc(j.uptime||'')],
      ['CPU / 内存', n(s.cpu_usage_pct,function(v){return v+'%'})+' / '+n(s.mem_used_pct,function(v){return v+'%'})],
      ['CPU 温度', esc(s.cpu_temp||'—')],
      ['射频温度', esc((s.radio_temps||[]).join(' / ')||'—')]
    ]));
    var pr=p.map(function(x){return '<tr><td>'+esc(x.name)+'</td><td>'+esc(x.speed||'—')+
      '</td><td>'+(x.carrier?pill('已连接'):pill('未连接','w'))+'</td></tr>'}).join('')||
      '<tr><td colspan="3">—（读不到端口）</td></tr>';
    out.push('<section class="u-card"><h3>网口状态 · PORT STATUS</h3><table class="u-tbl"><tr><th>端口</th><th>速率</th><th>链路</th></tr>'+pr+'</table>'+
      '<p class="u-hint">判速看 eth0/eth1，不看 br-lan：被 NSS 卸载的流量不经过 Linux 网桥。</p></section>');
    var rr=r.map(function(x){return '<tr><td>'+esc(x.band||'')+'</td><td>'+esc(x.ssid||'—')+
      '</td><td>'+esc(x.channel||'—')+'</td><td>'+esc(x.htmode||'—')+'</td><td>'+esc(x.status||'—')+'</td></tr>'}).join('')||
      '<tr><td colspan="5">—（射频未 probe 或 iwinfo 不可用）</td></tr>';
    out.push('<section class="u-card"><h3>无线射频 · RADIO</h3><table class="u-tbl"><tr><th>频段</th><th>SSID</th><th>信道</th><th>频宽</th><th>状态</th></tr>'+rr+'</table>'+
      '<p class="u-hint">CN + HE160 需约 60 秒 DFS CAC，期间 5G 不可见、2.4G 先起；改 HE80 可免等但吞吐少约 1/3。</p></section>');
    out.push(card('NSS 加速 · DATA PLANE',[
      ['加速栈', ns.present?pill('已加载'):pill('未加载 / 无 NSS 基线','w')],
      ['固件版本', esc(ns.fw||'—')],
      ['加速连接数', esc(ns.conn||'—')],
      ['NSS 占用', esc(ns.load||'—')]
    ]));
    out.push(card('巡检 / 机器狗 · TICK',[
      ['单常驻', tk.enabled?pill('已启用'):pill('未启用','w')],
      ['自愈动作', tk.dryrun?pill('dryrun=1 · 只记录','w'):pill('允许限频 reload')],
      ['最近一轮', '<code>'+esc(tk.last||'—')+'</code>'],
      ['红线', '不 wifi down · 不重启 · 30 分钟内最多一次 reload']
    ]));
    var target=(mode==='wds'?'ap':'wds');
    out.push(card('服务与防护 · SERVICES',[
      ['SSH / 串口', esc(j.ssh||'dropbear · ttyMSM0')],
      ['TTYD', '<a class="u-btn" href="http://'+esc(location.hostname)+':7681/" target="_blank">打开 :7681</a>'],
      ['LuCI 后台', '<a class="u-btn" href="/cgi-bin/luci/">打开高级后台</a>'],
      ['⇄ 模式切换', '<a class="u-btn" href="/cgi-bin/luci/admin/nwrt">LuCI 里切换</a> '+
        '<button class="u-btn" id="uCopyMode" data-cmd="nwrt-apply-mode '+target+'">复制 '+target.toUpperCase()+' 命令</button>'],
      ['DHCP 防护', esc(j.guard||'—')],
      ['防火墙 / IPv6', pill('已关')+' / '+pill('已关')],
      ['本机 DHCP 服务端', pill('关闭')]
    ]));
    return '<div class="u-grid">'+out.join('')+'</div>';
  }
  function render(j){
    var e=D.getElementById('app'); if(!e)return;
    e.innerHTML='<div class="wrap"><h2 class="u-h2">设备状态 · READ ONLY · 单包双模式</h2>'+rows(j)+
      '<p class="u-hint">本页只读。切模式走已登录的 <a href="/cgi-bin/luci/admin/nwrt">LuCI「WDS / AP 模式」</a>，'+
      '或 TTYD/SSH 执行 <code>nwrt-apply-mode wds|ap</code>；若 LuCI 页 404（该基线未编 luci-compat），用后者即可，'+
      '<b>不用重刷</b>。改 SSID / 密码 / 信道在 LuCI 后台或串口。</p></div>';
    var b=D.getElementById('uCopyMode');
    if(b) b.onclick=function(){
      var c=b.getAttribute('data-cmd'), ta=D.createElement('textarea');
      ta.value=c; D.body.appendChild(ta); ta.select();
      try{ D.execCommand('copy'); b.textContent='已复制：'+c; }catch(err){ b.textContent=c; }
      D.body.removeChild(ta);
    };
  }
  fetch('/cgi-bin/state').then(function(r){return r.json()})
    .then(render)
    .catch(function(e){var a=D.getElementById('app');if(a)a.innerHTML=
      '<div class="wrap"><section class="u-card"><h3>状态读取失败</h3>'+
      '<p class="u-hint">'+esc(String(e))+'。CGI 取不到数据时如实显示原因，不静默留一片「—」。</p></section></div>';});
})();
