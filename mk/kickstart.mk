.PHONY: ks validate

ks: $(KS) $(IMAGE_KS)

$(OUT_DIR):
	mkdir -p $@

SECRET_FILES := $(wildcard $(ADMIN_PASSWORD_FILE) $(ROOT_PASSWORD_FILE) $(ADMIN_PUBKEY_FILE))
RECOVERY_SCRIPTS := $(wildcard $(MAKEFILE_DIR)/recovery/*.sh)

$(KS): $(KS_TEMPLATE) $(RENDER_KS) $(SECRET_FILES) $(RECOVERY_SCRIPTS) | $(OUT_DIR)
	$(PYTHON) $(RENDER_KS) $(RENDER_FLAGS) --layout install --output $@

$(IMAGE_KS): $(KS_TEMPLATE) $(RENDER_KS) $(SECRET_FILES) $(RECOVERY_SCRIPTS) | $(OUT_DIR)
	$(PYTHON) $(RENDER_KS) $(RENDER_FLAGS) --layout image --output $@

validate: | $(OUT_DIR)
	$(PYTHON) $(RENDER_KS) $(RENDER_FLAGS) --dummy --layout install --output $(OUT_DIR)/.ks-syntax.ks
	$(PYTHON) $(VALIDATE_KS) $(KS_VERSION) $(OUT_DIR)/.ks-syntax.ks
	$(PYTHON) $(RENDER_KS) $(RENDER_FLAGS) --dummy --layout image --output $(OUT_DIR)/.ks-syntax-image.ks
	$(PYTHON) $(VALIDATE_KS) $(KS_VERSION) $(OUT_DIR)/.ks-syntax-image.ks
	rm -f $(OUT_DIR)/.ks-syntax.ks $(OUT_DIR)/.ks-syntax-image.ks
