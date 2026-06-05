SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT_DIR := $(shell pwd)
APP_NAME := WorkflowGenerator

.PHONY: help build test run lint fmt clean verify

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Compile the macOS app via Swift Package Manager.
	swift build

test: ## Run unit tests.
	swift test

run: ## Build & launch the macOS app bundle.
	./script/build_and_run.sh run

verify: ## Build, launch, and confirm the app process is alive.
	./script/build_and_run.sh --verify

lint: ## Run swiftlint + swiftformat (lint mode).
	./script/lint.sh

fmt: ## Apply swiftformat (mutates files).
	swiftformat .

clean: ## Remove .build and dist.
	./script/clean.sh
