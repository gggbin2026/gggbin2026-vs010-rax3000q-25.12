
# ── 本仓注入（第 44 次）：官方 25.12 / qosmio 25.12-nss 树内 0 命中这两台 ──
# DEVICE_PACKAGES 必须是真实包名；ATH11K_MEM_PROFILE_256M 是 .config 符号，不能写这里。
define Device/unicom_vs010
  $(call Device/FitImageLzma)
  $(call Device/UbiFit)
  SOC := ipq5018
  DEVICE_VENDOR := CUCC
  DEVICE_MODEL := VS010
  DEVICE_DTS_CONFIG := config@mp02.1
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 59392k
  NAND_SIZE := 128m
  IMAGES += factory.ubi
  IMAGE/factory.ubi := append-ubi
  DEVICE_PACKAGES := \
	ath11k-firmware-ipq5018-qcn6122 \
	kmod-ath11k-ahb \
	ipq-wifi-cucc_vs010
endef
TARGET_DEVICES += unicom_vs010

define Device/cmcc_rax3000q
  $(call Device/FitImageLzma)
  $(call Device/UbiFit)
  SOC := ipq5018
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := RAX3000Q
  DEVICE_DTS_CONFIG := config@mp02.1
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 59392k
  NAND_SIZE := 128m
  IMAGES += factory.ubi
  IMAGE/factory.ubi := append-ubi
  DEVICE_PACKAGES := \
	ath11k-firmware-ipq5018-qcn6122 \
	kmod-ath11k-ahb \
	ipq-wifi-cmcc_rax3000q
endef
TARGET_DEVICES += cmcc_rax3000q
