PROJECT := RaceFuelTimer.xcodeproj
SCHEME := RaceFuelTimer
DESTINATION := generic/platform=iOS Simulator
TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 16,OS=18.3.1
DERIVED_DATA := build/DerivedData

.PHONY: lint typecheck test build

lint:
	@find RaceFuelTimer RaceFuelTimerTests -name '*.swift' -print0 | xargs -0 swiftc -parse

typecheck:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) build-for-testing CODE_SIGNING_ALLOWED=NO

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(TEST_DESTINATION)' -derivedDataPath $(DERIVED_DATA) test CODE_SIGNING_ALLOWED=NO

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) build CODE_SIGNING_ALLOWED=NO
