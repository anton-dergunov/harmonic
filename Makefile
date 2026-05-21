APP_NAME := Harmonic
CONFIG ?= release
BUILD_DIR := .build/$(CONFIG)
BINARY := $(BUILD_DIR)/$(APP_NAME)

.PHONY: all build run clean debug

all: build

build:
	swift build -c $(CONFIG)

run: build
	@echo "Launching $(BINARY)…"
	@$(BINARY)

clean:
	swift package clean

debug:
	$(MAKE) build CONFIG=debug
	$(MAKE) run CONFIG=debug
