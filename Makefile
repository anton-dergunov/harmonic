APP_NAME := Harmonic
VERSION := 0.1.0
CONFIG ?= release
BUILD_DIR := .build/$(CONFIG)
BINARY := $(BUILD_DIR)/$(APP_NAME)

.PHONY: all build run clean debug app dmg dist

all: build

build:
	swift build -c $(CONFIG)

run: build
	@echo "Launching $(BINARY)…"
	@$(BINARY)

app: build
	@scripts/create_app_bundle.sh $(VERSION)

dmg: app
	@scripts/create_dmg.sh $(VERSION)

dist: dmg
	@echo "✓ Distribution package ready at build/$(APP_NAME)-$(VERSION).dmg"

clean:
	swift package clean
	rm -rf build

debug:
	$(MAKE) build CONFIG=debug
	$(MAKE) run CONFIG=debug
