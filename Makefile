PROJECT := SSH Keys Manager.xcodeproj
SCHEME := SSH Keys Manager
CONFIGURATION := Release
SHELL_SCRIPT := scripts/build-release-dmg.sh
DSYM_SCRIPT := scripts/package-dsyms.sh
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo dev)
APP_SLUG := SSH-Keys-Manager
VERSIONED_DMG := dist/$(APP_SLUG)-$(VERSION).dmg
LATEST_DMG := dist/$(APP_SLUG).dmg
DSYMS_ZIP := dist/$(APP_SLUG)-$(VERSION)-dSYMs.zip

.PHONY: help release-app release-dmg release-dmg-latest release-dsyms release-assets clean-release

help:
	@echo "Available targets:"
	@echo "  make release-app   Build the release .app into build/release"
	@echo "  make release-dmg   Build dist/$(APP_SLUG)-<version>.dmg"
	@echo "  make release-dmg-latest  Copy the versioned DMG to dist/$(APP_SLUG).dmg"
	@echo "  make release-dsyms Build dist/$(APP_SLUG)-<version>-dSYMs.zip"
	@echo "  make release-assets Build DMG, stable DMG alias, and dSYMs zip"
	@echo "  make clean-release Remove build/release and dist artifacts"

release-app:
	@bash $(SHELL_SCRIPT) --build-only --release-version "$(VERSION)"

release-dmg:
	@bash $(SHELL_SCRIPT) --release-version "$(VERSION)" --output "$(VERSIONED_DMG)"

release-dmg-latest: release-dmg
	@cp "$(VERSIONED_DMG)" "$(LATEST_DMG)"
	@echo "$(LATEST_DMG)"

release-dsyms: release-app
	@bash $(DSYM_SCRIPT) --release-version "$(VERSION)" --output "$(DSYMS_ZIP)"

release-assets: release-dmg release-dmg-latest
	@bash $(DSYM_SCRIPT) --release-version "$(VERSION)" --output "$(DSYMS_ZIP)"
	@printf "%s\n%s\n%s\n" "$(VERSIONED_DMG)" "$(LATEST_DMG)" "$(DSYMS_ZIP)"

clean-release:
	@rm -rf build/release dist
