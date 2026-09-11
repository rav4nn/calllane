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

.PHONY: build run test driver pkg install-driver release snap clean

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
	codesign --force --sign - $(DRIVER)

pkg: driver
	pkgbuild --component $(DRIVER) --install-location $(HAL_DIR) \
		--identifier dev.rav4nn.calllane.driver --version $(VERSION) \
		--scripts Driver/pkg/scripts $(PKG)

install-driver: pkg
	sudo installer -pkg $(PKG) -target /

release: build
	cd $(BUILD) && ditto -c -k --keepParent $(APP).app $(APP).zip
	shasum -a 256 $(BUILD)/$(APP).zip

clean:
	rm -rf .build $(BUILD)

snap:
	scripts/snap.sh
