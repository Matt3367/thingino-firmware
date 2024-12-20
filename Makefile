# Thingino Firmware
# https://github.com/themactep/thingino-firmware

ifeq ($(__BASH_MAKE_COMPLETION__),1)
	exit
endif

ifneq ($(shell command -v gawk >/dev/null; echo $$?),0)
$(error Please run `make bootstrap` to install prerequisites.)
endif

ifneq ($(findstring $(empty) $(empty),$(CURDIR)),)
$(error Current directory path "$(CURDIR)" contains spaces. Please remove spaces from the path and try again.)
endif

# Camera IP address
# shortened to just IP for convenience of running from command line
IP ?= 192.168.1.10
CAMERA_IP_ADDRESS = $(IP)

# Device of SD card
SDCARD_DEVICE ?= /dev/sdf

# TFTP server IP address to upload compiled images to
TFTP_IP_ADDRESS ?= 192.168.1.254

# Buildroot downloads directory
# can be reused from environment, just export the value:
# export BR2_DL_DIR = /path/to/your/local/storage
BR2_DL_DIR ?= $(HOME)/dl

# directory for extracting Buildroot sources
SRC_DIR ?= $(HOME)/src

# working directory
OUTPUT_DIR ?= $(HOME)/output/$(CAMERA)
STDOUT_LOG ?= $(OUTPUT_DIR)/compilation.log
STDERR_LOG ?= $(OUTPUT_DIR)/compilation-errors.log

# project directories
BR2_EXTERNAL := $(CURDIR)
SCRIPTS_DIR := $(BR2_EXTERNAL)/scripts

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BR2_EXTERNAL)/buildroot BR2_EXTERNAL=$(BR2_EXTERNAL) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) O=$(OUTPUT_DIR)
# handle the board
include $(BR2_EXTERNAL)/board.mk

# include device tree makefile
include $(BR2_EXTERNAL)/external.mk

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=5

ifeq ($(shell command -v figlet),)
FIGLET := echo
else
FIGLET := $(shell command -v figlet) -t -f pagga
endif

SIZE_32M := 33554432
SIZE_16M := 16777216
SIZE_8M := 8388608
SIZE_256K := 262144
SIZE_128K := 131072
SIZE_64K := 65536
SIZE_32K := 32768
SIZE_16K := 16384
SIZE_8K := 8192
SIZE_4K := 4096

ALIGN_BLOCK := $(SIZE_32K)

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest

U_BOOT_ENV_FINAL_TXT = $(OUTPUT_DIR)/uenv.txt
export U_BOOT_ENV_FINAL_TXT

ifeq ($(BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME),)
U_BOOT_BIN = $(OUTPUT_DIR)/images/u-boot-lzo-with-spl.bin
else
U_BOOT_BIN = $(OUTPUT_DIR)/images/$(patsubst "%",%,$(BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME))
endif

CONFIG_BIN := $(OUTPUT_DIR)/images/config.jffs2
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
ROOTFS_TAR := $(OUTPUT_DIR)/images/rootfs.tar
OVERLAY_BIN := $(OUTPUT_DIR)/images/overlay.jffs2

# create a full binary file suffixed with the time of the last modification to either uboot, kernel, or rootfs
FIRMWARE_NAME_FULL = thingino-$(CAMERA).bin
FIRMWARE_NAME_NOBOOT = thingino-$(CAMERA)-update.bin

FIRMWARE_BIN_FULL := $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)
FIRMWARE_BIN_NOBOOT := $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_NOBOOT)

# file sizes
U_BOOT_BIN_SIZE = $(shell stat -c%s $(U_BOOT_BIN))
KERNEL_BIN_SIZE = $(shell stat -c%s $(KERNEL_BIN))
ROOTFS_BIN_SIZE = $(shell stat -c%s $(ROOTFS_BIN))
CONFIG_BIN_SIZE = $(shell stat -c%s $(CONFIG_BIN))
OVERLAY_BIN_SIZE = $(shell stat -c%s $(OVERLAY_BIN))

FIRMWARE_BIN_FULL_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_FULL))
FIRMWARE_BIN_NOBOOT_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_NOBOOT))

U_BOOT_BIN_SIZE_ALIGNED = $(shell echo $$((($(U_BOOT_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
CONFIG_BIN_SIZE_ALIGNED = $(shell echo $$((($(CONFIG_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
KERNEL_BIN_SIZE_ALIGNED = $(shell echo $$((($(KERNEL_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
ROOTFS_BIN_SIZE_ALIGNED = $(shell echo $$((($(ROOTFS_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
OVERLAY_BIN_SIZE_ALIGNED = $(shell echo $$((($(OVERLAY_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))

# fixed size partitions
U_BOOT_PARTITION_SIZE := $(SIZE_256K)
U_BOOT_ENV_PARTITION_SIZE := $(SIZE_64K)
CONFIG_PARTITION_SIZE := $(SIZE_64K)
KERNEL_PARTITION_SIZE = $(KERNEL_BIN_SIZE_ALIGNED)
ROOTFS_PARTITION_SIZE = $(ROOTFS_BIN_SIZE_ALIGNED)

FIRMWARE_FULL_SIZE = $(FLASH_SIZE)
FIRMWARE_NOBOOT_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(U_BOOT_PARTITION_SIZE) - $(U_BOOT_ENV_PARTITION_SIZE))))

# dynamic partitions
OVERLAY_PARTITION_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(OVERLAY_OFFSET))))
OVERLAY_LLIMIT = $(shell echo $$(($(ALIGN_BLOCK) * 5)))

# partition offsets
U_BOOT_OFFSET := 0
U_BOOT_ENV_OFFSET = $(shell echo $$(($(U_BOOT_OFFSET) + $(U_BOOT_PARTITION_SIZE))))
#CONFIG_OFFSET = $(shell echo $$(($(U_BOOT_ENV_OFFSET) + $(U_BOOT_ENV_PARTITION_SIZE))))
#KERNEL_OFFSET = $(shell echo $$(($(CONFIG_OFFSET) + $(CONFIG_PARTITION_SIZE))))
KERNEL_OFFSET = $(shell echo $$(($(U_BOOT_ENV_OFFSET) + $(U_BOOT_ENV_PARTITION_SIZE))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))))
OVERLAY_OFFSET = $(shell echo $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))))

# special case with no uboot nor env
OVERLAY_OFFSET_NOBOOT = $(shell echo $$(($(KERNEL_PARTITION_SIZE) + $(ROOTFS_PARTITION_SIZE))))

.PHONY: all bootstrap build build_fast clean cleanbuild create_overlay \
	defconfig distclean fast help pack pack_full pack_update \
	prepare_config reconfig sdk toolchain update upload_tftp upgrade_ota br-%

all: build pack
	$(info -------------------------------- $@)
	@$(FIGLET) "FINE"

# update repo and submodules
update:
	$(info -------------------------------- $@)
	git pull --rebase --autostash
	git submodule update

# install what's needed
bootstrap:
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/dep_check.sh

build: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) all

build_fast: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) -j$(shell nproc) all

fast: build_fast pack
	$(info -------------------------------- $@)
	@$(FIGLET) "FINE"

### Configuration

FRAGMENTS = $(shell awk '/FRAG:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(MODULE_CONFIG_REAL))

# Assemble config from bits and pieces
prepare_config: buildroot/Makefile
	# create output directory
	$(info * make OUTPUT_DIR $(OUTPUT_DIR))
	mkdir -p $(OUTPUT_DIR)
	# delete older config
	$(info * remove existing .config file)
	rm -rvf $(OUTPUT_DIR)/.config
	# gather fragments of a new config
	$(info * add fragments FRAGMENTS=$(FRAGMENTS) from $(MODULE_CONFIG_REAL))
	for i in $(FRAGMENTS); do \
	echo "** add configs/fragments/$$i.fragment"; \
	cat configs/fragments/$$i.fragment >>$(OUTPUT_DIR)/.config; \
	echo >>$(OUTPUT_DIR)/.config; \
	done
	# add module configuration
	cat $(MODULE_CONFIG_REAL) >>$(OUTPUT_DIR)/.config
ifneq ($(CAMERA_CONFIG_REAL),$(MODULE_CONFIG_REAL))
	# add camera configuration
	cat $(CAMERA_CONFIG_REAL) >>$(OUTPUT_DIR)/.config
endif
	# Add local.fragment to the final config
	if [ -f local.fragment ]; then cat local.fragment >>$(OUTPUT_DIR)/.config; fi
	# Add local.mk to the building directory to override settings
	if [ -f $(BR2_EXTERNAL)/local.mk ]; then cp -f $(BR2_EXTERNAL)/local.mk $(OUTPUT_DIR)/local.mk; fi
	if [ ! -L $(OUTPUT_DIR)/thingino ]; then ln -s $(BR2_EXTERNAL) $(OUTPUT_DIR)/thingino; fi


# Configure buildroot for a particular board
defconfig: prepare_config
	@$(FIGLET) $(CAMERA)
	cp $(OUTPUT_DIR)/.config $(OUTPUT_DIR)/.config_original
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) olddefconfig
	if [ -f $(BR2_EXTERNAL)$(shell sed -rn "s/^U_BOOT_ENV_TXT=\"\\\$$\(\w+\)(.+)\"/\1/p" $(OUTPUT_DIR)/.config) ]; then \
	grep -v '^#' $(BR2_EXTERNAL)$(shell sed -rn "s/^U_BOOT_ENV_TXT=\"\\\$$\(\w+\)(.+)\"/\1/p" $(OUTPUT_DIR)/.config) | tee $(U_BOOT_ENV_FINAL_TXT); fi
	if [ -f $(BR2_EXTERNAL)/local.uenv.txt ]; then \
		grep -v '^#' $(BR2_EXTERNAL)/local.uenv.txt | while read line; do \
			grep -F -x -q "$$line" $(U_BOOT_ENV_FINAL_TXT) || echo "$$line" >> $(U_BOOT_ENV_FINAL_TXT); \
		done; \
	fi

select-device:
	$(info -------------------> select-device)

# call configurator
menuconfig: $(OUTPUT_DIR)/.config
	$(info -------------------------------- $@)
	$(BR2_MAKE) menuconfig

nconfig: $(OUTPUT_DIR)/.config
	$(info -------------------------------- $@)
	$(BR2_MAKE) nconfig

# permanently save changes to the defconfig
saveconfig:
	$(info -------------------------------- $@)
	$(BR2_MAKE) savedefconfig

### Files

# remove target/ directory
clean:
	$(info -------------------------------- $@)
	rm -rf $(OUTPUT_DIR)/target

# rebuild from scratch
cleanbuild: distclean all
	$(info -------------------------------- $@)

# remove all build files
distclean:
	$(info -------------------------------- $@)
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

delete_bin_full:
	if [ -f $(FIRMWARE_BIN_FULL) ]; then rm $(FIRMWARE_BIN_FULL); fi

delete_bin_update:
	if [ -f $(FIRMWARE_BIN_NOBOOT) ]; then rm $(FIRMWARE_BIN_NOBOOT); fi

# assemble final images
pack: $(FIRMWARE_BIN_FULL) $(FIRMWARE_BIN_NOBOOT)
	$(info -------------------------------- $@)
	$(FIGLET) $(BOARD)
	$(info ALIGNMENT: $(ALIGN_BLOCK))
	$(info  )
	$(info $(shell printf "%-7s | %8s | %8s | %8s | %8s | %8s | %8s |" NAME OFFSET PT_SIZE CONTENT ALIGNED END LOSS))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" U_BOOT $(U_BOOT_OFFSET) $(U_BOOT_PARTITION_SIZE) $(U_BOOT_BIN_SIZE) $(U_BOOT_BIN_SIZE_ALIGNED) $$(($(U_BOOT_OFFSET) + $(U_BOOT_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_PARTITION_SIZE) - $(U_BOOT_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" ENV $(U_BOOT_ENV_OFFSET) $(U_BOOT_ENV_PARTITION_SIZE) $(U_BOOT_ENV_BIN_SIZE) $(U_BOOT_ENV_BIN_SIZE_ALIGNED) $$(($(U_BOOT_ENV_OFFSET) + $(U_BOOT_ENV_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_ENV_PARTITION_SIZE) - $(U_BOOT_ENV_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" KERNEL $(KERNEL_OFFSET) $(KERNEL_PARTITION_SIZE) $(KERNEL_BIN_SIZE) $(KERNEL_PARTITION_SIZE) $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))) $$(($(KERNEL_PARTITION_SIZE) - $(KERNEL_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" ROOTFS $(ROOTFS_OFFSET) $(ROOTFS_PARTITION_SIZE) $(ROOTFS_BIN_SIZE) $(ROOTFS_PARTITION_SIZE) $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))) $$(($(ROOTFS_PARTITION_SIZE) - $(ROOTFS_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" OVERLAY $(OVERLAY_OFFSET) $(OVERLAY_PARTITION_SIZE) $(OVERLAY_BIN_SIZE) $(OVERLAY_BIN_SIZE_ALIGNED) $$(($(OVERLAY_OFFSET) + $(OVERLAY_BIN_SIZE_ALIGNED))) $$(($(OVERLAY_PARTITION_SIZE) - $(OVERLAY_BIN_SIZE_ALIGNED))) ))
	$(info  )
	$(info $(shell printf "%-7s | %8s | %8s | %8s | %8s | %8s | %8s |" NAME OFFSET PT_SIZE CONTENT ALIGNED END LOSS))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" U_BOOT $(U_BOOT_OFFSET) $(U_BOOT_PARTITION_SIZE) $(U_BOOT_BIN_SIZE) $(U_BOOT_BIN_SIZE_ALIGNED) $$(($(U_BOOT_OFFSET) + $(U_BOOT_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_PARTITION_SIZE) - $(U_BOOT_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" ENV $(U_BOOT_ENV_OFFSET) $(U_BOOT_ENV_PARTITION_SIZE) $(U_BOOT_ENV_BIN_SIZE) $(U_BOOT_ENV_BIN_SIZE_ALIGNED) $$(($(U_BOOT_ENV_OFFSET) + $(U_BOOT_ENV_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_ENV_PARTITION_SIZE) - $(U_BOOT_ENV_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" KERNEL $(KERNEL_OFFSET) $(KERNEL_PARTITION_SIZE) $(KERNEL_BIN_SIZE) $(KERNEL_PARTITION_SIZE) $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))) $$(($(KERNEL_PARTITION_SIZE) - $(KERNEL_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" ROOTFS $(ROOTFS_OFFSET) $(ROOTFS_PARTITION_SIZE) $(ROOTFS_BIN_SIZE) $(ROOTFS_PARTITION_SIZE) $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))) $$(($(ROOTFS_PARTITION_SIZE) - $(ROOTFS_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" OVERLAY $(OVERLAY_OFFSET) $(OVERLAY_PARTITION_SIZE) $(OVERLAY_BIN_SIZE) $(OVERLAY_BIN_SIZE_ALIGNED) $$(($(OVERLAY_OFFSET) + $(OVERLAY_BIN_SIZE_ALIGNED))) $$(($(OVERLAY_PARTITION_SIZE) - $(OVERLAY_BIN_SIZE_ALIGNED))) ))
	$(info  )
	if [ $(FIRMWARE_BIN_FULL_SIZE) -gt $(FIRMWARE_FULL_SIZE) ]; then $(FIGLET) "OVERSIZE"; fi
	sha256sum $(FIRMWARE_BIN_FULL) | awk '{print $$1 "  " filename}' filename=$$(basename $(FIRMWARE_BIN_FULL)) > $(FIRMWARE_BIN_FULL).sha256sum
	if [ $(FIRMWARE_BIN_NOBOOT_SIZE) -gt $(FIRMWARE_NOBOOT_SIZE) ]; then $(FIGLET) "OVERSIZE"; fi
	sha256sum $(FIRMWARE_BIN_NOBOOT) | awk '{print $$1 "  " filename}' filename=$$(basename $(FIRMWARE_BIN_NOBOOT)) > $(FIRMWARE_BIN_NOBOOT).sha256sum

# rebuild a package
rebuild-%: defconfig
	$(BR2_MAKE) $(subst rebuild-,,$@)-dirclean $(subst rebuild-,,$@)

# build toolchain fast
sdk: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) -j$(shell nproc) sdk

source: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) source

# build toolchain
toolchain: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) sdk

# flash compiled update image to the camera
update_ota: $(FIRMWARE_BIN_NOBOOT)
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/fw_ota.sh $(FIRMWARE_BIN_NOBOOT) $(CAMERA_IP_ADDRESS)

# flash compiled full image to the camera
upgrade_ota: $(FIRMWARE_BIN_FULL)
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/fw_ota.sh $(FIRMWARE_BIN_FULL) $(CAMERA_IP_ADDRESS)

# upload firmware to tftp server
upload_tftp: $(FIRMWARE_BIN_FULL)
	$(info -------------------------------- $@)
	busybox tftp -l $(FIRMWARE_BIN_FULL) -r $(FIRMWARE_NAME_FULL) -p $(TFTP_IP_ADDRESS)

### Buildroot

# delete all build/{package} and per-package/{package} files
br-%-dirclean:
	$(info -------------------------------- $@)
	rm -rf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
		$(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))* \
		$(OUTPUT_DIR)/target
	#  \ sed -i /^$(subst -dirclean,,$(subst br-,,$@))/d $(OUTPUT_DIR)/build/packages-file-list.txt

br-%: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) $(subst br-,,$@)

# checkout buidroot submodule
buildroot/Makefile:
	$(info -------------------------------- $@)
	git submodule init
	git submodule update --depth 1 --recursive

# create output directory
$(OUTPUT_DIR)/.keep:
	$(info -------------------------------- $@)
	mkdir -p $(OUTPUT_DIR)
	touch $@

# configure buildroot for a particular board
$(OUTPUT_DIR)/.config: $(OUTPUT_DIR)/.keep $(SRC_DIR)/.keep defconfig
	$(info -------------------------------- $@)

# create source directory
$(SRC_DIR)/.keep:
	$(info -------------------------------- $@)
	mkdir -p $(SRC_DIR)
	touch $@

# download bootloader
$(U_BOOT_BIN):
	$(info -------------------------------- $@)
	$(info U_BOOT_BIN $(U_BOOT_BIN) not found!)
	$(WGET) -O $@ $(U_BOOT_GITHUB_URL)/u-boot-$(SOC_MODEL_LESS_Z).bin

# create config partition image
$(CONFIG_BIN):
	$(info -------------------------------- $@)
	$(OUTPUT_DIR)/host/sbin/mkfs.jffs2 --little-endian --squash \
		--root=$(BR2_EXTERNAL)/overlay/upper/ --output=$(CONFIG_BIN) \
		--pad=$(CONFIG_PARTITION_SIZE)

#$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(CONFIG_BIN) $(KERNEL_BIN) $(ROOTFS_BIN) $(OVERLAY_BIN)
#@$(info $(shell printf "%-10s | %8d / 0x%07X | %8d / 0x%07X | %8d / 0x%07X | %8d / 0x%07X | 0x%07X | 0x%07X |" CONFIG $(CONFIG_OFFSET) $(CONFIG_OFFSET) $(CONFIG_PARTITION_SIZE) $(CONFIG_PARTITION_SIZE) $(CONFIG_BIN_SIZE) $(CONFIG_BIN_SIZE) $(CONFIG_BIN_SIZE_ALIGNED) $(CONFIG_BIN_SIZE_ALIGNED) $$(($(CONFIG_OFFSET) + $(CONFIG_BIN_SIZE_ALIGNED))) $$(($(CONFIG_PARTITION_SIZE) - $(CONFIG_BIN_SIZE_ALIGNED))) ))
#@dd if=$(CONFIG_BIN) bs=$(CONFIG_BIN_SIZE) seek=$(CONFIG_OFFSET)B count=1 of=$@ conv=notrunc status=none
$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(KERNEL_BIN) $(ROOTFS_BIN) $(OVERLAY_BIN)
	$(info -------------------------------- $@)
	dd if=/dev/zero bs=$(SIZE_8M) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(U_BOOT_BIN) bs=$(U_BOOT_BIN_SIZE) seek=$(U_BOOT_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=$(KERNEL_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(ROOTFS_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(OVERLAY_BIN) bs=$(OVERLAY_BIN_SIZE) seek=$(OVERLAY_OFFSET)B count=1 of=$@ conv=notrunc status=none

$(FIRMWARE_BIN_NOBOOT): $(KERNEL_BIN) $(ROOTFS_BIN) $(OVERLAY_BIN)
	$(info -------------------------------- $@)
	dd if=/dev/zero bs=$(FIRMWARE_NOBOOT_SIZE) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=0 count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(KERNEL_PARTITION_SIZE)B count=1 of=$@ conv=notrunc status=none
	dd if=$(OVERLAY_BIN) bs=$(OVERLAY_BIN_SIZE) seek=$(OVERLAY_OFFSET_NOBOOT)B count=1 of=$@ conv=notrunc status=none

# rebuild kernel
$(KERNEL_BIN):
	$(info -------------------------------- $@)
	$(BR2_MAKE) linux-rebuild
#	mv -vf $(OUTPUT_DIR)/images/uImage $@

# rebuild rootfs
$(ROOTFS_BIN):
	$(info -------------------------------- $@)
	$(BR2_MAKE) all

# create .tar file of rootfs
$(ROOTFS_TAR):
	$(info -------------------------------- $@)
	$(BR2_MAKE) all

$(OVERLAY_BIN): $(U_BOOT_BIN)
	$(info -------------------------------- $@)
	if [ $(OVERLAY_PARTITION_SIZE) -lt $(OVERLAY_LLIMIT) ]; then $(FIGLET) "OVERLAY IS TOO SMALL"; fi
	if [ -f $(OVERLAY_BIN) ]; then rm $(OVERLAY_BIN); fi
	$(OUTPUT_DIR)/host/sbin/mkfs.jffs2 --little-endian --squash \
		--root=$(BR2_EXTERNAL)/overlay/upper/ --output=$(OVERLAY_BIN) \
		--pad=$(OVERLAY_PARTITION_SIZE) --eraseblock=$(ALIGN_BLOCK)
       #	--pagesize=$(ALIGN_BLOCK)

	$(info -------------------------------- $@)


help:
	$(info -------------------------------- $@)
	@echo "\n\
	Usage:\n\
	  make bootstrap      install system deps\n\
	  make update         update local repo from GitHub\n\
	  make defconfig      (re)create config file\n\
	  make                build and pack everything\n\
	  make build          build kernel and rootfs\n\
	  make cleanbuild     build everything from scratch\n\
	  make pack_full      create a full firmware image\n\
	  make pack_update    create an update firmware image (no bootloader)\n\
	  make clean          clean before reassembly\n\
	  make distclean      start building from scratch\n\
	  make rebuild-<pkg>  perform a clean package rebuild for <pkg>\n\
	  make help           print this help\n\
	  \n\
	  make upgrade_ota IP=192.168.1.10\n\
	                      upload the full firmware file to the camera\n\
	                        over network, and flash it\n\n\
	  make update_ota IP=192.168.1.10\n\
	                      upload the update firmware file to the camera\n\
	                        over network, and flash it\n\n\
	"
