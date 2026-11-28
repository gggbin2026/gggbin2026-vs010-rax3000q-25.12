/* r29.9 · 三页共用 UBNT 皮肤注入器（零侵入）
   🔴 只在 /bridge/ /ap/ 两页外层包一层侧栏 + 顶栏 KPI：
      · 不删除、不重命名、不改写任何原有 DOM 节点与 id（两页几百行 JS 全部照常命中）
      · 不覆盖两页原有 CSS 选择器，只新增 u-* 类
      · 不调用任何 admin 写入端点；未登录仍只读
      · 数据靠 hook 原生 fetch + Response.clone() 拿（只接主 CGI），零额外请求、不消费原页面 body
   放 <head> 同步加载，以便先于页面内联脚本完成 fetch hook。 */
(function(){
  var D=document, LAST=null, READY=false;
  var PATH=D.location.pathname||'';
  var IS_AP=/\/ap\//.test(PATH);
  var PAGE=IS_AP?'ap':'bridge';
  var NAV=[
    ['/ubnt/','◧','概览'],
    ['/bridge/','⇄','网桥状态'],
    ['/ap/','≋','AP 状态'],
    ['#vs010-setup','⚙','常用设置'],
    ['/cgi-bin/luci/','↗','高级后台']
  ];
  function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]});}
  function el(tag,cls,html){var e=D.createElement(tag);if(cls)e.className=cls;if(html!=null)e.innerHTML=html;return e;}

  function navHTML(){
    var h='';
    for(var i=0;i<NAV.length;i++){
      var a=NAV[i], on=(a[0]==='#vs010-setup')?false:((a[0]==='/ubnt/'&&/\/ubnt\//.test(PATH))||
        (a[0]==='/bridge/'&&!IS_AP&&!/\/ubnt\//.test(PATH))||(a[0]==='/ap/'&&IS_AP));
      h+='<a href="'+a[0]+'"'+(on?' class="on"':'')+'><b>'+a[1]+'</b>'+a[2]+'</a>';
    }
    return h;
  }
    /* r29.10：全界面互访按钮条 —— 任何尺寸都能一键去 4 类界面，竖屏横向滚动不隐藏 */
    var JUMP=[
      ['/ubnt/','◧ 概览'],
      ['/bridge/','⇄ 网桥状态'],
      ['/ap/','≋ AP 状态'],
      ['/cgi-bin/luci/admin/status/vs010_setup','⚙ 常用设置'],
      ['/cgi-bin/luci/','↗ OpenWrt / LuCI']
    ];
    function jumpHTML(){
      var h='';
      for(var i=0;i<JUMP.length;i++){
        var a=JUMP[i], on=(a[0]==='/ubnt/'&&/\/ubnt\//.test(PATH))||
          (a[0]==='/bridge/'&&!IS_AP&&!/\/ubnt\//.test(PATH))||
          (a[0]==='/ap/'&&IS_AP);
        h+='<a href="'+a[0]+'"'+(on?' class="on"':'')+'>'+a[1]+'</a>';
      }
      h+='<a class="u-auth" id="uAuthJump" href="/cgi-bin/luci/">🔑 登录 LuCI</a>';
      return h;
    }
    /* 登录态：复用共用控制台已发的 probe 响应（hook + clone，零新增请求）。
       未登录→「登录 LuCI」，已登录→「已登录 · 退出」；不碰任何写入端点。 */
    function auth(on){
      var href=on?'/cgi-bin/luci/admin/logout':'/cgi-bin/luci/';
      var txt=on?'🔑 已登录 · 退出':'🔑 登录 LuCI';
      var ids=['uAuth','uAuthJump'];
      for(var i=0;i<ids.length;i++){
        var e=D.getElementById(ids[i]);
        if(e){e.href=href;e.textContent=txt;e.className=on?'u-btn u-auth on':'u-auth';}
      }
      var st=D.getElementById('uAuthState');
      if(st){st.textContent=on?'已登录 · 可保存设置':'未登录 · 只读';
             st.className=on?'u-authstate on':'u-authstate';}
    }


  function build(){
    if(D.body.classList.contains('ubnt-body')) return;
    D.body.classList.add('ubnt-body');
    /* 侧栏 */
    var side=el('aside','u-side');
    side.innerHTML='<div class="u-brand"><i></i><div>WDS/AP（仿UBNT）<small>NWRT · UBNT STYLE</small></div></div>'+
      '<div class="u-lbl">状态</div><nav class="u-nav">'+navHTML()+'</nav>'+
      '<div class="u-lbl u-ext">外部</div><nav class="u-nav u-ext">'+
      '<a href="/cgi-bin/luci/"><b>↗</b>高级设置后台</a>'+
      '<a href="/bridge/"><b>↗</b>网桥状态</a><a href="/ap/"><b>↗</b>AP 状态</a></nav>'+
      '<div class="u-foot">WDS/AP（仿UBNT）· 三入口共存<br>5.8G 160MHz / 2.4G 20·40 共存<br>未登录只读 · 设置需 LuCI 会话</div>';
    /* 顶栏 KPI */
    var top=el('header','u-top');
    top.innerHTML='<span class="u-dot"></span><h1 id="uDev">'+(IS_AP?'AP 控制台':'网桥状态')+'</h1>'+
      '<span class="u-pill" id="uMode">'+(IS_AP?'AP 模式':'WDS 网桥')+'</span>'+
        '<span class="u-pill u-prod">WDS/AP · 仿 UBNT</span>'+
      '<span class="u-kpi" id="uCli"><i></i>客户端 <b>—</b></span>'+
      '<span class="u-kpi" id="uCpu"><i></i>CPU <b>—</b></span>'+
      '<span class="u-kpi" id="uMem"><i></i>内存 <b>—</b></span>'+
      '<span class="u-sp"></span>'+
      '<span class="u-kv">时间 <b id="uTime">—</b></span>'+
      '<span class="u-kv">运行 <b id="uUp">—</b></span>'+
      '<span class="u-authstate" id="uAuthState">未登录 · 只读</span>'+
      '<a class="u-btn u-auth" id="uAuth" href="/cgi-bin/luci/">🔑 登录 LuCI</a>'+
      '<button class="u-btn" id="uRefresh">立即刷新</button>';
    var main=el('div','u-main');
    var content=el('div','u-content');
    /* 把原有 body 子节点整体搬进 u-content（script 留在原位，不移动不重执行） */
    var nodes=[].slice.call(D.body.childNodes);
    for(var i=0;i<nodes.length;i++){
      var n=nodes[i];
      if(n.nodeType===1 && n.tagName==='SCRIPT') continue;
      if(n===side||n===top||n===main) continue;
      content.appendChild(n);
    }
    var jump=el('div','u-jump'); jump.innerHTML=jumpHTML();
    main.appendChild(top); main.appendChild(jump); main.appendChild(content);
    D.body.insertBefore(side,D.body.firstChild);
    D.body.appendChild(main);
    var btn=D.getElementById('uRefresh');
    if(btn) btn.onclick=function(){ try{ if(typeof window.load==='function') window.load(); else D.location.reload(); }
      catch(e){ D.location.reload(); } };
    READY=true;
    if(LAST) paint(LAST);
  }

  /* 从现有 CGI 的 JSON 里挑字段填 KPI；字段缺失一律优雅降级，不抛错 */
  function paint(j){
    LAST=j; if(!READY) return;
    try{
      var y=j.sys||{}, t=function(id,v){if(v==null||v==='')return;var e=D.getElementById(id);
        if(e&&e.textContent!==v)e.textContent=v;};   /* 🔴 空值不覆盖：多个 CGI 响应不会互相冲掉 */
      t('uDev',j.host||j.model||j.board);
      t('uTime',j.time);
      t('uUp',j.uptime);
      var st=j.stations||j.clients||(j.wds&&j.wds.stations)||[];
      var ce=D.getElementById('uCli'); if(ce){var b=ce.querySelector('b');if(b)b.textContent=st.length+' 台';}
      var cpu=parseInt(y.cpu_usage_pct,10), mem=parseInt(y.mem_used_pct,10);
      var c=D.getElementById('uCpu'), m=D.getElementById('uMem');
      function set(e,v){if(!e||isNaN(v))return;var b=e.querySelector('b');if(b)b.textContent=v+'%';
        e.className='u-kpi'+(v>=80?' r':v>=60?' w':'');}
      set(c,cpu); set(m,mem);
    }catch(e){}
  }

  /* 🔴 零额外请求：包一层 fetch，用 clone() 读一份，原页面的 .then(r=>r.json()) 完全不受影响 */
  var _f=window.fetch;
  if(_f){
    window.fetch=function(u,o){
      var p=_f.apply(this,arguments);
      try{
        var s=String(u);
        if(/cgi-bin\/(bridge|apstatus)/.test(s)){
          p.then(function(r){
            try{ r.clone().json().then(function(j){paint(j);}).catch(function(){}); }catch(e){}
          }).catch(function(){});
        }
          else if(/vs010_setup\/probe/.test(s)){
            p.then(function(r){
              try{ r.clone().json().then(function(j){auth(!!j.ok);}).catch(function(){}); }catch(e){}
            }).catch(function(){});
          }
      }catch(e){}
      return p;
    };
  }
  /* 兜底：页面没发起 CGI 请求（如离线/异常）也给个静态壳 */
  if(D.readyState==='loading') D.addEventListener('DOMContentLoaded',build); else build();
  window.__VS010_UBNT__={page:PAGE,paint:paint};
})();
