# Build a Fedora Server kickstart ISO, or a disk image, from the Server DVD.
# Run make with no target for the command list. make iso and make image wipe
# the disks described by the kickstart when that media is booted.

MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

include $(MAKEFILE_DIR)/mk/config.mk
include $(MAKEFILE_DIR)/mk/tools.mk
include $(MAKEFILE_DIR)/mk/kickstart.mk
include $(MAKEFILE_DIR)/mk/iso.mk
include $(MAKEFILE_DIR)/mk/image.mk

.DEFAULT_GOAL := help
SHELL := /usr/bin/bash

.PHONY: help clean

help:
	@echo "Fedora $(FEDORA_RELEASE) Server ($(FEDORA_ARCH))"
	@echo
	@echo "  make ks          Render kickstart files into out/"
	@echo "  make validate    Syntax-check the kickstart template"
	@echo "  make iso         Build a DVD that boots straight into the kickstart"
	@echo "  make image       Install a $(IMAGE_TYPE) disk image with livemedia-creator"
	@echo "  make verify-src  Check the source ISO checksum"
	@echo "  make deps        Install lorax, lorax-lmc-virt, and pykickstart"
	@echo "  make clean       Remove out/"
	@echo
	@echo "Source ISO: $(SRC_ISO)"
	@echo "Login user: $(ADMIN_USER) via $(ADMIN_PUBKEY_FILE) (sudo, no password)"
	@echo "Install source: Fedora $(FEDORA_RELEASE) Server (netinstall)"
	@echo "Packages: core, make, rsync, podman, bmap-tools, python3, dracut, tree, htop, btop, sysstat, vim"
	@echo "Root (PRIMARY_ROOT) grows to fill the disk after a $(RECOVERY_SIZE_MB) MiB recovery volume"
	@echo "Overrides go in config.local.mk (see config.local.mk.example)"

clean:
	rm -rf $(OUT_DIR)
