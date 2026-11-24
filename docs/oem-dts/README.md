# 第 44 次：用户上传的板级取证资料（只读，不进编译链）

来源：`gggbin2026/Actions-OpenWrt-RAX3000Q-VS010-WDS` 的
`3000Q-VS010-固件/DTS/`（提交 b2af839，2026-11-24）。

| 文件 | 内容 | 可信度 |
|---|---|---|
| `vs010.dtb` | VS010 原厂闭源固件运行态 `/sys/firmware/fdt` 导出，45056 B，DTB v17，311 节点 | ★★★ 一手实机 |
| `VS010_原厂MTD分区表.txt` | mtd0..mtd23 原厂分区表（OpenWrt 论坛原帖逐字抄录） | ★★★ |
| `VS010与CMCC机型DTS资料核查报告.md` | 命名辨析、三份 VS010 DTS 可信度链条、五份 DTS 字段对比、变砖案例 | ★★☆ 主体交叉推定，已标注未核实项 |
| `VS010_DTS获取清单与来源.md` | 可点击原始链接与本地取法 | ★★☆ |
| `ipq5018-pz-l8.dts` | OpenWrt 主线 PZ-L8 DTS（网页树还原稿） | ⚠ 非逐字节官方 blob，仅字段对照 |
| `ipq5018-rax3000q.dts` | 用户上传的 RAX3000Q/QY 网页树还原稿 | ⚠ `boot-args` 等字段未逐字节核实 |
| `ipq5018-rax3000q.MAIN.dts` | **本次额外抓取**：openwrt/openwrt `main` 分支逐字节官方原文（6208 B），用于逐行校验还原稿 | ★★★ |

## 两条必须记住的边界

1. **`ipq5018-rax3000q.dts` / `ipq5018-pz-l8.dts` 不能直接编译**：网页渲染把
   `<...>` 的 phandle / 宏做了 HTML 转义剥离，是按同树语义补齐的还原稿。
   已用 main 分支官方原文逐行比对，绝大多数字段一致，但
   `boot-args` 被简化成 `<0x02000000>`（官方实为 `<0x2 4 2 27 0 0>`）等处有差异。
2. **官方 main 有 RAX3000Q，但 v25.12.6 稳定 tag 和 qosmio 25.12-nss 都没有**：
   实测 `v25.12.6:target/linux/qualcommax/image/ipq50xx.mk` 无 `cmcc_rax3000q`，
   所以三条基线仍需本仓 `board-inject.sh` 注入板级。

## 这些资料怎么被用掉

- VS010 的按键 / LED / NAND ECC / 分区 / MAC 交叉值 → `board/ipq5018-vs010.6.12.dts`
- RAX3000Q 的 QCA8337 端口映射 / ECC / compatible / 绑定差异 →
  `board/ipq5018-rax3000q.6.12.dts` + `scripts/board-inject.sh`
- 完整逐项核对表与「为什么有些字段故意不改」→ `docs/板级真值-第44次.md`

**所有文件只作取证与核对，不参与 `make`。**
