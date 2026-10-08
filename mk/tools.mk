PYTHON             ?= python3
MKKSISO            ?= mkksiso
LIVEMEDIA_CREATOR  ?= livemedia-creator
CHECKISOMD5        ?= checkisomd5
RENDER_KS          ?= $(MAKEFILE_DIR)/scripts/render-kickstart.py
VALIDATE_KS        ?= $(MAKEFILE_DIR)/scripts/validate-kickstart.py
KS_VERSION         ?= F$(FEDORA_RELEASE)

AS_ROOT := $(if $(filter 0,$(shell id -u)),,sudo)

# mkksiso can skip the EFI image edit when not root. A USB that boots on UEFI
# needs the privileged path, which rewrites the embedded efiboot image.
ifeq ($(SKIP_EFIBOOT),1)
MKKSISO_CMD   = $(MKKSISO)
MKKSISO_FLAGS = --skip-mkefiboot
else
MKKSISO_CMD   = $(AS_ROOT) $(MKKSISO)
MKKSISO_FLAGS =
endif

RENDER_FLAGS = \
	--template $(KS_TEMPLATE) \
	--fedora-release $(FEDORA_RELEASE) \
	--hostname $(HOSTNAME) \
	--timezone $(TIMEZONE) \
	--admin-user $(ADMIN_USER) \
	--boot-drive '$(BOOT_DRIVE)' \
	--root-size-mb $(ROOT_SIZE_MB) \
	--swap-size-mb $(SWAP_SIZE_MB) \
	--recovery-size-mb $(RECOVERY_SIZE_MB) \
	--admin-password-file $(ADMIN_PASSWORD_FILE) \
	--root-password-file $(ROOT_PASSWORD_FILE) \
	--admin-pubkey-file $(ADMIN_PUBKEY_FILE) \
	--recovery-dir $(MAKEFILE_DIR)/kickstart/recovery \
	$(if $(filter 1,$(VIRT_UEFI)),--uefi,--no-uefi)

.PHONY: deps
deps:
	$(AS_ROOT) dnf install -y lorax lorax-lmc-virt pykickstart isomd5sum xorriso
