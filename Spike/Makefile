# Phase 0 spikes (plan Step 1). Root Makefile delegates: $(MAKE) -C Spike <target>.
SWIFTC      ?= xcrun swiftc
SWIFTFLAGS  ?= -swift-version 6 -O
BUILD       := build
APP_NAME    := FinderVisorSpike
APP         := $(BUILD)/$(APP_NAME).app
# Signing: SPIKE_SIGN_IDENTITY overrides; else the first valid code-signing identity; else ad-hoc ("-").
SPIKE_SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $$2; exit}')
SIGN_ID     := $(if $(strip $(SPIKE_SIGN_IDENTITY)),$(SPIKE_SIGN_IDENTITY),-)

.PHONY: spike hide-spike hotkey-spike spike-app frame-dump run-spike-app clean

spike: hide-spike hotkey-spike spike-app $(BUILD)/frame-dump

hide-spike: $(BUILD)/HideSpike
hotkey-spike: $(BUILD)/HotkeySpike

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/HideSpike: HideSpike/main.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<

$(BUILD)/HotkeySpike: HotkeySpike/main.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<

$(BUILD)/frame-dump: frame-dump.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<

# Builds (if needed) and prints the Finder window table.
frame-dump: $(BUILD)/frame-dump
	./$(BUILD)/frame-dump

spike-app: $(APP)

$(APP): SpikeApp/main.swift SpikeApp/Info.plist SpikeApp/FinderVisorSpike.entitlements | $(BUILD)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp SpikeApp/Info.plist $(APP)/Contents/Info.plist
	$(SWIFTC) $(SWIFTFLAGS) -o $(APP)/Contents/MacOS/$(APP_NAME) SpikeApp/main.swift
	codesign --force --options runtime --entitlements SpikeApp/FinderVisorSpike.entitlements --sign "$(SIGN_ID)" $(APP)
	@echo "Signed $(APP) with identity: $(SIGN_ID)$(if $(filter -,$(SIGN_ID)), (ad-hoc: TCC grants reset on every rebuild),)"

# Launch through LaunchServices so TCC attributes permissions to the app, not the terminal.
run-spike-app: $(APP)
	open $(APP)

clean:
	rm -rf $(BUILD)
