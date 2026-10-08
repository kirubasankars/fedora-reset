FEDORA_RELEASE ?= 44
FEDORA_ARCH    ?= x86_64
FEDORA_COMPOSE ?= 1.7
ISO_KIND       ?= netinst

SRC_ISO ?= $(MAKEFILE_DIR)/Fedora-Server-$(ISO_KIND)-$(FEDORA_ARCH)-$(FEDORA_RELEASE)-$(FEDORA_COMPOSE).iso

OUT_DIR     ?= $(MAKEFILE_DIR)/out
KS_TEMPLATE ?= $(MAKEFILE_DIR)/kickstart/fedora-server.ks.in
KS          ?= $(OUT_DIR)/fedora-server.ks
IMAGE_KS    ?= $(OUT_DIR)/fedora-server-image.ks
OUT_ISO     ?= $(OUT_DIR)/Fedora-Server-$(ISO_KIND)-$(FEDORA_ARCH)-$(FEDORA_RELEASE)-kickstart.iso

ADMIN_USER  ?= agent
# Empty means each install picks its own name. Set this for a fixed name.
HOSTNAME    ?=
TIMEZONE    ?= UTC
BOOT_DRIVE  ?=
ROOT_SIZE_MB     ?= 12288
SWAP_SIZE_MB     ?= 2048
RECOVERY_SIZE_MB ?= 32768
VIRT_UEFI   ?= 1

SECRETS_DIR         ?= $(MAKEFILE_DIR)/secrets
ADMIN_PASSWORD_FILE ?= $(SECRETS_DIR)/admin.password
ROOT_PASSWORD_FILE  ?= $(SECRETS_DIR)/root.password
ADMIN_PUBKEY_FILE   ?= $(SECRETS_DIR)/id_ed25519.pub

IMAGE_DIR   ?= $(OUT_DIR)/image
IMAGE_TYPE  ?= qcow2
IMAGE_NAME  ?= fedora-server-$(FEDORA_RELEASE)-$(FEDORA_ARCH).qcow2
IMAGE_RAM   ?= 4096
IMAGE_VCPUS ?= 2

# The build machine exports HOSTNAME. Keep that from becoming the installed name
# unless it is set on the make command line or in config.local.mk.
ifeq ($(origin HOSTNAME),environment)
HOSTNAME :=
endif

-include $(MAKEFILE_DIR)/config.local.mk
