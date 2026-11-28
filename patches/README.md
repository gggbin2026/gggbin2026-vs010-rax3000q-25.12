# NAND V2 补丁（默认关）

`3000Q-VS010-固件/ATR文件/` 里两份 U-Boot 名称表都含 `FM25LS01` / `FM25LS02BI3`
→ V2 批次真实存在、补丁对 V2 必需；但 **EUCLEAN 风险不变，默认不启用**。

本包**不内置未经验证的内核 patch**（不同基线内核源码不同，凭空写 diff 只会让
`git apply --check` 失败）。要启用时：

1. 把针对你所选基线内核的补丁放进本目录，命名 `*.patch`；
2. Run workflow 时 `nand_patch=true`，且基线为 6.12；
3. `scripts/apply-nand-patch.sh` 先跑 `git apply --check`，不过只打 warning 不停编；
4. 6.18 基线直接跳过。

刷前备份整片 flash；EUCLEAN 出现时不要反复擦写。
