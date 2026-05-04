# SPDX-License-Identifier: BSD-2-Clause

TARGETS :=

include $(wildcard projects/*/Makefile.virtioso_build)

TARGETS := $(sort $(TARGETS))

all:
	@echo "Possible make targets are:"
	@echo
	@echo "  Configuration:"
	@echo "    menuconfig         - Interactive configuration menu"
	@echo "    <name>_defconfig   - Load defconfig (e.g., ARCH=arm64 orinagx_defconfig)"
	@echo "    savedefconfig      - Save minimal config to defconfig file"
	@echo "    oldconfig          - Update config with new options"
	@echo
	@echo "  Build:"
	@echo "    sel4test           - Build seL4 test suite"
	@echo "    vm_minimal         - Build minimal VM example"
	@echo "    vm_multi           - Build multi-VM example"
	@echo "    isengard           - Build Isengard for ISENGARD_HOST={sel4,linux}"
	@echo "    linux-image        - Build Yocto Linux images"
	@echo "    linux-kernel-image - Build Yocto Linux kernel image only"
	@echo "    kmod-sel4-virt     - Build Yocto kernel-module-sel4-virt recipe"
	@echo "    qemu-runtime-x86_64 - Build relocatable Yocto host QEMU runtime artifact"
	@echo "    isengard-linux-native - Build Linux-native Isengard shared-core demo and parity test"
	@echo "    isengard-linux-image  - Build Yocto Isengard Linux image for Orin AGX bare-metal boot"
	@echo
	@echo "  Variables:"
	@echo "    ARCH={arm64,x86_64}"
	@echo "    CROSS_COMPILE=<toolchain-prefix>"
	@echo "    ISENGARD_HOST={sel4,linux}"
	@echo
	@echo "  Clean:"
	@echo "    clean              - Remove build outputs"
	@echo "    mrproper           - Remove build outputs and .config"
	@echo "    distclean          - Remove everything including backups"
	@echo
	@echo "  Other:"
	@echo "    docker             - Build Docker container"
	@echo "    shell              - Enter Docker shell"
	@echo "    build_cache        - Pre-populate Haskell cache"
	@echo

# Kconfig tools
CONF := scripts/kconfig/conf
MCONF := scripts/kconfig/mconf

ARCH ?=
CROSS_COMPILE ?=
ISENGARD_HOST ?= sel4

CONFIG_FILE := .config

export KCONFIG_CONFIG := $(CONFIG_FILE)

ifeq ($(origin CROSS_COMPILE), environment)
ifneq ($(ARCH),arm64)
CROSS_COMPILE :=
endif
endif

export ARCH
export CROSS_COMPILE
export ISENGARD_HOST

$(CONF) $(MCONF):
	$(MAKE) -C scripts/kconfig

# Configuration targets
menuconfig: $(MCONF)
	$< Kconfig

%_defconfig: $(CONF)
	$< --defconfig=configs/$@ Kconfig

savedefconfig: $(CONF)
	$< --savedefconfig=defconfig Kconfig

oldconfig: $(CONF)
	$< --oldconfig Kconfig

olddefconfig: $(CONF)
	$< --olddefconfig Kconfig

alldefconfig: $(CONF)
	$< --alldefconfig Kconfig

# Clean targets
clean:
	rm -rf *_sel4test
	@for target in $(TARGETS); do rm -rf *_$$target; done
	$(MAKE) -C scripts/kconfig clean

mrproper: clean
	rm -f .config .config.old defconfig

distclean: mrproper
	rm -f *~ \#*\# *.orig *.rej *.swp

# Build configuration
BUILD_CACHE_DIR ?= $(shell realpath .virtioso_build 2>/dev/null || echo .virtioso_build)
export BUILD_CACHE_DIR

DOCKER_EXPORT = ARCH CROSS_COMPILE CAMKES_VM_APP
export DOCKER_EXPORT

$(BUILD_CACHE_DIR)/stack:
	mkdir -p $(BUILD_CACHE_DIR)/stack
	@scripts/build_cache.sh

build_cache: $(BUILD_CACHE_DIR)/stack

build_camkes: $(CONFIG_FILE) build_cache
	@scripts/build_camkes.sh

build_sel4test: $(CONFIG_FILE)
	@scripts/build_sel4test.sh

$(TARGETS): phony_explicit
	@if [ "$@" = "isengard" ] && [ "$(ISENGARD_HOST)" = "linux" ]; then \
		$(MAKE) isengard-linux-native; \
	elif [ "$@" = "isengard" ] && [ "$(ISENGARD_HOST)" != "sel4" ]; then \
		echo "Unsupported ISENGARD_HOST='$(ISENGARD_HOST)'; expected sel4 or linux" >&2; \
		exit 1; \
	else \
		CAMKES_VM_APP=$@ $(MAKE) build_camkes; \
	fi

sel4test:
	$(MAKE) build_sel4test

phony_explicit:

.PHONY: \
	all \
	menuconfig \
	savedefconfig \
	oldconfig \
	olddefconfig \
	alldefconfig \
	clean \
	mrproper \
	distclean \
	phony_explicit \
	docker \
	shell \
	linux-image \
	linux-kernel-image \
	kmod-sel4-virt \
	qemu-runtime-x86_64 \
	isengard-linux-native \
	isengard-linux-image \
	build_cache \
	build_camkes \
	build_sel4test \
	sel4test \
	$(TARGETS)

docker:
	docker buildx build --network=host \
		--build-arg UID=$(shell id -u) \
		--build-arg GID=$(shell id -g) \
		--build-arg USER=$(shell id -u -n) \
		--build-arg GROUP=$(shell id -u -n) \
		--build-arg HOME=$(HOME) \
		docker -t virtioso/build:latest

linux-image:
	@scripts/build_yocto.sh

linux-kernel-image:
	@scripts/build_yocto_kernel_image.sh

kmod-sel4-virt:
	@scripts/build_yocto_kmod_sel4_virt.sh

qemu-runtime-x86_64:
	@scripts/build_yocto_qemu_runtime_x86_64.sh

isengard-linux-native:
	$(MAKE) -C sources/isengard-core

isengard-linux-image:
	@MACHINE=isengard-agx-orin scripts/build_isengard_linux.sh

shell:
	@docker/enter_container.sh
