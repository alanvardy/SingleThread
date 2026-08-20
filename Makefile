SIM ?= platform=iOS Simulator,name=iPhone 17
WATCH_SIM := generic/platform=watchOS Simulator
# Concrete watchOS Simulator used by watch UI tests (xcodebuild requires a
# concrete device to run XCTests). Name-only works when one standalone watch
# simulator exists; override with WATCH_TEST_SIM='platform=watchOS Simulator,id=…'
# on machines where the name is ambiguous.
WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)
MAC_SIM := platform=macOS
DERIVED_DATA := DerivedData
COVERAGE_RESULT := build/Coverage.xcresult
COVERAGE_UI_RESULT := build/Coverage.UI.xcresult
COVERAGE_ALL_RESULT := build/Coverage.All.xcresult
export SIM

.PHONY: build watch-build test ui-test simverify mac-build mac-test coverage coverage-ui coverage-all check clean lint format periphery watch-ui-test

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing

watch-build:
	xcodebuild -scheme SingleThreadWatch -destination '$(WATCH_SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build

mac-build:
	xcodebuild -scheme SingleThread -destination '$(MAC_SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build

mac-test:
	xcodebuild -scheme SingleThread -destination '$(MAC_SIM)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests

coverage:
	rm -rf '$(COVERAGE_RESULT)'
	xcodebuild -scheme SingleThread \
	  -destination '$(SIM)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  -enableCodeCoverage YES \
	  -only-testing:SingleThreadTests \
	  test \
	  -resultBundlePath '$(COVERAGE_RESULT)'
	@echo ""
	@echo "==> Coverage report"
	xcrun xccov view --report '$(COVERAGE_RESULT)'

coverage-ui:
	rm -rf '$(COVERAGE_UI_RESULT)'
	xcodebuild -scheme SingleThread \
	  -destination '$(SIM)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  -enableCodeCoverage YES \
	  -only-testing:SingleThreadUITests \
	  test \
	  -resultBundlePath '$(COVERAGE_UI_RESULT)'
	@echo ""
	@echo "==> UI coverage report"
	xcrun xccov view --report '$(COVERAGE_UI_RESULT)'

coverage-all:
	rm -rf '$(COVERAGE_ALL_RESULT)'
	xcodebuild -scheme SingleThread \
	  -destination '$(SIM)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  -enableCodeCoverage YES \
	  test \
	  -resultBundlePath '$(COVERAGE_ALL_RESULT)'
	@echo ""
	@echo "==> Full coverage report (unit + UI)"
	xcrun xccov view --report '$(COVERAGE_ALL_RESULT)'

test:
	./scripts/test.sh --unit-only

ui-test:
	./scripts/test.sh --ui-only

simverify:
	./scripts/simverify.sh

watch-ui-test:
	xcodebuild -scheme SingleThreadWatch \
	  -destination '$(WATCH_TEST_SIM)' \
	  -configuration Debug \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  test \
	  -only-testing:SingleThreadWatchUITests

check:
	./scripts/test.sh

clean:
	xcodebuild -scheme SingleThread -destination '$(SIM)' clean

lint:
	swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/ SingleThreadWatchUITests/
	swiftlint lint --strict

format:
	swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/ SingleThreadWatchUITests/
	swiftlint --fix

periphery:
	periphery scan --strict -- -destination "$(SIM)"
