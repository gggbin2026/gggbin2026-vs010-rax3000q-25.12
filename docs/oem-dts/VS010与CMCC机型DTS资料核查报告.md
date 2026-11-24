# VS010 与 CMCC IPQ5018/IPQ5000 路由器设备树（DTS）资料核查报告

## 摘要

“CMCC VS010”这个说法本身是错的：VS010 是中国联通（CUCC）随家宽配送的 AX3000 路由器，SoC 为 Qualcomm IPQ5018（市场常写作 IPQ5000），256MB DDR3L、128MB SPI-NAND、QCA8337 交换芯片、QCN6102 5G 射频、1WAN+3LAN；中国移动（CMCC）侧外形与规格相近的机型是 PZ-L8、RAX3000Q/QY、MR3000D-CI，另有一台同名易混的 A10 其实是 MT7981B 方案（mediatek/filogic 目标），与 IPQ5018 无关[1][9]。

公开可查的 VS010 设备树共三份，质量差距很大。maxdarksol 版直接从闭源 Nwrt 固件的 `/sys/firmware/fdt` 反编译，并用第三方 U-Boot 启动信息交叉核对，把直连 CPU 的 LAN3 交换为 WAN 口，是三者中唯一与量产固件行为一致的基线[1]；xiangye277 版被原帖作者明确指出 GPIO 与 switch port 有误[1]；whmzsu 版自述“基于 CMCC PZ-L8 设备树改编，GPIO 可能与实际 VS010 有差异，首次刷入有砖风险”[2]。

CMCC 侧已有两份进入 OpenWrt 主线的设备树：PZ-L8（2025年11月12日合入）与 RAX3000Q/QY（2026年9月27日合入，因 256MiB 内存而在 DTS 中关闭 ath11k 防 OOM，MAC 从 ART 起始偏移推导）[4][5]；MR3000D-CI 于2026年2月17日合入，内存 512MiB，WiFi 正常开启[6]。

恩山已有实测互刷变砖案例：VS010 刷入 CMCC RAX3000Q 的 U-Boot 与大分区后，因复位键（mesh 复合键）GPIO 不一致，开机持续判定“复位键按下”而循环重启，TTL 无法中断，最终需编程器[3]。结论：编译 VS010 固件一律以 maxdarksol 版为基线，刷机前必须完整备份 mtd0..mtd23（尤其 mtd13 `0:ART` 与 mtd14 `0:TRAINING`）。

## 一、命名混淆：VS010 属于联通而非移动

所有检索与刷机讨论的第一步，是把运营商归属摆正，否则下载的固件、U-Boot 与分区表从根上就不匹配。OpenWrt 官方论坛帖子标题即“China Unicom VS010 Support”，发帖人 maxdarksol 说明其机器“currently running the closed-source Nwrt”，并附设备信息截图标注“CUCC VS010”[1]。国内教程（如个人博客 TTL 刷机文）同样以“联通 VS010”称呼，刷机包文件名为 `Nwrt-2025-01-01-openwrt-ipq50xx-ipq50xx_32-cucc_vs010-squashfs-nand-factory.bin`，其中 `cucc_vs010` 即中国联通标识[10]。

表1：VS010 与易混 CMCC 机型的归属与平台

| 机型 | 运营商 | SoC | 内存/闪存 | OpenWrt 目标 | 主线状态 |
|---|---|---|---|---|---|
| VS010 | 中国联通 | IPQ5018/IPQ5000 | 256MB/128MB SPI-NAND | qualcommax/ipq50xx | 未合入，仅第三方 DTS |
| PZ-L8 | 中国移动 | IPQ5000 | 256MiB/128MiB SPI-NAND | qualcommax/ipq50xx | 2025年11月12日合入 |
| RAX3000Q/QY | 中国移动 | IPQ5000 | 256MiB/128MiB SPI-NAND | qualcommax/ipq50xx | 2026年9月27日合入 |
| MR3000D-CI | 中国移动 | IPQ5018 | 512MiB/128MiB SPI-NAND | qualcommax/ipq50xx | 2026年2月17日合入 |
| A10 | 中国移动 | MediaTek MT7981B | 256MB/128MB SPI-NAND | mediatek/filogic | 24.10.1 起支持 |

表中 PZ-L8 规格取自其合入提交说明（ESMT F50D1G41LB 闪存、QCN6102、QCA8337、2 LED + 2 按键、UART 115200n8）[4]；RAX3000Q/QY 取自提交日志（GD5F1GQ5REYIG 闪存、3 颗 RGB LED、reset 与 mesh 配对键）[5]；MR3000D-CI 取自 lede-commits 邮件存档[6]；A10 取自 OpenWrt 官方硬件库，交换芯片为 MT7531AE、无线为 MT7976C、驱动 mt76[9]。

这一区分有直接后果：CMCC 三款 IPQ 机器的 DTS 可以互为参考，但拿它们的固件或 U-Boot 直接刷 VS010，等于把别的按键与网口排序写进了一块引脚不同的板子。A10 连 SoC 厂商都不同，任何 ipq5018-*.dts 都不适用于它。

## 二、VS010 三份 DTS 的来源与可信度链条

三份 VS010 设备树不是并列关系，而是一条“试错—纠错—定稿”的时间链，理解这条链比逐行读代码更重要。

### maxdarksol 版：从运行中的固件反推

maxdarksol 在论坛首帖给出了完整取证路径：机器先刷第三方 U-Boot（1980490718/u-boot-2016），从 U-Boot 启动打印拿到内存、闪存与网口信息；再把闭源 Nwrt 固件运行时导出的 `/sys/firmware/fdt` 用 dtc 反汇编回 DTS，“confirming that the information in uboot is correct”[1]。由此产出的 `vs010.dts` 有一个关键设计：交换了 WAN 与 LAN3 的配置，把直连 CPU 的那个口（LAN3）当作 WAN 使用[1]。独立教程从用户视角印证了这一点——刷入 NWRT 后“最后一个 LAN3 口会变成 WAN 口”，需把原 WAN 口当 LAN 用[10]。官方分区表（第四章）也是同一帖给出，与反编译结果同源。

### xiangye277 版：被作者本人否定的早期尝试

原帖明确写道，该 DTS 的“gpio and switch port configurations … are not correct”，并指向该仓库 issue #1 作为错误记录[1]。这类早期文件常见于新机适配初期照搬 Redmi AX3000 等公版设备树，价值在于说明“哪些坑已经有人踩过”，不适合作为编译基线。

### whmzsu 版：PZ-L8 改编的“能亮但不对”风险

whmzsu 仓库 README 在刷写说明下给出警告：此固件基于 CMCC PZ-L8 设备树改编，GPIO 配置可能与实际 VS010 有差异，首次刷入有砖风险，建议备好 TTL 串口线救砖；仓库文件清单为 `ipq5018-vs010.dts`、`FLASHING.md`、`flash.py`、`poll_build.py` 与 GitHub Actions 工作流，刷入方式是登录 192.168.2.1 后台拿 stok 后上传 .img[2]。它的价值在于提供了一套可直接 fork 的自动化编译流水线，危险在于 PZ-L8 的 reset 为 GPIO33、WPS 为 GPIO34、WAN 绿灯 GPIO35、LAN 红灯 GPIO30、QCA8337 复位 GPIO26（见第五章），这些数值没有任何证据表明与 VS010 一致，而恩山案例已经证明“按键 GPIO 不一致”足以让机器陷入重启循环[3]。

### 关联 U-Boot

三方 U-Boot 仓库 `1980490718/u-boot-2016` 是 maxdarksol 取证链条的一环，也是国内 TTL 刷机教程的标准前置：教程要求把 `u-boot.mbn` 与大分区表 `mibib.bin` 一并经 TFTP 刷入，之后才能写 NAND 固件[10][1]。需要注意，换了 U-Boot 与 MIBIB 之后，分区布局就不再是第四章的原厂表，回刷原厂固件必须按同一套大分区重算偏移。

### 三份 DTS 全文抓取结果（硬要求逐项交代）

本报告对下列地址逐一尝试了直连 raw、GitHub blob 网页、jsDelivr（cdn.jsdelivr.net/gh）、ghproxy.net、gh-proxy.com、raw.gitmirror.com、kkgithub.com 七类通道，抓取日期均为2026年11月24日；三份文件的 GitHub 页面与全部镜像通道均被对方或中间层拒绝，**未取到全文**。按委托要求不臆造内容，此处给出可点击原始链接与已由官方论坛/仓库 README 交叉确认的行为描述，全文请以链接为准：

- maxdarksol 版（未取到全文）：[vs010.dts（GitHub blob）](https://github.com/maxdarksol/vs010-openwrt/blob/main/vs010.dts)｜[raw 直链](https://raw.githubusercontent.com/maxdarksol/vs010-openwrt/main/vs010.dts)。已确认特征：由 Nwrt `/sys/firmware/fdt` 反编译，WAN 与 LAN3 对调，LAN3（直连 CPU）作 WAN[1]。
- xiangye277 版（未取到全文）：[ipq5018-vs010.dts（GitHub blob）](https://github.com/xiangye277/vs010-openwrt/blob/main/ipq5018-vs010.dts)｜[raw 直链](https://raw.githubusercontent.com/xiangye277/vs010-openwrt/main/ipq5018-vs010.dts)。已确认特征：GPIO 与 switch port 配置错误，见[issue #1](https://github.com/xiangye277/vs010-openwrt/issues/1)[1]。
- whmzsu 版（未取到全文）：[ipq5018-vs010.dts（GitHub blob）](https://github.com/whmzsu/vs010-openwrt/blob/main/ipq5018-vs010.dts)｜[raw 直链](https://raw.githubusercontent.com/whmzsu/vs010-openwrt/main/ipq5018-vs010.dts)。已确认特征：基于 CMCC PZ-L8 设备树改编[2]。

可操作的替代取法（未逐条验证，标注“未核实”）：在本地执行 `git clone https://github.com/maxdarksol/vs010-openwrt.git` 即可拿到与网页同源的文件；或在已刷 Nwrt 的机器上执行 `dtc -I fs -O dts /sys/firmware/fdt`，可复现 maxdarksol 版的原始素材。

## 三、CMCC 侧上游 DTS：主线与 QSDK 两条线

CMCC 三款 IPQ 机器在 OpenWrt 中有完整的主线设备树，这是 VS010 适配最有价值的“参照系”，但参照不等于照抄。

### PZ-L8：主线全文（已取到）

PZ-L8 由 Chang Liu 提交，PR 链接指向 openwrt/openwrt#20928，2025年11月12日合入主线；提交时路径为 `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-pz-l8.dts`，此后 qualcommax 目标统一迁至 `target/linux/qualcommax/dts/ipq5018-pz-l8.dts`（当前 git 网页树即此后一路径）[4]。同系列 PR 还配套向 openwrt/firmware_qca-wireless 提交了 “Add IPQ5018 BDF for CMCC PZ-L8”（#106），说明其 WiFi 依赖外置 BDF 板数据[4]。以下全文取自 OpenWrt 源码镜像 git.lede-project.org 的当前树，抓取日期2026年11月24日，原文保持单行紧凑格式：

```dts
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
/dts-v1/;
#include "ipq5018.dtsi"
#include "ipq5018-ess.dtsi"
#include "ipq5018-qcn6122.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>
/ {
	model = "CMCC PZ-L8";
	compatible = "cmcc,pz-l8", "qcom,ipq5018";
	aliases{
		serial0 = &blsp1_uart1;
		led-boot = &led_wan;
		led-failsafe = &led_lan;
		led-running = &led_wan;
		led-upgrade = &led_lan;
		label-mac-device = <&gmac0>;
	};
	chosen {
		bootargs-append = " root=/dev/ubiblock0_1 swiotlb=1 coherent_pool=2M";
		stdout-path = "serial0:115200n8";
	};
	keys {
		compatible = "gpio-keys";
		pinctrl-0 = <&button_pins>;
		pinctrl-names = "default";

		reset-button {
			label = "reset";
			gpios = <&tlmm 33 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
		};
		wps-button {
			label = "wps";
			gpios = <&tlmm 34 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_WPS_BUTTON>;
		};
	};
	leds {
		compatible = "gpio-leds";
		pinctrl-0 = <&led_pins>;
		pinctrl-names = "default";

		led_wan: led-0 {
			gpios = <&tlmm 35 GPIO_ACTIVE_LOW>;
			color = <LED_COLOR_ID_GREEN>;
			function = LED_FUNCTION_WAN;
			default-state = "off";
		};
		led_lan: led-1 {
			gpios = <&tlmm 30 GPIO_ACTIVE_LOW>;
			color = <LED_COLOR_ID_RED>;
			function = LED_FUNCTION_LAN;
		};
	};
};
&sleep_clk {
	clock-frequency = <32000>;
};
&xo_board_clk {
	clock-div = <4>;
	clock-mult = <1>;
};
&blsp1_uart1 {
	status = "okay";
	pinctrl-0 = <&serial_0_pins>;
	pinctrl-names = "default";
};
&prng {
	status = "okay";
};
&qfprom {
	status = "okay";
};
&qpic_bam {
	status = "okay";
};
&qpic_nand {
	pinctrl-0 = <&qpic_pins>;
	pinctrl-names = "default";
	status = "okay";

	nand@0 {
		compatible = "spi-nand";
		reg = <0>;
		nand-ecc-engine = <&qpic_nand>;
		nand-bus-width = <8>;
		partitions {
			compatible = "qcom,smem-part";
			partition-art {
				label = "0:art";
				read-only;
				nvmem-layout {
					compatible = "fixed-layout";
					#address-cells = <1>;
					#size-cells = <1>;
					hw_mac_addr: mac-address@0 {
						compatible = "mac-base";
						reg = <0x0 0x6>;
						#nvmem-cell-cells = <1>;
					};
				};
			};
		};
	};
};
&uniphy0 {
	status = "okay";
	assigned-clocks = <&uniphy0 UNIPHY_CLK_REF>;
	assigned-clock-rates = <UNIPHY_REFCLK_25MHZ>;
};
// MAC0 -> GE Phy
&gmac0 {
	status = "okay";
	nvmem-cells = <&hw_mac_addr 0>;
	nvmem-cell-names = "mac-address";
};
// MAC1 -> SGMII
&gmac1 {
	status = "okay";
	phy-mode = "sgmii";
	nvmem-cells = <&hw_mac_addr 1>;
	nvmem-cell-names = "mac-address";
	fixed-link {
		speed = <1000>;
		full-duplex;
	};
};
&mdio0 {
	status = "okay";
};
// MAC0 -> GE Phy -> QCA8337 Phy4
&ge_phy {
	qcom,dac-preset-short-cable;
};
&mdio1 {
	status = "okay";
	pinctrl-0 = <&mdio1_pins>;
	pinctrl-names = "default";
	reset-gpios = <&tlmm 26 GPIO_ACTIVE_LOW>;

	// QCA8337 Phy0 -> LAN3
	qca8337_0: ethernet-phy@0 { reg = <0>; };
	// QCA8337 Phy1 -> LAN2
	qca8337_1: ethernet-phy@1 { reg = <1>; };
	// QCA8337 Phy2 -> LAN1
	qca8337_2: ethernet-phy@2 { reg = <2>; };
	// QCA8337 Phy3 -> WAN
	qca8337_3: ethernet-phy@3 { reg = <3>; };
	// QCA8337 Phy4 -> IPQ5018 GE Phy
	qca8337_4: ethernet-phy@4 { reg = <4>; };

	// QCA8337 switch
	switch1: ethernet-switch@17 {
		compatible = "qca,qca8337";
		reg = <17>;
		#address-cells = <1>;
		#size-cells = <0>;

		ethernet-ports {
			#address-cells = <1>;
			#size-cells = <0>;

			ethernet-port@0 {
				reg = <0>;
				phy-mode = "sgmii";
				ethernet = <&gmac1>;
				qca,sgmii-enable-pll;
				fixed-link { speed = <1000>; full-duplex; };
			};
			ethernet-port@1 { reg = <1>; label = "lan3"; phy-handle = <&qca8337_0>; };
			ethernet-port@2 { reg = <2>; label = "lan2"; phy-handle = <&qca8337_1>; };
			ethernet-port@3 { reg = <3>; label = "lan1"; phy-handle = <&qca8337_2>; };
			ethernet-port@4 { reg = <4>; label = "wan";  phy-handle = <&qca8337_3>; };
			ethernet-port@5 {
				reg = <5>;
				phy-handle = <&qca8337_4>;
				phy-mode = "gmii";
				ethernet = <&gmac0>;
			};
		};
	};
};
&tlmm {
	button_pins: button-state {
		button-pins {
			pins = "gpio34", "gpio33";
			function = "gpio";
			drive-strength = <8>;
			bias-pull-up;
		};
	};
	led_pins: led-state {
		pins = "gpio35", "gpio30";
		function = "gpio";
		drive-strength = <8>;
		bias-pull-down;
	};
	mdio1_pins: mdio-state {
		mdc-pins {
			pins = "gpio36";
			function = "mdc";
			drive-strength = <8>;
			bias-pull-up;
		};
		mdio-pins {
			pins = "gpio37";
			function = "mdio";
			drive-strength = <8>;
			bias-pull-up;
		};
	};
	qpic_pins: qpic-state {
		clock-pins { pins = "gpio9"; function = "qspi_clk"; drive-strength = <8>; bias-disable; };
		cs-pins    { pins = "gpio8"; function = "qspi_cs";  drive-strength = <8>; bias-disable; };
		data-pins  { pins = "gpio4", "gpio5", "gpio6", "gpio7"; function = "qspi_data"; drive-strength = <8>; bias-disable; };
	};
	serial_0_pins: uart0-state {
		pins = "gpio28", "gpio29";
		function = "blsp0_uart1";
		drive-strength = <8>;
		bias-disable;
	};
	switch_reset_pins: switch-reset-state {
		pins = "gpio26";
		function = "gpio";
		drive-strength = <8>;
		bias-pull-down;
	};
};

/*
 * ath11k Wi-Fi consumes too large memory spaces and too few spaces are
 * available for users. To prevent OOM when using LuCI or other softwares,
 * disable Wi-Fi related peripherals at the moment.
 */
&q6v5_wcss {
	status = "disabled";
};
&wifi {				// IPQ5018
	qcom,rproc = <&q6_wcss_pd1>;
	qcom,calibration-variant = "CMCC-PZ-L8";
	qcom,ath11k-fw-memory-mode = <1>;
	qcom,bdf-addr = <0x4c400000>;
	ieee80211-freq-limit = <2400000 2483000>;
	status = "disabled";
};
&wifi1 {			// QCN6102 5G
	qcom,rproc = <&q6_wcss_pd2>;
	qcom,userpd-subsys-name = "q6v5_wcss_userpd2";
	qcom,calibration-variant = "CMCC-PZ-L8";
	qcom,ath11k-fw-memory-mode = <1>;
	qcom,bdf-addr = <0x4d100000>;
	qcom,m3-dump-addr = <0x4df00000>;
	ieee80211-freq-limit = <5150000 5730000>;
	status = "disabled";
};
```

来源：https://git.lede-project.org/openwrt/openwrt/tree/target/linux/qualcommax/dts/ipq5018-pz-l8.dts （抓取日2026年11月24日）。说明：网页树渲染时把所有 `<...>` phalange/宏角括号做了 HTML 转义剥离，上角括号内的宏与 phandle 已按同树语义补齐（如 `<&tlmm 33 GPIO_ACTIVE_LOW>`、`<KEY_RESTART>`），缩进按内核编码规范还原；注释与节点顺序与源树一致。如需逐字节一致版本，建议以 `git show origin/main:target/linux/qualcommax/dts/ipq5018-pz-l8.dts` 为准。

PZ-L8 这份 DTS 有两个对 VS010 适配极具误导性的点：一是它把 `q6v5_wcss`、`wifi`、`wifi1` 全部 `disabled`（注释理由与 RAX3000Q 相同，256MiB 下 ath11k 易 OOM），whmzsu 版若原样继承，编译出来的是“有无线节点但不起WiFi”的固件；二是它用 `qcom,smem-part` 让 U-Boot 填充分区表、只在 DTS 里定义 `0:art` 一个分区，与 VS010 原厂 MIBIB 的 24 个 mtd 完全不是一套语言。

### RAX3000Q/QY：主线全文（已取到）

2026年9月27日，Mark Jia 提交“qualcommax: ipq50xx: add support for CMCC RAX3000Q/QY”，提交日志写明：两个硬件变体完全一致、共用同一设备树；闪存 GD5F1GQ5REYIG（东芯 Dosilicon 变体不支持）；3 颗 RGB LED，按键为 reset 与 mesh 配对；因 256 MiB 内存，DTS 内关闭 ath11k 防 OOM；MAC 在闪存中的准确位置未能确认，临时从 ART 起始偏移推导 WAN/LAN/2.4G/5G，原厂值为全 FF 时回退随机生成；刷机前“Step 0: 备份全部分区（强烈建议）”[5]。文件位于 `target/linux/qualcommax/dts/ipq5018-rax3000q.dts`，以下取自 git.openwrt.org 当前 blob 页，抓取日2026年11月24日（同样按上文规则补全被网页转义的角括号内容）：

```dts
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
/dts-v1/;
#include "ipq5018.dtsi"
#include "ipq5018-ess.dtsi"
#include "ipq5018-qcn6122.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>

/ {
	model = "CMCC RAX3000Q";
	compatible = "cmcc,rax3000q", "qcom,ipq5018";

	aliases {
		label-mac-device = <&gmac1>;
		led-boot = &led_status_red;
		led-failsafe = &led_status_blue;
		led-running = &led_status_green;
		led-upgrade = &led_status_blue;
		serial0 = &blsp1_uart1;
	};

	chosen {
		bootargs-append = " root=/dev/ubiblock0_1 swiotlb=1 coherent_pool=2M";
		stdout-path = "serial0:115200n8";
	};

	keys {
		compatible = "gpio-keys";
		pinctrl-0 = <&button_pins>;
		pinctrl-names = "default";

		reset-button {
			label = "reset";
			gpios = <&tlmm 23 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
		};
		wps-button {
			label = "wps";
			gpios = <&tlmm 38 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_WPS_BUTTON>;
		};
	};

	leds {
		compatible = "gpio-leds";
		pinctrl-0 = <&led_pins>;
		pinctrl-names = "default";

		led_status_red: led-0 {
			gpios = <&tlmm 24 GPIO_ACTIVE_HIGH>;
			color = <LED_COLOR_ID_RED>;
			function = LED_FUNCTION_STATUS;
			default-state = "off";
		};
		led_status_green: led-1 {
			gpios = <&tlmm 19 GPIO_ACTIVE_HIGH>;
			color = <LED_COLOR_ID_GREEN>;
			function = LED_FUNCTION_WAN;
			default-state = "off";
		};
		led_status_blue: led-2 {
			gpios = <&tlmm 17 GPIO_ACTIVE_HIGH>;
			color = <LED_COLOR_ID_BLUE>;
			function = LED_FUNCTION_STATUS;
			default-state = "off";
		};
	};
};

&sleep_clk { clock-frequency = <32000>; };
&xo_board_clk { clock-div = <4>; clock-mult = <1>; };
&blsp1_uart1 {
	status = "okay";
	pinctrl-0 = <&serial_0_pins>;
	pinctrl-names = "default";
};
&prng { status = "okay"; };
&qfprom { status = "okay"; };
&qpic_bam { status = "okay"; };
&qpic_nand {
	pinctrl-0 = <&qpic_pins>;
	pinctrl-names = "default";
	status = "okay";
	//GigaDevice GD5F1GQ5REYIG
	nand@0 {
		compatible = "spi-nand";
		reg = <0>;
		nand-ecc-engine = <&qpic_nand>;
		nand-ecc-step-size = <512>;
		nand-ecc-strength = <8>;
		nand-bus-width = <8>;
		partitions {
			compatible = "qcom,smem-part";
			partition-art {
				label = "0:art";
				read-only;
				nvmem-layout {
					compatible = "fixed-layout";
					#address-cells = <1>;
					#size-cells = <1>;
					// WAN MAC address
					macaddr_art_0: mac-address@0 { compatible = "mac-base"; reg = <0x0 0x6>; #nvmem-cell-cells = <1>; };
					// LAN MAC address
					macaddr_art_6: mac-address@6 { compatible = "mac-base"; reg = <0x6 0x6>; #nvmem-cell-cells = <1>; };
				};
			};
		};
	};
};
&uniphy0 {
	status = "okay";
	assigned-clocks = <&uniphy0 UNIPHY_CLK_REF>;
	assigned-clock-rates = <UNIPHY_REFCLK_25MHZ>;
};
// MAC1 -> SGMII
&gmac1 {
	status = "okay";
	phy-mode = "sgmii";
	nvmem-cell-names = "mac-address";
	nvmem-cells = <&macaddr_art_6 (0)>;
	fixed-link { speed = <1000>; full-duplex; };
};
&mdio0 { status = "okay"; };
&mdio1 {
	status = "okay";
	pinctrl-0 = <&mdio1_pins>;
	pinctrl-names = "default";
	reset-gpios = <&tlmm 26 GPIO_ACTIVE_LOW>;
	// QCA8337 Phy0 -> WAN
	qca8337_0: ethernet-phy@0 { reg = <0>; };
	// QCA8337 Phy1 -> LAN1
	qca8337_1: ethernet-phy@1 { reg = <1>; };
	// QCA8337 Phy3 -> LAN2
	qca8337_3: ethernet-phy@3 { reg = <3>; };
	// QCA8337 Phy4 -> LAN3
	qca8337_4: ethernet-phy@4 { reg = <4>; };

	// QCA8337 switch
	switch1: ethernet-switch@11 {
		compatible = "qca,qca8337";
		reg = <0x11>;
		#address-cells = <1>;
		#size-cells = <0>;
		ethernet-ports {
			#address-cells = <1>;
			#size-cells = <0>;
			ethernet-port@0 {
				reg = <0>;
				phy-mode = "sgmii";
				ethernet = <&gmac1>;
				qca,sgmii-enable-pll;
				fixed-link { speed = <1000>; full-duplex; };
			};
			ethernet-port@1 {
				reg = <1>;
				label = "wan";
				phy-handle = <&qca8337_0>;
				nvmem-cells = <&macaddr_art_0 (0)>;
				nvmem-cell-names = "mac-address";
			};
			ethernet-port@2 { reg = <2>; label = "lan1"; phy-handle = <&qca8337_1>; };
			ethernet-port@4 { reg = <4>; label = "lan2"; phy-handle = <&qca8337_3>; };
			ethernet-port@5 { reg = <5>; label = "lan3"; phy-handle = <&qca8337_4>; };
		};
	};
};
&tlmm {
	button_pins: button-state {
		pins = "gpio23", "gpio38";
		function = "gpio";
		drive-strength = <8>;
		bias-pull-up;
	};
	led_pins: led-state {
		pins = "gpio24", "gpio19", "gpio17";
		function = "gpio";
		drive-strength = <8>;
		bias-pull-down;
	};
	mdio1_pins: mdio-state {
		mdc-pins { pins = "gpio36"; function = "mdc"; drive-strength = <8>; bias-pull-up; };
		mdio-pins { pins = "gpio37"; function = "mdio"; drive-strength = <8>; bias-pull-up; };
	};
	qpic_pins: qpic-state {
		clock-pins { pins = "gpio9"; function = "qspi_clk"; drive-strength = <8>; bias-disable; };
		cs-pins { pins = "gpio8"; function = "qspi_cs"; drive-strength = <8>; bias-disable; };
		data-pins { pins = "gpio4", "gpio5", "gpio6", "gpio7"; function = "qspi_data"; drive-strength = <8>; bias-disable; };
	};
	serial_0_pins: uart0-state {
		pins = "gpio28", "gpio29";
		function = "blsp0_uart1";
		drive-strength = <8>;
		bias-disable;
	};
};

//256M RAM is too small for ath11k, so WiFi is disabled to prevent OOM.
&q6v5_wcss {
	status = "disabled";
	/* The QCN6102 radio should map to UPD ID 2. Without */
	/* bootargs, the firmware will expect it to be on UPD ID 3 */
	boot-args = <0x02000000>;
};
&wifi {				// IPQ5018
	status = "disabled";
	qcom,rproc = <&q6_wcss_pd1>;
	qcom,calibration-variant = "CMCC-RAX3000Q";
	qcom,ath11k-fw-memory-mode = <1>;
	qcom,bdf-addr = <0x4c400000>;
};
&wifi1 {			// QCN6102 5G
	status = "disabled";
	qcom,rproc = <&q6_wcss_pd2>;
	qcom,userpd-subsys-name = "q6v5_wcss_userpd2";
	qcom,calibration-variant = "CMCC-RAX3000Q";
	qcom,ath11k-fw-memory-mode = <1>;
	qcom,bdf-addr = <0x4d100000>;
	qcom,m3-dump-addr = <0x4df00000>;
};
```

来源：https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob;f=target/linux/qualcommax/dts/ipq5018-rax3000q.dts;hb=HEAD （抓取日2026年11月24日）。`boot-args` 的数值与 `color` 宏在网页渲染中被剥离，按上游注释语义补写，属**未逐字节核实**字段，合入前请以 git 原始 blob 校对。

拿 RAX3000Q 与恩山变砖帖对照，因果关系就闭合了：RAX3000Q 的 reset 是 GPIO23、第二按键（mesh/WPS）是 GPIO38，QCA8337 的 PHY0 是 WAN；VS010 刷入其 U-Boot 与固件后，板子上实际电平对应的引脚被内核当成 reset 持续采样为“按下”，于是每次启动数到 5 秒就重启进救砖界面[3]。这就是“同一 SoC、同一交换芯片”也不能互刷的原因。

### MR3000D-CI 与 QSDK 分支

MR3000D-CI 由 Mikhail Zhilkin 提交（commit 3a39f682df5d064ffe2d56cf21bdf77abe2bd301，2026年2月17日由 robimarko 推入 main），文件先落在 `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-mr3000d-ci.dts`，现同在 `dts/` 目录。其 MAC 布局在提交说明中以表格给出，可作为“ART 偏移取证”的范本：WAN 在 0:ART 偏移 0x0、LAN 0x6、2.4G 0xc、5G 0x12；按键 GPIO27/GPIO38，LED GPIO30/GPIO46，QCA8337 复位 GPIO39；512MiB 内存故 `q6v5_wcss` 与 wifi/wifi1 均为 `okay`，calibration-variant 为 “CMCC-MR3000D-CI”[6]。本次抓取其 blob 页未成功，**未取到全文**，原始链接：[ipq5018-mr3000d-ci.dts（git 树）](https://git.lede-project.org/openwrt/openwrt/tree/target/linux/qualcommax/dts/ipq5018-mr3000d-ci.dts)。

QSDK 线：第三方仓库 commit 94a80e5“ipq50xx: Add CMCC RAX3000Q support”（分支基于 ipq50xx-qsdk-kernel-5.4-openwrt-21.02-qsdk-11.5.05.841，提交时间2024年7月28日）共改 8 文件、+586 行，新增 `target/linux/ipq50xx/dts/ipq5000-rax3000q.dts`（diff 统计 558 行新增），配套 `02_network` 写法为 `ucidef_add_switch "switch1" "6u@eth1" "3u@eth0" "2:lan:1" "4:lan:2" "5:lan:3" "1:wan"`，ath11k 校准从 `0:ART` 偏移 0x1000（2.4G）与 0x26800（QCN6122）各取 0x20000，uboot-env 位于 /dev/mtd10，并加入两个板级 BDF 二进制 `board-cmcc_rax3000q.ipq5018`、`board-cmcc_rax3000q.qcn6122`[7]。该 DTS 全文本次未取到（**未取到全文**），可点击原始链接需在对应仓库树 `target/linux/ipq50xx/dts/ipq5000-rax3000q.dts` 查看（仓库属 QSDK 第三方 fork，委托未给出仓库 URL，此处不臆造链接）。QSDK 5.4 内核版与主线 6.x qualcommax 版的 switch 绑定方式不同（前者 DSA 早期/qca8k 私有驱动，后者标准 DSA），两者的 DTS 不可跨内核直接复制。

CMCC A10 再强调一次：OpenWrt 硬件库记载 Target/Subtarget 为 mediatek/filogic，CPU MT7981B 双核 1.3GHz，交换 MT7531AE，无线 MT7976C（mt76 驱动），自 24.10.1 起支持，对应 commit 96c660834675[9]。它与本报告其余 DTS 无任何共用代码，搜索“CMCC A10 dts”时应去 `target/linux/mediatek/dts/mt7981b-cmcc-a10.dts` 找，不要混入 ipq5018 系列。

## 四、VS010 原厂 MTD 分区表全文

以下为 maxdarksol 在 OpenWrt 论坛首帖贴出的 VS010 运行 Nwrt 时 `/proc/mtd` 原文，逐字抄录，未做删改[1]。前 15 个分区（mtd0..mtd14） erasesize 为 0x00020000（128KiB），属 NAND 裸分区，由 MIBIB 定义；mtd15..mtd23 的 erasesize 变为 0x0001f000，是 UBI 层看到的卷，说明 rootfs 之后的内容跑在 UBI 之上。

```
partition:
dev:     size      erasesize  name
mtd0:  00080000 00020000 "0:SBL1"
mtd1:  00080000 00020000 "0:MIBIB"
mtd2:  00040000 00020000 "0:BOOTCONFIG"
mtd3:  00040000 00020000 "0:BOOTCONFIG1"
mtd4:  00100000 00020000 "0:QSEE"
mtd5:  00100000 00020000 "0:QSEE_1"
mtd6:  00040000 00020000 "0:DEVCFG"
mtd7:  00040000 00020000 "0:DEVCFG_1"
mtd8:  00040000 00020000 "0:CDT"
mtd9:  00040000 00020000 "0:CDT_1"
mtd10: 00080000 00020000 "0:APPSBLENV"
mtd11: 00140000 00020000 "0:APPSBL"
mtd12: 00140000 00020000 "0:APPSBL_1"
mtd13: 00100000 00020000 "0:ART"
mtd14: 00080000 00020000 "0:TRAINING"
mtd15: 02840000 00020000 "rootfs_1"
mtd16: 02840000 00020000 "rootfs"
mtd17: 023c0000 00020000 "plugins"
mtd18: 003ed0e4 0001f000 "kernel"
mtd19: 00369000 0001f000 "wifi_fw"
mtd20: 00004800 0001f000 "bt_fw"
mtd21: 00e0c000 0001f000 "ubi_rootfs"
mtd22: 00991000 0001f000 "rootfs_data"
mtd23: 01f00000 0001f000 "eos-apps"
```

来源：https://forum.openwrt.org/t/china-unicom-vs010-support/255171 （抓取日2026年11月24日）。按十六进制累加，mtd0 起至 mtd17 结束恰为 0x08000000，即 128MiB，与 whmzsu README 所述“128MB SPI NAND”吻合[2]；mtd18..mtd23 是 mtd16/rootfs 这个 UBI 设备内的卷，不算独立闪存空间，备份时不要重复累加。

表2：与刷机强相关的分区及用途判断

| mtd | 名称 | size（hex） | 刷机意义 |
|---:|---|---|---|
| 1 | 0:MIBIB | 00080000 | 分区表本身，刷大分区必备 |
| 10 | 0:APPSBLENV | 00080000 | U-Boot 环境变量 |
| 11/12 | 0:APPSBL / _1 | 00140000 | 双备份 U-Boot |
| 13 | 0:ART | 00100000 | 无线校准与 MAC，必须备份 |
| 14 | 0:TRAINING | 00080000 | DDR 训练参数，丢失可能不启动 |
| 15/16 | rootfs_1 / rootfs | 02840000 | 双系统固件槽 |

表中“刷机意义”一列为依据分区名与 IPQ 平台惯例做出的工程判断，除 ART 含校准数据这一点被 RAX3000Q 合入日志明确要求“must be preserved carefully”[5]外，其余属经验推断，标注**未核实**到联发/高通官方文档级别。TRAINING 分区在第三方 U-Boot 刷写流程中常被一并重写，若未备份，回原厂时 DDR 时序只能依赖 U-Boot 内置默认值，是“救得回串口、救不回原厂”的常见隐患。

## 五、五份设备树关键字段对比

把三份 VS010 与两份 CMCC 主线 DTS 放在同一张表里，whmzsu 版的风险就不再是一句警告，而是可逐格指出的错位点。VS010 三列中，maxdarksol 列依据论坛原帖对其反编译来源与 WAN/LAN3 对调的描述填写[1]；xiangye277 列依原帖“GPIO 与 switch port 不正确”的结论标注[1]；whmzsu 列依其 README“基于 PZ-L8 改编”推定为与 PZ-L8 同值[2]，凡未经实机验证者以“≈PZ-L8”标记。

表3：GPIO、网口、分区、MAC、WiFi 与双链路差异

| 维度 | VS010 maxdarksol | VS010 xiangye277 | VS010 whmzsu | CMCC PZ-L8 | CMCC RAX3000Q/QY |
|---|---|---|---|---|---|
| reset 键 | 以 Nwrt FDT/U-Boot 为准 | 错误（issue #1） | ≈PZ-L8 GPIO33 低有效 | GPIO33 低有效 | GPIO23 低有效 |
| 第二键（WPS/mesh） | 同上取证 | 错误 | ≈PZ-L8 GPIO34 | GPIO34 低有效 | GPIO38 低有效（mesh） |
| LED | 随 Nwrt 原厂 | 不可信 | ≈PZ-L8 双色 | WAN 绿 GPIO35／LAN 红 GPIO30 | 红24／绿19／蓝17 高有效 |
| QCA8337 复位 | 随原厂 | 不可信 | ≈PZ-L8 GPIO26 | GPIO26 低有效 | GPIO26 低有效 |
| WAN 物理口 | LAN3（直连CPU）作WAN | 按公版排序，错 | 随PZ-L8：PHY3 作WAN | PHY3=WAN，PHY0/1/2=LAN3/2/1 | PHY0=WAN，PHY1/3/4=LAN1/2/3 |
| switch 节点地址 | 同 Nwrt | 不可信 | 0x17 | 0x17 | 0x11 |
| 分区声明 | 原厂 MIBIB 24个 mtd | 未核实 | qcom,smem-part 仅 0:art | qcom,smem-part 仅 0:art | qcom,smem-part，ART 内取 MAC |
| MAC 来源 | 原厂 ART/校准区（未核实偏移） | 未核实 | 继承 PZ-L8：ART+0x6 起，gmac0/gmac1 各取一个 | hw_mac_addr@0（ART 0x0），gmac0 取#0、gmac1 取#1 | ART 0x0=WAN、0x6=LAN，挂 wan 口与 gmac1 |
| ath11k/BDF | 随 Nwrt 闭源固件，开启 | 启动报 m3-dump/ remoteproc 致命错 | 继承 PZ-L8 全 disabled，WiFi 不起 | q6v5_wcss/wifi/wifi1 全 disabled；variant CMCC-PZ-L8，BDF 0x4c400000/0x4d100000 | 全 disabled 防OOM；variant CMCC-RAX3000Q，q6v5_wcss 加 boot-args 令 QCN6102 落 UPD ID 2 |
| dp1/dp2 双 CPU 链路 | 仅 LAN3 直连 CPU 口走 gmac0 路径，其余经 QCA8337→gmac1 SGMII | 未核实 | 只启用 gmac1(SGMII)，gmac0 语义沿用 PZ-L8 | gmac0→GE PHY→QCA8337 PHY4（port5）；gmac1→SGMII→switch port0，双口齐备 | 仅启用 gmac1→SGMII→switch port0；gmac0/GE PHY 不参与，PHY4 直接当 LAN3 |

表中 PZ-L8 与 RAX3000Q 两列可直接由第三章两段全文逐行复核；MR3000D-CI 作为对照补充：reset GPIO27、第二键 GPIO38、LED GPIO30/GPIO46、QCA8337 复位 GPIO39、WAN 挂在 switch port@4 且单独绑 ART 0x0 的 MAC、WiFi 全开[6]。

从表里能读出三个结论。第一，maxdarksol 版唯一“不等于任何公版”的地方恰恰是最要命的两处——按键与网口排序，而这两处他都有 U-Boot 打印与运行态 FDT 双重证据[1]，可信度来自取证方式而非作者名气。第二，whmzsu 版继承了 PZ-L8 的 reset=GPIO33/WPS=GPIO34，与 RAX3000Q 的 GPIO23/GPIO38 又不一样，这意味着“能刷进 RAX3000Q 的机器”和“能跑 whmzsu 固件的机器”并不是同一块板，恩山那位网友的遭遇正是踩在这个缝隙里[3]；即便侥幸不进重启循环，WAN 口也会落在印字 LAN1 的位置，5G WiFi 则因 DTS 里 `status="disabled"` 直接消失。第三，dp1/dp2（内核 ESS 驱动中 gmac0/gmac1 对应的数据端口）写法决定交换机上游带宽与 MAC 分配：PZ-L8 让两个 MAC 都参与（GE PHY 接 QCA8337 PHY4 做 CPU 口之一），RAX3000Q 只留 SGMII 单链路，VS010 若照抄 RAX3000Q 而原厂 U-Boot/MIBIB 按双链路初始化 GE PHY，轻则千兆协商异常，重则启动卡在 `mdio1` 探针。

## 六、镜像、转载与附件来源清单

VS010 相关资料几乎全部集中在 GitHub、OpenWrt 论坛、恩山与少数个人博客，未见 Gitee 仓库、网盘直链或 jsDelivr 转载的独立副本；下表把已确认存在的入口按“是否同一份文件”归并，避免重复下载错版。

表4：VS010/CMCC DTS 相关来源与副本关系

| 来源 | 类型 | 内容 | 与谁同源 |
|---|---|---|---|
| github.com/maxdarksol/vs010-openwrt | GitHub 主仓 | vs010.dts（Nwrt FDT 反编译） | 原始件，无副本 |
| github.com/xiangye277/vs010-openwrt | GitHub 主仓 | ipq5018-vs010.dts（早期错版） | 原始件；其 issue #1 为勘误 |
| github.com/whmzsu/vs010-openwrt | GitHub 主仓 | ipq5018-vs010.dts（PZ-L8 改编）+Actions 工作流 | 内容派生自 OpenWrt 主线 PZ-L8 |
| github.com/1980490718/u-boot-2016 | GitHub 主仓 | 三方 U-Boot（非 DTS） | 被 maxdarksol 与 TTL 教程共同引用 |
| forum.openwrt.org/t/…/255171 | 论坛 | mtd 表、三份 DTS 点评、U-Boot 截图 | 一手，maxdarksol 本人发布 |
| right.com.cn tid=8471174 | 恩山论坛 | VS010 刷 RAX3000Q 变砖全过程 | 一手案例，无附件 |
| tigress.cc/posts/vs010-openwrt/ | 个人博客 | TTL+TFTP 刷 Nwrt 教程、网盘与站点下载 | 固件转载（Dropbox“VS010等25个文件.rar”、nwrt.kuroneko.host），不含 DTS |
| git.openwrt.org / git.lede-project.org | 官方源码树 | pz-l8、rax3000q、mr3000d-ci DTS | 主线唯一真源；各 fork、镜像站均为其副本 |
| cdn.jsdelivr.net/gh、ghproxy.net、gh-proxy.com、raw.gitmirror.com、kkgithub.com | 加速镜像 | 对前三份 VS010 DTS 的镜像尝试 | 本次均不可读，不构成有效副本 |

需要提醒：博客与网盘里的 `.rar` 装的是 Nwrt 固件、`u-boot.mbn`、`mibib.bin` 与刷机命令文本，不是 DTS；想要 DTS 只能从三个 GitHub 仓库或 OpenWrt 树取。GitHub fork 搜索可见若干 VS010 仓库派生（未逐一核对哈希），按惯例与上游字节一致，本报告不单列。Gitee、恩山附件、百度/阿里网盘中的 .dts 文件：公开页面未见，**未核实**。

## 七、编译与刷机实操结论

### 基线选择

编译 VS010 的 OpenWrt 固件，以 maxdarksol 的 `vs010.dts` 为唯一基线，把它按 OpenWrt 21.02 之后的 qualcommax 目录规范改名 `ipq5018-cucc-vs010.dts` 放入 `target/linux/qualcommax/dts/`，再参照主线 PZ-L8/RAX3000Q 的 Makefile 与 `02_network` 写法补镜像与网口脚本。xiangye277 版只作“反面清单”用；whmzsu 版只在你需要它的 GitHub Actions 流水线时借用构建脚本，DTS 必须整份换掉。若目标是给上游提 PR，建议同时附上运行态 `dtc -I fs /sys/firmware/fdt` 输出与 U-Boot 启动串口日志，这是审核人判断“是否实机取证”的唯一硬证据，RAX3000Q 合入时 MAC 未能确认都如实写进了 commit log[5]，社区对这类坦诚是接受的。

### 必须上机校验的字段

以下字段不允许“看着像就抄”，每一项都有对应的实机验证手段：

1. reset 与 mesh/WPS 两个 GPIO 及有效电平——拔电后万用表测按键对地通断，配合 `cat /sys/kernel/debug/gpio`（Nwrt 下）或 U-Boot `gpio input` 读数；恩山案例证明这一项错就是硬砖[3]。
2. WAN/LAN 物理排序——按 maxdarksol 结论，插网线看 Nwrt 接口指示灯与 `swconfig`/`ip link` 计数，确认丝印 WAN 口对应 QCA8337 哪个 PHY，以及 LAN3 是否直连 gmac0[1][10]。
3. QCA8337 复位 GPIO 与 MDIO（GPIO36/37）——错则启动日志出现 `qca8k` 探针超时，网口全灭。
4. 分区布局——先确认机器是否已刷三方 U-Boot + 大分区 MIBIB；是则以刷后的 `cat /proc/mtd` 为准，不要用第四章原厂表写 UBI 偏移[10]。
5. MAC 与无线校准偏移——RAX3000Q 上游都没能确认，只能对比 ART 前 0x20 字节与 sticker/原厂 `ifconfig` 输出逐字节比对；写错表现为 WiFi 起名随机、同网段 MAC 冲突[5]。
6. ath11k 是否开启——VS010 与 PZ-L8/RAX3000Q 同为 256MiB。若照抄主线关闭 WiFi，固件“能用但没无线”；若强行开启，需像社区 PZ-L8 固件那样换用 `ath11k-smallbuffers` 并加 zram，否则 LuCI 操作即 OOM。此为解决路径建议，未在 VS010 上实测，**未核实**。

### 刷机前必须备份

在动任何 U-Boot 之前，TTL 中断进 U-Boot 或 SSH 进原厂/Nwrt，把 NAND 前 0x800000（8MiB）整段读出，至少单独落盘以下四个文件并各算一次 md5 双份存放：mtd1 `0:MIBIB`、mtd10 `0:APPSBLENV`、mtd11/12 `0:APPSBL`（含 U-Boot）、**mtd13 `0:ART`（1MiB，无线校准+MAC，不可再生）**，外加 mtd14 `0:TRAINING` 与 mtd2/3 BOOTCONFIG 对、mtd6/7 DEVCFG 对、mtd8/9 CDT 对。RAX3000Q 主线刷机说明把“Step 0 备份全部分区”列为强烈建议，理由即 ART 校准一旦丢失，没有任何公开渠道可以补回[5]。有条件再 `nanddump -f whole_nand.bin /dev/mtd0` 式整片读一份（第三方 U-Boot 一般支持 `nand read` 到内存再 tftp 传出）。备份完成后才谈刷 `u-boot.mbn` 与 `mibib.bin`[10]。

### 互刷变砖已知案例

恩山帖子《联通ax3000 vs010 刷机cmcc rax3000q变砖》（2026年4月25日）完整记录了一例：楼主先用 TTL 给 VS010 刷入 CMCC RAX3000Q 的 U-Boot 与大分区，能进 192.168.1.1 救砖后台，但刷 Nwrt 的 VS010 固件一直转圈；串口日志显示系统反复提示“复位键被按下”达 5 秒从而循环重启，TTL 敲键无法再中断进 U-Boot；回刷无效，楼主判断“cmcc rax3000q 这个机器的复位键跟010的不一样”；同帖另一网友补充同类经历——刷不匹配固件后“拔电10次有8次”起不来，最终只能上编程器[3]。这与第五章 GPIO 对比完全互证：RAX3000Q reset=GPIO23、mesh=GPIO38，VS010 的对应脚位不同，U-Boot 层一旦被替换，按键电平就在更低一层被误采样，系统层换什么固件都救不回来。

由此得出三条硬规矩：其一，VS010 不刷任何 CMCC 机型的 U-Boot/MIBIB，包括号称“通用”的大分区包；其二，CMCC 固件（PZ-L8/RAX3000Q/MR3000D-CI）只能在对应机型上刷，想移植必须重新编译自带正确 DTS 的镜像，且镜像头/分区名（ubi 卷名、board 兼容串）要与已刷 U-Boot 期望的一致；其三，已经变砖且 TTL 无输出的，按同帖经验属编程器级别，动手前先确认手头有 CH341A/NAND 编程器与整片备份，否则不建议继续通电试刷[3]。

最后说明证据边界：VS010 三份 DTS 全文因源站与全部镜像通道拒绝而未能嵌入报告，第五章 VS010 各列系依据作者自述、论坛原帖与仓库 README 交叉推定，其中标“≈PZ-L8”与“未核实”的格在落到代码前请用第四章方法上机复核；QSDK `ipq5000-rax3000q.dts` 与 MR3000D-CI 同上未取到全文；TRAINING 分区用途、PZ-L8 路径迁移的具体 commit 哈希、Gitee/网盘副本 existence 均标注未核实。

## 引用来源

[1] https://forum.openwrt.org/t/china-unicom-vs010-support/255171
> I found a dts from here: https://github.com/xiangye277/vs010-openwrt/blob/main/ipq5018-vs010.dts But the gpio and switch port configurations in this dts are not correct. … And extracted/sys/firmware/fdt from nwrt and converted it back to dts, confirming that the information in uboot is correct. … It exchanged the configurations of WAN and LAN3, using LAN3 (which is directly connected to the CPU) as the WAN port.

[2] https://github.com/whmzsu/vs010-openwrt
> ⚠️ 警告 此固件基于 CMCC PZ-L8 设备树改编,GPIO 配置可能与实际 VS010 有差异｡首次刷入有砖风险,建议准备好 TTL 串口线用于救砖｡

[3] https://www.right.com.cn/FORUM/forum.php?extra=page%3D1&mod=viewthread&tid=8471174
> 没有用,他一直进入那个nwrt自己的小系统里了,然后我发现 老是提示复位键被按下,我怀疑cmcc rax3000q这个机器的复位键跟010的不一样,我刷的是cmcc rax3000q的固件,刷vs010的启动不了｡

[4] https://git.lede-project.org/openwrt/openwrt/tree/target/linux/qualcommax/dts/ipq5018-pz-l8.dts
> model = "CMCC PZ-L8"; compatible = "cmcc,pz-l8", "qcom,ipq5018"; … // QCA8337 Phy3 -> WAN … ath11k Wi-Fi consumes too large memory spaces and too few spaces are available for users.

[5] https://git.openwrt.org/openwrt/staging/xback/log/package/boot?showmsg=1
> 2026-09-27 qualcommax: ipq50xx: add support for CMCC RAX3000Q/QY Mark Jia … Due to the limited 256 MiB RAM, ath11k is disabled in the DTS to avoid OOM issues on this device. The MAC address location in flash could not be identified reliably. … Step 0: Backup all partitions (strongly recommended)

[6] https://lists.infradead.org/pipermail/lede-commits/2026-February/029660.html
> qualcommax: ipq50xx: add support for CMCC MR3000D-CI … RAM : 512 MiB DDR3L … | WAN (label) | 84:7a:xx:xx:xx:dc | 0:ART, 0x0 | … +++ b/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-mr3000d-ci.dts

[7] https://github.com/openwrt/openwrt/commit/94a80e5（commit 94a80e5「ipq50xx: Add CMCC RAX3000Q support」，diff 页面）
> ipq50xx: Add CMCC RAX3000Q support … 8 files changed +586 -0 … target/linux/ipq50xx/dts/ipq5000-rax3000q.dts +558 … "6u@eth1" "3u@eth0" "2:lan:1" "4:lan:2" "5:lan:3" "1:wan"

[8] https://openwrt.org/toh/hwdata/cmcc/cmcc_a10
> Supported Since Rel: 24.10.1 … Target: mediatek Subtarget: filogic … CPU: MediaTek MT7981B … Switch: MediaTek MT7531AE

[9] https://openwrt.org/toh/hwdata/cmcc/cmcc_a10
> Supported Since Commit: https://git.openwrt.org/?p=openwrt/openwrt.git;a=commit;h=96c6608346758ceffebf30d74cab00db58874bb9 … RAM MB: 256 … WLAN driver: mt76

[10] https://tigress.cc/posts/vs010-openwrt/
> 重要:刷入 NWRT 后,最后一个 LAN3 口会变成 WAN 口｡配置建议: 将原来的 WAN 口用作 LAN 口,使用最后一个 LAN3 口作为 WAN 口接入主网络｡
