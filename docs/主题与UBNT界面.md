# 为什么是「bootstrap + 独立 UBNT 页」，而不是直接装 Argon

## 老仓库那个坑（两个根因叠加）

1. `/etc/config/luci` 缺 named `config core 'main'`。它是 luci-base 的 conffile，
   sysupgrade 勾「保留配置」或旧 overlay 残留会盖掉编译期文件；此时任何
   `uci set luci.main=...` 都会让 UCI 造出**匿名** config main，LuCI 按名字找
   `main` 找不到 → `dispatcher.lua:427`，整个 `/cgi-bin/luci` 打不开。
2. `mediaurlbase` 写死 `/luci-static/argon`、主题下拉里还列 Argon / Footstrap，
   但这两个是**社区主题，官方 25.12 luci feed 里没有**。写 `=y` 会被
   `make defconfig` 静默丢掉，镜像里只有 bootstrap；配置却指向空气 → 白屏，
   在「系统 → 语言与样式」点一下幽灵主题就 500，之后再也进不去。

## 本仓四层兜住

| 层 | 做法 |
|---|---|
| 编译期 `.config` | 只 `luci-theme-bootstrap=y`；argon/footstrap 显式 `is not set`；`gen-config.sh` 发现 feed 里没有的包会**从 .config 删掉**而不是只打 warning |
| 编译期配置 | `files/etc/config/luci` 写死 named `config core 'main'` + `mediaurlbase=/luci-static/bootstrap`，themes 段只 Bootstrap |
| 每次开机 | `luci-fix`(START=18) 重建 named main、按 `/www/luci-static/` 实际目录生成主题下拉、修正指向空气的 mediaurlbase、清 LuCI 缓存、`uhttpd.main.index_page=index.html` |
| 页面本身 | `/ubnt/`、`/bridge/`、`/ap/` 是独立静态页 + 只读 CGI，**不依赖 LuCI 主题**，LuCI 万一挂了也照常能开；CGI 取不到数据时显示明确原因 |

## UBNT 皮肤

直接移植 5.4 老仓的 `vs010-ubnt.css` + `vs010-ubnt-skin.js`（见
`reference/old54/`），零侵入：

- 只定义 `u-*` 新类与 `body.ubnt-body` 布局，**绝不覆盖两页原有选择器**；
- 注入器只搬移 DOM 外层，不删、不重命名、不改写任何原有节点与 id；
- `window.fetch` hook + `Response.clone()` 读一份，**零额外请求**；
- 只接主 CGI（本仓 `/cgi-bin/state`，另留 `bridge`/`apstatus` 兼容别名），
  **绝不**调用任何写入端点；未登录只读；
- 宽屏 ≥900px 左侧 220px 深色栏，<900px 折叠顶部横向 pill；
- 六个互访入口（含「⇄ 模式切换」→ `/cgi-bin/luci/admin/nwrt`）+ 登录/退出 + TTYD :7681；
- 竖屏按钮条 `overflow-x:auto` 横向滚动，绝不 `display:none`。

状态页渲染由 `www/app.js` 完成，字段与 `www/cgi-bin/state` 一一对应；
读不到传感器如实显示「—」，绝不写假数值。非当前模式的页显示一条非强制提示条，
不 2 秒踢走（保留三页全互访）；「服务与防护」里给 `nwrt-apply-mode` 命令兜底，
防止 `luci-compat` 未编入时切换页 404 却假装能点。非当前模式的页显示一条非强制提示条，
不 2 秒踢走（保留三页全互访）；「服务与防护」里给 `nwrt-apply-mode` 命令兜底，
防止 `luci-compat` 未编入时切换页 404 却假装能点。非当前模式的页显示一条非强制提示条，
不 2 秒踢走（保留三页全互访）；「服务与防护」里给 `nwrt-apply-mode` 命令兜底，
防止 `luci-compat` 未编入时切换页 404 却假装能点。非当前模式的页显示一条非强制提示条，
不 2 秒踢走（保留三页全互访）；「服务与防护」里给 `nwrt-apply-mode` 命令兜底，
防止 `luci-compat` 未编入时切换页 404 却假装能点。
