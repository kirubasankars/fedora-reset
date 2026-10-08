.PHONY: iso verify-src

# Keep the source volume id. Anaconda finds stage2 by the label embedded in
# the source ISO; mkksiso preserves it unless -V is set.
#
# The stock menu waits 60s on "Test this media & install" (default "1").
# Select "Install" (entry 0), skip the wait, and drop the media check so the
# kickstart starts as soon as the ISO boots. --skip-mkefiboot avoids losetup;
# refresh-efiboot.py copies that menu into the embedded UEFI image.
iso: $(OUT_ISO)

REFRESH_EFIBOOT ?= $(MAKEFILE_DIR)/scripts/refresh-efiboot.py

RECOVERY_DIR ?= $(MAKEFILE_DIR)/recovery

$(OUT_ISO): $(KS) $(SRC_ISO) $(REFRESH_EFIBOOT) $(wildcard $(RECOVERY_DIR)/*)
	$(PYTHON) $(VALIDATE_KS) $(KS_VERSION) $(KS)
	rm -f $@
	$(MKKSISO) --skip-mkefiboot --no-md5sum --ks $(KS) \
		--add $(RECOVERY_DIR) \
		--rm-args 'rd.live.check' \
		-R 'set default="1"' 'set default="0"' \
		-R 'set timeout=60' 'set timeout=0' \
		$(SRC_ISO) $@
	$(PYTHON) $(REFRESH_EFIBOOT) $@

verify-src: $(SRC_ISO)
	$(CHECKISOMD5) $(SRC_ISO)
