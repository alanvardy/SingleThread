SIM := platform=iOS Simulator,name=iPhone 17
DERIVED_DATA := DerivedData

.PHONY: build test ui-test check clean lint format periphery

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing
test:
	./scripts/test.sh --unit-only

ui-test:
	./scripts/test.sh --ui-only

check:
	./scripts/test.sh

clean:
	xcodebuild -scheme SingleThread -destination '$(SIM)' clean

lint:
	swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint lint --strict

format:
	swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint --fix

periphery:
	periphery scan --strict -- -destination "platform=iOS Simulator,name=iPhone 17"
