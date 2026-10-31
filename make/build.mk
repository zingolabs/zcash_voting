# ── Target directory ─────────────────────────────────────────────────────────
# Single-stack LRZ (upstream librustzcash 0.31): one crypto stack, one target
# directory.
#
# `test-fixtures` is a feature axis. Every target below that builds the default
# stack enables it, so `check` and `test` resolve to identical features and
# reuse each other's fingerprints.
TARGET_DIR := $(ROOT)/target

APP_PACKAGES  := -p zcash_voting -p zcash-voting-wallet-example
VCT_PACKAGES  := -p vote-commitment-tree -p vote-commitment-tree-client

# Profile from .config/nextest.toml. `agent` reports failures only; `ci`
# runs the whole suite without failing fast.
NEXTEST_PROFILE ?= agent

.PHONY: help check test test-lrz test-vct doc-test proofs msrv fmt clippy \
	recovery-conformance-check recovery-conformance recovery-conformance-crash \
	recovery-conformance-stalls recovery-conformance-fleet \
	stage-bench-check stage-bench-worker stage-bench stage-bench-unit

help: ## Show the canonical build and test targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

check: ## Type-check the default stack (fast inner loop)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo check $(APP_PACKAGES) --all-targets --features test-fixtures --locked

test: ## Run the test suite
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(APP_PACKAGES) \
		--features test-fixtures --locked

doc-test: ## Run documentation tests (nextest cannot run these)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo test $(APP_PACKAGES) --doc --features test-fixtures --locked

test-lrz: ## Deprecated alias for `test` (the stack is single-LRZ now)
	@$(MAKE) test

test-vct: ## Run the vote-commitment-tree crates
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(VCT_PACKAGES) \
		--all-targets --features vote-commitment-tree-client/cli --locked

proofs: ## Run the #[ignore] Halo2 proof tests (release only; slow)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) --release -p zcash_voting \
		--locked --run-ignored ignored-only

msrv: ## Check every package at the 1.97 MSRV
	@CARGO_TARGET_DIR="$(TARGET_DIR)/msrv" \
		cargo +1.97.0 check $(APP_PACKAGES) --all-targets --features test-fixtures --locked
	@CARGO_TARGET_DIR="$(TARGET_DIR)/msrv" \
		cargo +1.97.0 check $(VCT_PACKAGES) --all-targets \
		--features vote-commitment-tree-client/cli --locked

FMT_FLAGS ?= --check
fmt: ## Check formatting (FMT_FLAGS= applies formatting)
	@cargo fmt --all $(FMT_FLAGS)

clippy: ## Lint the default stack
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo clippy $(APP_PACKAGES) --all-targets --features test-fixtures --locked

# Staging crash-recovery conformance. Deliberately not in APP_PACKAGES: this
# package drives a real staging round over the network and kills its own child
# processes, so it must never join `check`, `test`, or CI's hermetic jobs. It
# shares the main target dir so it reuses the main build's artifacts.
RECOVERY_CONFORMANCE_PACKAGE = -p recovery-conformance
RECOVERY_CONFORMANCE_ARGS ?=

.PHONY: recovery-conformance-worker
recovery-conformance-worker: ## Build the exact worker used by live recovery matrices
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo build $(RECOVERY_CONFORMANCE_PACKAGE) --bin recovery-conformance-worker --locked

recovery-conformance-check: ## Type-check the staging crash-recovery suite
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo clippy $(RECOVERY_CONFORMANCE_PACKAGE) --all-targets --locked

recovery-conformance: recovery-conformance-worker ## Run every staging recovery matrix: crash, hang, fleet (network, very slow)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(RECOVERY_CONFORMANCE_PACKAGE) --locked $(RECOVERY_CONFORMANCE_ARGS)

# One axis at a time. The full run provisions roughly thirty-five rounds on
# `svote-1` and takes hours, so a change that can only affect one axis should
# pay for one axis. The hermetic tests run under every one of these.
recovery-conformance-crash: recovery-conformance-worker ## Run only the staging crash matrix (network, slow)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(RECOVERY_CONFORMANCE_PACKAGE) --locked $(RECOVERY_CONFORMANCE_ARGS) \
		-E 'not (binary(stall_conformance) or binary(helper_fleet_conformance))'

recovery-conformance-stalls: recovery-conformance-worker ## Run only the staging hang matrix (network, slow)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(RECOVERY_CONFORMANCE_PACKAGE) --locked $(RECOVERY_CONFORMANCE_ARGS) \
		-E 'not (binary(staging_conformance) or binary(stall_conformance))'

recovery-conformance-fleet: recovery-conformance-worker ## Run only the staging helper-fleet matrix (network, slow)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(RECOVERY_CONFORMANCE_PACKAGE) --locked $(RECOVERY_CONFORMANCE_ARGS) \
		-E 'not (binary(staging_conformance) or binary(stall_conformance))'

# Multi-proposal staging benchmark. Excluded from APP_PACKAGES for the same
# reason `recovery-conformance` is: it provisions real rounds on the staging
# vote chain and drives them over the network. It shares the main target dir
# so it reuses the main build's artifacts.
STAGE_BENCH_PACKAGE = -p stage-bench

# Arguments for `make stage-bench`, e.g.
#   STAGE_BENCH_ARGS="run --proposals 37 --helpers 2"
STAGE_BENCH_ARGS ?= run

stage-bench-check: ## Type-check and lint the staging benchmark
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo clippy $(STAGE_BENCH_PACKAGE) --all-targets --locked

stage-bench-worker: ## Build the release worker the benchmark CLI spawns
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo build --release $(STAGE_BENCH_PACKAGE) --bin stage-bench-worker --locked

# Release, always. A debug ZKP2 proof takes minutes where a release proof takes
# seconds, so a debug run's phase table measures the compiler rather than the
# SDK. The CLI records the profile in every run manifest for the same reason.
stage-bench: stage-bench-worker ## Run the staging benchmark (network, slow); see STAGE_BENCH_ARGS
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo run --release $(STAGE_BENCH_PACKAGE) --bin stage-bench --locked -- $(STAGE_BENCH_ARGS)

stage-bench-unit: ## Run hermetic benchmark tests (no staging)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(STAGE_BENCH_PACKAGE) --locked \
		--test ballot --test metrics --test run_directory --test share_schedule --test helper_fleet

.PHONY: recovery-conformance-unit
recovery-conformance-unit: ## Run hermetic crash-recovery harness tests (no staging)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" \
		cargo nextest run -P $(NEXTEST_PROFILE) $(RECOVERY_CONFORMANCE_PACKAGE) --locked $(RECOVERY_CONFORMANCE_ARGS) \
		--test stage_taxonomy --test stage_config --test target_chain \
		--test crash_log --test round_shape --test orchestration \
		--test fault_routes --test helper_fleet_plan --test stall_taxonomy \
		--test combined_recovery --test precompute --test setup_preservation \
		--test recrash_taxonomy --test sidecar_durability --test resume_progress

.PHONY: bench-bundle-pipelines
bench-bundle-pipelines: ## Compare serial and five real-proof pipelines with controlled peer delays
	@python3 "$(ROOT)/scripts/bench-bundle-pipelines.py"

.PHONY: bench-bundle-pipelines-sample
bench-bundle-pipelines-sample: ## Run one benchmark sample (normally invoked by the comparison harness)
	@CARGO_TARGET_DIR="$(TARGET_DIR)" cargo nextest run -P ci --release -p zcash_voting --locked --run-ignored ignored-only --success-output immediate -E 'test(bundle_pipeline_benchmark)'
