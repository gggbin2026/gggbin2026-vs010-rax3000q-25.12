# SPDX-License-Identifier: GPL-2.0-or-later
# 第 58 次：机器狗【独立插件包】。用户要求「改成插件，配置我自己来设置」。
# 标准 OpenWrt package：可被 apk/opkg 单独装卸、单独升级；不依赖 feeds。
# 注意：本包【不安装 /etc/config/wdsdog】—— 那份由仓库 files/ overlay 提供
# （冻结基线项），避免 conffile 冲突。用户配置入口是 /etc/wdsdog.conf。
include $(TOPDIR)/rules.mk

PKG_NAME:=bridge-watchdog
PKG_VERSION:=58
PKG_RELEASE:=1
PKGARCH:=all
PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=gggbin2026

include $(INCLUDE_DIR)/package.mk

define Package/bridge-watchdog
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=WDS bridge watchdog (user-configurable plugin)
  DEPENDS:=+uci +bridge
  PKGARCH:=all
endef

define Package/bridge-watchdog/description
  WDS/网桥看门狗：连续不通达到自定义分钟数才重启，支持无线关联 / 对端 ping /
  锚点 ping 三判据、开机宽限、连续重启上限、dryrun 调试、链路本地别名互 ping。
  第 58 次插件化：编译期不注入参数、首启不覆写配置，全部参数由用户自己设置：
    /etc/wdsdog.conf（最高优先，bridge-watchdog config 生成模板）
    uci set wdsdog.main.<key> / bridge-watchdog set-delay 10 等 CLI
  未配置时只待命、绝不重启。
endef

define Build/Compile
endef

define Package/bridge-watchdog/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/wdsdog
	$(INSTALL_BIN) ./files/bridge-watchdog $(1)/usr/sbin/bridge-watchdog
	$(INSTALL_BIN) ./files/bridge-watchdog.init $(1)/etc/init.d/bridge-watchdog
	$(INSTALL_DATA) ./files/USER-CONFIG.md $(1)/etc/wdsdog/USER-CONFIG.md
	$(INSTALL_DATA) ./files/wdsdog.conf.example $(1)/etc/wdsdog/wdsdog.conf.example
endef

$(eval $(call BuildPackage,bridge-watchdog))
