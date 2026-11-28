-- WDS/AP（仿UBNT）· 单包双模式切换
-- 只在 LuCI admin 树下注册，继承 root.sysauth；未登录由 dispatcher 302 到登录页。
-- 若编译时 luci-compat 未编入，本文件不会被 dispatch，请用状态页给出的兜底命令：
--   TTYD / SSH / 串口：nwrt-apply-mode wds  或  nwrt-apply-mode ap
module("luci.controller.admin.nwrt", package.seeall)

function index()
    entry({"admin", "nwrt"}, call("action_switch"), _("WDS / AP 模式"), 80)
    entry({"admin", "nwrt", "switch"}, call("action_switch"), nil, nil)
end

function action_switch()
    local http = require "luci.http"
    local sys  = require "luci.sys"
    local dsp  = require "luci.dispatcher"
    local mode = http.formvalue("mode")
    if mode == "wds" or mode == "ap" then
        -- mode 已白名单，拼接无命令注入面
        sys.exec("/usr/sbin/nwrt-apply-mode " .. mode)
        http.redirect(dsp.build_url("admin", "nwrt") .. "?ok=1")
        return
    end
    local f = io.open("/etc/nwrt/mode", "r")
    local cur = "wds"
    if f then cur = f:read("*l") or "wds"; f:close() end
    if cur ~= "ap" then cur = "wds" end
    local df = io.open("/etc/nwrt/default_mode", "r")
    local def = "wds"
    if df then def = df:read("*l") or "wds"; df:close() end
    luci.template.render("admin_nwrt/switch", { cur = cur, def = def, ok = http.formvalue("ok") })
end
