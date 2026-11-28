# 主题：UBNT（仿 UniFi）· 深色

用户要的就是**这个 UBNT 主题**。现在的落地口径：

| 位置 | 主题 |
|---|---|
| `/ubnt/`、`/bridge/`、`/ap/` 三页状态页 | **UBNT（仿 UniFi）深色**：左侧蓝条侧栏、深色卡片、胶囊 KPI / 按钮 / 输入项、六入口互访 |
| `/cgi-bin/luci/` 后台 | **UBNT（仿 UniFi）深色**：真·主题目录 `/www/luci-static/ubnt/`，主题下拉显示 `UBNT` |
| 底层资源 | 官方 `luci-theme-bootstrap`（**必须编入**，见下） |

## 为什么这样不会白屏（老仓那个坑）

老仓「主题页进不去 / dispatcher.lua:427」是两个根因叠加：

1. `/etc/config/luci` 缺 named `config core 'main'`，`uci set luci.main=...` 会造出匿名
   section，LuCI 按名字找不到 `main` → 427，整个 `/cgi-bin/luci` 打不开。
2. `mediaurlbase` 写死 `/luci-static/argon`、下拉里还列 Argon / Footstrap，
   但这两个是**社区主题，官方 25.12 luci feed 里没有**。写 `=y` 会被
   `make defconfig` 静默丢掉，镜像里只有 bootstrap；配置却指向空气 → 白屏 / 500。

本仓三层兜住：

| 层 | 做法 |
|---|---|
| 编译期 | `luci-theme-bootstrap=y` 保留（**底资源**），argon/footstrap 显式 `is not set`；UBNT 主题由本仓 `files/` 注入，不依赖任何第三方 feed |
| 主题文件 | `files/www/luci-static/ubnt/cascade.css` 第一行 `@import url("/luci-static/bootstrap/cascade.css")`。被导入 CSS 里的相对 `url()` 基于**被导入文件自身 URL** 解析，所以图片/字体全部正确落在官方 bootstrap 目录，无需复制文件；后面叠 UBNT 深色覆盖 |
| 出厂配置 | `files/etc/config/luci` 写死 named `config core 'main'` + `mediaurlbase='/luci-static/ubnt'` + 标准 `config internal 'themes'`（option `UBNT`、`Bootstrap`，值都是真实路径） |
| 每次开机 | `luci-fix`(START=18) 校验 `ubnt/cascade.css` **和** `bootstrap/cascade.css` 都在才用 ubnt，任一缺失立刻回退 bootstrap 并记 WARN；重建 named main、按实际目录重建下拉、清 LuCI 缓存、`uhttpd.main.index_page=index.html` |
| 页面本身 | 三页状态页是独立静态页 + 只读 CGI，**不依赖 LuCI 主题**，LuCI 万一挂了也照常能开 |

⚠ **别删 `common.seed` 里的 `luci-theme-bootstrap=y`**：它是 UBNT 主题 `@import`
的底资源，删了就是真的「指向空气」。`gen-config.sh` 有硬校验会拦。
`verify.sh` 也把这条列为阻断项。

## 切回官方原样

面板 `⑦ 主题与界面` 把「LuCI 主题」选成 `Bootstrap（官方原样）` → 保存，
`nwrt-apply-config` 会把 `mediaurlbase` 指回 `/luci-static/bootstrap`。
或直接串口：`uci set luci.main.mediaurlbase='/luci-static/bootstrap'; uci commit luci`。
三页状态页**永远是 UBNT 风格**，不受这个开关影响。

## 出厂账号（同一套，SSH / LuCI / TTYD / 串口）

```
root / admin
```

`nwrt-passwd`(START=19) 在 root 密码为空 / 锁定（`!`、`*`、`x`）时设为 `admin`；
用户自己改过就保持不变，开机不会反复盖回去。改密码请走 LuCI
「系统 → 管理权」或 `passwd`，**不要**写进 `/etc/nwrt/user.cfg`（它是明文配置）。
Web 若仍报 427：串口 `sh /usr/sbin/health-fix`（或单跑 `luci-fix`），刷新即可，不用重刷。
