SIM := platform=iOS Simulator,name=iPhone 17
WATCH_SIM := generic/platform=watchOS Simulator
DERIVED_DATA := DerivedData

.PHONY: build watch-build test ui-test check clean lint format periphery

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing

watch-build:
	xcodebuild -scheme SingleThreadWatch -destination '$(WATCH_SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build

test:
	./scripts/test.sh --unit-only

ui-test:
	./scripts/test.sh --ui-only

check:
	./scripts/test.sh

clean:
	xcodebuild -scheme SingleThread -destination '$(SIM)' clean

lint:
	swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadTests/ SingleThreadUITests/
	swiftlint lint --strict

format:
	swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadTests/ SingleThreadUITests/
	swiftlint --fix

periphery:
	periphery scan --strict -- -destination "platform=iOS Simulator,name=iPhone 17"
