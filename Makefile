SIM := platform=iOS Simulator,name=iPhone 17

.PHONY: build test clean lint format

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug build

test:
	xcodebuild test -scheme SingleThread -destination '$(SIM)' -only-testing:SingleThreadTests

clean:
	xcodebuild -scheme SingleThread -destination '$(SIM)' clean

lint:
	swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint lint --strict --config .swiftlint.yml

format:
	swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint --fix --config .swiftlint.yml
