SIM := platform=iOS Simulator,name=iPhone 17
DERIVED_DATA := DerivedData

.PHONY: build test ui-test clean lint format periphery

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

test:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath '$(DERIVED_DATA)' test-without-building -only-testing:SingleThreadTests

ui-test:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath '$(DERIVED_DATA)' test-without-building -only-testing:SingleThreadUITests

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
