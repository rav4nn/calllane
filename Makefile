APP     = CallLane
BUILD   = build
BUNDLE  = $(BUILD)/$(APP).app
BIN     = .build/release/$(APP)
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Sources/$(APP)/Info.plist)

DRIVER  = $(BUILD)/$(APP).driver
PKG     = $(BUILD)/$(APP)Driver.pkg
HAL_DIR = /Library/Audio/Plug-Ins/HAL
# The device the call apps pick is output only; its hidden twin is the input the app reads.
# Both share one ring inside coreaudiod. 48 kHz only: the engine assumes it.
DRIVER_DEFINES = \
	-DkDriver_Name='"$(APP)"' \
	-DkPlugIn_BundleID='"dev.rav4nn.calllane.driver"' \
	-DkHas_Driver_Name_Format=false \
	-DkDevice_Name='"$(APP)"' \
	-DkDevice_HasInput=false \
	-DkDevice2_Name='"$(APP) Tap"' \
	-DkDevice2_HasOutput=false \
	-DkDevice2_IsHidden=true \
	-DkEnableVolumeControl=false \
	-DkManufacturer_Name='"$(APP)"' \
	-DkNumber_Of_Channels=2 \
	-DkLatency_Frame_Size=0 \
	-DkSampleRates=48000

DMG     = $(BUILD)/$(APP)-$(VERSION).dmg
INST_PKG = $(BUILD)/$(APP).pkg

.PHONY: build run test driver pkg install-driver uninstall-driver release dmg snap clean

build:
	swift build -c release
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Sources/$(APP)/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(BUNDLE)

run: build
	open $(BUNDLE)

# Command Line Tools keep the Swift Testing macro plugin in a folder swiftc does not search.
TESTING_PLUGINS = /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
TEST_FLAGS = $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

test:
	swift test $(TEST_FLAGS)

driver:
	rm -rf $(DRIVER)
	mkdir -p $(DRIVER)/Contents/MacOS
	clang -bundle -O2 -framework CoreAudio -framework CoreFoundation -framework Accelerate \
		$(DRIVER_DEFINES) -o $(DRIVER)/Contents/MacOS/$(APP) Driver/BlackHole.c
	sed 's/@VERSION@/$(VERSION)/' Driver/Info.plist > $(DRIVER)/Contents/Info.plist
	mkdir -p $(DRIVER)/Contents/Resources
	cp Driver/LICENSE Driver/NOTICE $(DRIVER)/Contents/Resources/   # GPL-3: the licence ships with the binary
	codesign --force --sign - $(DRIVER)

# --root with a fixed component plist: a plain --component pkg is relocatable, and Installer
# could then update a stray build/CallLane.driver instead of the HAL folder.
pkg: driver
	rm -rf $(BUILD)/pkgroot && mkdir -p $(BUILD)/pkgroot
	cp -R $(DRIVER) $(BUILD)/pkgroot/
	pkgbuild --root $(BUILD)/pkgroot --component-plist Driver/pkg/component.plist \
		--install-location $(HAL_DIR) --identifier dev.rav4nn.calllane.driver \
		--version $(VERSION) --scripts Driver/pkg/scripts $(PKG)

install-driver: pkg
	sudo installer -pkg $(PKG) -target /

# Quit first: the app's quit handler puts the input device and gain back (the cask does the same).
uninstall-driver:
	-osascript -e 'quit app "$(APP)"'
	sudo rm -rf $(HAL_DIR)/$(APP).driver
	sudo pkgutil --forget dev.rav4nn.calllane.driver || true
	sudo killall coreaudiod

# Renders Casks/calllane.rb (a template) into build/calllane.rb with version and sha; the
# workflow uploads it and the tap takes it as is.
release: build pkg
	rm -rf $(BUILD)/dist && mkdir -p $(BUILD)/dist
	cp -R $(BUNDLE) $(BUILD)/dist/
	cp $(PKG) $(BUILD)/dist/
	cd $(BUILD)/dist && ditto -c -k --norsrc . ../$(APP).zip
	shasum -a 256 $(BUILD)/$(APP).zip | tee $(BUILD)/sha256.txt
	sed -e 's/@VERSION@/$(VERSION)/' -e "s/@SHA256@/$$(cut -d' ' -f1 $(BUILD)/sha256.txt)/" Casks/calllane.rb > $(BUILD)/calllane.rb

# Combined installer: app → /Applications, driver → HAL dir, one admin-password prompt.
dmg: build pkg
	rm -rf $(BUILD)/installer-root && mkdir -p $(BUILD)/installer-root
	cp -R $(BUNDLE) $(BUILD)/installer-root/
	pkgbuild --root $(BUILD)/installer-root --component-plist Installer/app-component.plist \
		--install-location /Applications --identifier dev.rav4nn.calllane \
		--version $(VERSION) $(BUILD)/$(APP)-app.pkg
	sed 's/@VERSION@/$(VERSION)/' Installer/distribution.xml > $(BUILD)/distribution.xml
	productbuild --distribution $(BUILD)/distribution.xml \
		--package-path $(BUILD) --resources . $(INST_PKG)
	rm -rf $(BUILD)/dmg-stage && mkdir -p $(BUILD)/dmg-stage
	cp $(INST_PKG) $(BUILD)/dmg-stage/
	hdiutil create -volname "CallLane $(VERSION)" -srcfolder $(BUILD)/dmg-stage \
		-fs HFS+ -format UDZO -imagekey zlib-level=9 -ov $(DMG)
	@echo "$(DMG) ready."

clean:
	rm -rf .build $(BUILD)

snap:
	scripts/snap.sh

# LaneMeter: floating on-screen meter for demo recordings (Tools/LaneMeter). Not shipped.
METER = $(BUILD)/LaneMeter.app
meter:
	rm -rf $(METER)
	mkdir -p $(METER)/Contents/MacOS
	swiftc -O -framework AppKit -framework CoreAudio -framework SwiftUI Tools/LaneMeter/main.swift -o $(METER)/Contents/MacOS/LaneMeter
	cp Tools/LaneMeter/Info.plist $(METER)/Contents/Info.plist
	codesign --force --sign - $(METER)
