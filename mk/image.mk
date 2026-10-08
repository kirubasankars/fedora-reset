.PHONY: image

image: $(IMAGE_DIR)/$(IMAGE_NAME)

$(IMAGE_DIR)/$(IMAGE_NAME): $(IMAGE_KS) $(SRC_ISO)
	$(PYTHON) $(VALIDATE_KS) $(KS_VERSION) $(IMAGE_KS)
	rm -rf $(IMAGE_DIR)
	mkdir -p $(IMAGE_DIR)
	$(AS_ROOT) $(LIVEMEDIA_CREATOR) \
		--make-disk \
		$(if $(filter 1,$(VIRT_UEFI)),--virt-uefi,) \
		--iso $(SRC_ISO) \
		--ks $(IMAGE_KS) \
		--image-type $(IMAGE_TYPE) \
		--image-name $(IMAGE_NAME) \
		--resultdir $(IMAGE_DIR) \
		--ram $(IMAGE_RAM) \
		--vcpus $(IMAGE_VCPUS) \
		--logfile $(OUT_DIR)/livemedia-creator.log
