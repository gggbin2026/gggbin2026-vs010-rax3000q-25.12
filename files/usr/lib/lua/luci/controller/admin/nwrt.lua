-- WDS/AP（仿UBNT）· 单包双模式 / 配置写入 / 维护动作
-- 全部挂在 admin 树下继承 root.sysauth；未登录由 dispatcher 302 到登录页。
-- 🔴 零裸 CGI 写入端点、零 eval、零 shell 参数拼接：
--    save 只做「字段白名单 + 值校验 + 原子写 /etc/nwrt/user.cfg」，
--    再调用无参数的 /usr/sbin/nwrt-apply-config 应用。
-- 若所选基线已 ucode 化、未编 luci-compat，本控制器不 dispatch（页面 404）：
--    状态页给 TTYD/SSH 的 nwrt-apply-mode / nwrt-apply-config 兜底，不假装能点。
module("luci.controller.admin.nwrt", package.seeall)

local WHITELIST = {
    "mode","role","peer_ssid","peer_bssid","peer_key","ssid5","key5","ssid2","key2",
    "ch5g","htmode","ch24g","ht24","txpower","wmm","mu_mimo","rssi_thr","rssi_timeout",
    "kick_enabled","kick_rssi",
    "ip","mask","hostname","stp","ntp","theme","dhcp_enabled","dhcp_start","dhcp_limit","dhcp_lease"
}
local LIMITS = {
    mode=function(v) return v=="wds" or v=="ap" end,
    role=function(v) return v=="master" or v=="client" end,
    htmode=function(v) return v=="HE160" or v=="HE80" or v=="HE40" end,   -- 6.12 主线，拒绝 QSDK HT*
    ht24=function(v) return v=="HE40" or v=="HE20" end,
    ch5g=function(v) return v=="auto" or (tonumber(v) and tonumber(v)>=36 and tonumber(v)<=165) end,
    ch24g=function(v) return v=="auto" or (tonumber(v) and tonumber(v)>=1 and tonumber(v)<=13) end,
    txpower=function(v) return v=="auto" or v=="20" or v=="17" or v=="14" end,
    wmm=function(v) return v=="0" or v=="1" end,
    mu_mimo=function(v) return v=="0" or v=="1" end,
    rssi_thr=function(v) local x=tonumber(v); return x~=nil and x>=-100 and x<=-30 end,
    rssi_timeout=function(v) local x=tonumber(v); return x~=nil and x>=1 and x<=60 end,
    kick_enabled=function(v) return v=="0" or v=="1" end,
    kick_rssi=function(v) local x=tonumber(v); return x~=nil and x>=-100 and x<=-30 end,
    stp=function(v) return v=="0" or v=="1" end,
    ip=function(v) return v:match("^%d+%.%d+%.%d+%.%d+$")~=nil end,
    mask=function(v) return v:match("^%d+%.%d+%.%d+%.%d+$")~=nil end,
    ntp=function(v) return v:match("^[%d%.]+$")~=nil end,
    hostname=function(v) return #v<=63 and v:match("^[%w%-]+$")~=nil end,
    theme=function(v) return v=="ubnt" or v=="bootstrap" end,
    dhcp_enabled=function(v) return v=="0" or v=="1" end,
    dhcp_start=function(v) local x=tonumber(v); return x~=nil and x>=1 and x<=253 end,
    dhcp_limit=function(v) local x=tonumber(v); return x~=nil and x>=1 and x<=253 end,
    dhcp_lease=function(v) return v=="1h" or v=="12h" or v=="24h" end
}
local ACTS = {
    health="/usr/sbin/health-fix", wifi="/usr/sbin/wifi-fullspeed",
    oem="/usr/sbin/oem-stack-check", l2="/etc/init.d/l2-guard status",
    logs="/usr/sbin/nwrt-logs"
}

function index()
    entry({"admin","nwrt"}, call("action_switch"), _("WDS / AP 模式"), 80)
    entry({"admin","nwrt","switch"}, call("action_switch"), nil, nil)
    entry({"admin","nwrt","setup"}, call("action_setup"), _("常用设置"), 81)
    entry({"admin","nwrt","probe"}, call("action_probe"), nil, nil)
    entry({"admin","nwrt","save"}, call("action_save"), nil, nil)
    entry({"admin","nwrt","scan"}, call("action_scan"), nil, nil)
    entry({"admin","nwrt","act"}, call("action_act"), nil, nil)
    entry({"admin","vs010_home"}, call("go_home"), _("← 返回网桥/AP 状态"), 1)
end

function go_home()
    local http = require "luci.http"
    local f = io.open("/etc/nwrt/mode","r")
    local m = "wds"
    if f then m = f:read("*l") or "wds"; f:close() end
    if m ~= "ap" then m = "wds" end
    http.redirect(m=="ap" and "/ap/" or "/bridge/")
end

function action_probe()
    local http = require "luci.http"
    http.prepare_content("application/json")
    http.write('{"ok":1,"msg":"LuCI 会话有效"}')
end

local function current_cfg()
    local t = {}
    local f = io.open("/etc/nwrt/user.cfg","r")
    if f then
        for line in f:lines() do
            local k,v = line:match("^([%w_]+)=(.-)$")
            if k then t[k]=v end
        end
        f:close()
    end
    return t
end

function action_save()
    local http = require "luci.http"
    http.prepare_content("text/plain")
    -- admin 树已继承 sysauth；这里再核实一次会话（老仓 r26 口径）。
    -- 不同 LuCI 版本 context.authsession 字段名不一致：只有明确为 false 才拒绝，
    -- 字段不存在时交给 dispatcher 自己的 sysauth，绝不把保存永久锁死。
    local dsp2 = require "luci.dispatcher"
    local ctx = dsp2.context
    if ctx and ctx.authsession == false then
        http.status(403,"Forbidden")
        http.write("FAILED: 未登录（403）")
        return
    end
    local cfg = current_cfg()
    local bad = {}
    for _,k in ipairs(WHITELIST) do
        local v = http.formvalue(k)
        if v ~= nil then
            local fn = LIMITS[k]
            if fn and not fn(v) then
                table.insert(bad, k)
            elseif fn then
                cfg[k] = v
            else
                -- 字符串字段：只允许可打印字符，禁止换行（避免注入 cfg 文件结构）
                if v:find("[\r\n]") then table.insert(bad,k)
                else cfg[k] = v end
            end
        end
    end
    if #bad > 0 then
        http.status(400,"Bad Request")
        http.write("FAILED: 非法字段 " .. table.concat(bad,","))
        return
    end
    -- WDS 模式硬禁止本机 DHCP（前端锁定 + 后端二次强制）
    if cfg.mode == "wds" then cfg.dhcp_enabled = "0" end
    -- 原子写：先写临时文件再 rename，权限 600
    local tmp = "/etc/nwrt/.user.cfg.tmp"
    local f = io.open(tmp,"w")
    if not f then http.write("FAILED: 无法写 /etc/nwrt/user.cfg"); return end
    f:write("# WDS/AP（仿UBNT）· 6.12 用户配置（由 LuCI admin/save 写入）\n")
    for _,k in ipairs(WHITELIST) do
        local v = cfg[k] or ""
        f:write(k .. "=" .. v .. "\n")
    end
    f:close()
    os.rename(tmp, "/etc/nwrt/user.cfg")
    -- 🔴 面板显式改了「管理 IP / 子网掩码」才同步写覆盖文件，用户改过就持久化。
    --    必须用 http.formvalue 判断「本次是否提交」，不能用 cfg["ip"]：
    --    cfg 会合并旧值，若每次保存都写，会把用户串口手写的 .243 悄悄覆盖回 .241。
    --    开机脚本 bridge-netfix / nwrt-apply-config 只读取、绝不删改这两个文件。
    local ip_form   = http.formvalue("ip")
    local mask_form = http.formvalue("mask")
    local function sync_override(path, v)
        if v ~= nil and v ~= "" then
            local o = io.open(path,"w")
            if o then o:write(v .. "\n"); o:close() end
        end
    end
    sync_override("/etc/nwrt/ipaddr",  ip_form)
    sync_override("/etc/nwrt/netmask", mask_form)
    os.execute("chmod 600 /etc/nwrt/user.cfg /etc/nwrt/ipaddr /etc/nwrt/netmask 2>/dev/null")
    local sys = require "luci.sys"
    local out = sys.exec("/usr/sbin/nwrt-apply-config 2>&1")
    http.write(out ~= "" and out or "OK 已保存")
end

function action_scan()
    local http = require "luci.http"
    http.prepare_content("application/json; charset=utf-8")
    local sys = require "luci.sys"
    local out = sys.exec("/usr/sbin/nwrt-scan 2>/dev/null")
    -- 只回显只读扫描结果；不接收任何 HTTP 参数、不写配置（密码必须用户手填后 /save）
    http.write(out ~= "" and out or '{"ok":0,"msg":"扫描无输出","aps":[]}')
end

function action_act()
    local http = require "luci.http"
    http.prepare_content("text/plain")
    local a = http.formvalue("act") or ""
    local cmd = ACTS[a]                       -- 固定命令枚举，零参数拼接
    if not cmd then http.status(400,"Bad Request"); http.write("FAILED: 未知动作"); return end
    local sys = require "luci.sys"
    http.write(sys.exec(cmd .. " 2>&1"))
end

function action_switch()
    local http = require "luci.http"
    local sys  = require "luci.sys"
    local dsp  = require "luci.dispatcher"
    local mode = http.formvalue("mode")
    if mode == "wds" or mode == "ap" then
        sys.exec("/usr/sbin/nwrt-apply-mode " .. mode)   -- mode 已白名单
        http.redirect(dsp.build_url("admin","nwrt") .. "?ok=1")
        return
    end
    local f = io.open("/etc/nwrt/mode","r"); local cur="wds"
    if f then cur=f:read("*l") or "wds"; f:close() end
    if cur ~= "ap" then cur="wds" end
    local df=io.open("/etc/nwrt/default_mode","r"); local def="wds"
    if df then def=df:read("*l") or "wds"; df:close() end
    luci.template.render("admin_nwrt/switch", {cur=cur,def=def,ok=http.formvalue("ok")})
end

function action_setup()
    local http = require "luci.http"
    http.prepare_content("text/html")
    http.write('<!doctype html><meta charset="utf-8"><title>常用设置 · WDS/AP（仿UBNT）</title>')
    http.write('<div style="font:14px system-ui;max-width:720px;margin:30px auto;color:#e8eef7;background:#132033;padding:22px;border-radius:14px">')
    http.write('<a class="vs010Back" style="display:inline-block;border:1px solid #22334b;border-radius:999px;padding:6px 13px;color:#8ab4ff;text-decoration:none" href="/bridge/">← 返回网桥/AP 状态</a>')
    http.write('<h2>常用设置控制台</h2><p>完整控制台在状态页 <code>#setup</code>：')
    http.write('<a style="color:#8ab4ff" href="/bridge/#setup">网桥状态 · 常用设置</a> · ')
    http.write('<a style="color:#8ab4ff" href="/ap/#setup">AP 状态 · 常用设置</a></p>')
    http.write('<p>写入端点 <code>/cgi-bin/luci/admin/nwrt/save</code> 在本 admin 树下继承 sysauth；')
    http.write('本页不重复实现表单，避免两套 UI 打架。</p></div>')
end
