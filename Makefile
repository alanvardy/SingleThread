SIM := platform=iOS Simulator,name=iPhone 17
DERIVED_DATA := DerivedData

.PHONY: build test clean lint format

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing -only-testing:SingleThreadTests

test:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath '$(DERIVED_DATA)' test-without-building -only-testing:SingleThreadTests

clean:
	xcodebuild -scheme SingleThread -destination '$(SIM)' clean

lint:
	swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint lint --strict --config .swiftlint.yml

format:
	swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint --fix --config .swiftlint.yml
