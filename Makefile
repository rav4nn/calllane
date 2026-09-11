APP     = CallLane
BUILD   = build
BUNDLE  = $(BUILD)/$(APP).app
BIN     = .build/release/$(APP)

.PHONY: build run test release snap clean

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

release: build
	cd $(BUILD) && ditto -c -k --keepParent $(APP).app $(APP).zip
	shasum -a 256 $(BUILD)/$(APP).zip

clean:
	rm -rf .build $(BUILD)

snap:
	scripts/snap.sh
