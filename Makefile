# FinderVisor build entry points. Requires only Xcode (27+) command line tools.

PROJECT        := FinderVisor.xcodeproj
SCHEME         := FinderVisor
CONFIGURATION  ?= Release
DERIVED_DATA   := build
APP_NAME       := FinderVisor.app
APP_PATH       := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)
INSTALL_DIR    := /Applications
BUNDLE_ID      := io.github.findervisor.FinderVisor
PACKAGE_PATH   := Packages/VisorCore
LOCAL_XCCONFIG := Config/Local.xcconfig

# Last unconditional CODE_SIGN_IDENTITY in Config/Local.xcconfig (quotes and trailing comments stripped), if any.
SIGNING_IDENTITY = $(shell [ -f $(LOCAL_XCCONFIG) ] && sed -n -E \
	's@^[[:space:]]*CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*"?([^"/]*[^"/[:space:]])"?[[:space:]]*(//.*)?$$@\1@p' \
	$(LOCAL_XCCONFIG) | tail -n 1)

# "missing" when Local.xcconfig names a real identity that is not a valid, trusted code-signing identity.
SIGNING_STATUS = $(shell id='$(SIGNING_IDENTITY)'; \
	if [ -z "$$id" ] || [ "$$id" = "-" ]; then echo none; \
	elif security find-identity -v -p codesigning 2>/dev/null | grep -F -q "\"$$id\""; then echo ok; \
	else echo missing; fi)

AD_HOC_OVERRIDE := CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

.PHONY: build test install reset-permissions check-signing spike frame-dump clean

build: check-signing
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA) \
		$(if $(filter missing,$(SIGNING_STATUS)),$(AD_HOC_OVERRIDE)) \
		build
	@echo "Built $(APP_PATH)"

test:
	swift test --package-path $(PACKAGE_PATH)

check-signing:
	@case "$(SIGNING_STATUS)" in \
	ok) echo "check-signing: using code-signing identity '$(SIGNING_IDENTITY)'." ;; \
	none) echo "check-signing: no signing identity in $(LOCAL_XCCONFIG); building ad-hoc (permissions will reset on every rebuild). See Config/Local.xcconfig.example." ;; \
	missing) echo "warning: signing identity '$(SIGNING_IDENTITY)' not found or not trusted — falling back to ad-hoc; permissions will reset on every rebuild." >&2 ;; \
	esac

install: build
	rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	ditto "$(APP_PATH)" "$(INSTALL_DIR)/$(APP_NAME)"
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME)"

reset-permissions:
	-tccutil reset Accessibility $(BUNDLE_ID)
	-tccutil reset AppleEvents $(BUNDLE_ID)
	-tccutil reset ListenEvent $(BUNDLE_ID)

spike:
	$(MAKE) -C Spike spike

frame-dump:
	$(MAKE) -C Spike frame-dump

clean:
	rm -rf $(DERIVED_DATA) $(PACKAGE_PATH)/.build
