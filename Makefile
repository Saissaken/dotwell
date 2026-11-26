.PHONY: build test app lint format clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh

lint:
	swift format lint --strict --recursive --parallel Package.swift Sources Tests

format:
	swift format --in-place --recursive --parallel Package.swift Sources Tests

clean:
	rm -rf .build build
