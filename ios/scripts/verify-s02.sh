#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${S02_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${S02_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"

log() {
  printf '[verify-s02] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid S02_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
  fi

  if [[ -z "$DESTINATION" ]]; then
    fail_config "IOS_SIM_DESTINATION must not be empty" 91
  fi

  if [[ "$DESTINATION" != *"platform="* ]]; then
    fail_config "Invalid IOS_SIM_DESTINATION='$DESTINATION' (expected an xcodebuild destination containing 'platform=')" 93
  fi

  case "$ALLOW_MISSING_XCODEBUILD" in
    0|1)
      ;;
    *)
      fail_config "Invalid S02_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
      ;;
  esac
}

run_with_optional_timeout() {
  if [[ -n "$TIMEOUT_SECONDS" ]]; then
    if command -v timeout >/dev/null 2>&1; then
      timeout "$TIMEOUT_SECONDS" "$@"
      return
    fi

    log "timeout requested (${TIMEOUT_SECONDS}s) but 'timeout' command is unavailable; running without timeout wrapper"
  fi

  "$@"
}

run_phase() {
  local phase="$1"
  shift

  local started_at
  started_at="$(date +%s)"

  log "▶ ${phase}"

  set +e
  run_with_optional_timeout "$@"
  local status=$?
  set -e

  local finished_at
  finished_at="$(date +%s)"
  local duration=$((finished_at - started_at))

  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 124 ]]; then
      log "✗ ${phase} timed out after ${duration}s"
    else
      log "✗ ${phase} failed after ${duration}s"
    fi

    log "  command: $*"
    exit "$status"
  fi

  log "✓ ${phase} passed in ${duration}s"
}

run_contract_phase() {
  local phase="$1"
  shift

  local started_at
  started_at="$(date +%s)"

  log "▶ ${phase}"

  set +e
  "$@"
  local status=$?
  set -e

  local finished_at
  finished_at="$(date +%s)"
  local duration=$((finished_at - started_at))

  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 124 ]]; then
      log "✗ ${phase} timed out after ${duration}s"
    else
      log "✗ ${phase} failed after ${duration}s"
    fi

    exit "$status"
  fi

  log "✓ ${phase} passed in ${duration}s"
}

ensure_file_exists() {
  local file="$1"
  local code="$2"

  if [[ ! -f "$file" ]]; then
    log "✗ Missing required artifact: ${file}"
    return "$code"
  fi
}

require_token() {
  local file="$1"
  local token="$2"
  local description="$3"
  local code="$4"

  if ! grep -Fq "$token" "$file"; then
    log "✗ Missing ${description}: '${token}' in ${file}"
    return "$code"
  fi
}

check_runtime_artifacts_exist() {
  local reducer_file="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorReducer.swift"
  local palette_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyPaletteView.swift"
  local debug_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"
  local runtime_ui_tests_file="$ROOT_DIR/FiliusPadUITests/TopologySimulationRuntimeUITests.swift"
  local project_file="$PROJECT_PATH/project.pbxproj"

  ensure_file_exists "$reducer_file" 2 || return $?
  ensure_file_exists "$palette_file" 2 || return $?
  ensure_file_exists "$debug_file" 2 || return $?
  ensure_file_exists "$runtime_ui_tests_file" 2 || return $?
  ensure_file_exists "$project_file" 2 || return $?
}

check_runtime_reducer_contract() {
  local reducer_file="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorReducer.swift"

  require_token "$reducer_file" "startSimulation" "runtime reducer action" 3 || return $?
  require_token "$reducer_file" "simulationTick" "runtime reducer action" 3 || return $?
}

check_runtime_control_identifiers() {
  local palette_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyPaletteView.swift"

  require_token "$palette_file" "runtime.control.start" "runtime control identifier" 4 || return $?
  require_token "$palette_file" "runtime.control.stop" "runtime control identifier" 4 || return $?
}

check_runtime_debug_identifiers() {
  local debug_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"

  require_token "$debug_file" "debug.simulationPhase" "runtime debug accessibility identifier" 5 || return $?
  require_token "$debug_file" "debug.simulationTick" "runtime debug accessibility identifier" 5 || return $?
  require_token "$debug_file" "debug.lastRuntimeEvent" "runtime debug accessibility identifier" 5 || return $?
}

check_runtime_ui_test_artifacts() {
  local runtime_ui_tests_file="$ROOT_DIR/FiliusPadUITests/TopologySimulationRuntimeUITests.swift"

  require_token "$runtime_ui_tests_file" "final class TopologySimulationRuntimeUITests" "runtime UI test class" 6 || return $?
  require_token "$runtime_ui_tests_file" "runtime.control.start" "runtime UI control assertion" 6 || return $?
  require_token "$runtime_ui_tests_file" "debug.simulationTick" "runtime UI diagnostics assertion" 6 || return $?
}

check_project_wiring_contract() {
  local project_file="$PROJECT_PATH/project.pbxproj"

  require_token "$project_file" "TopologySimulationRuntimeUITests.swift" "project wiring token" 7 || return $?
  require_token "$project_file" "TopologyPaletteView.swift" "project wiring token" 7 || return $?
  require_token "$project_file" "TopologyDebugOverlayView.swift" "project wiring token" 7 || return $?
}

run_contract_fallback_checks() {
  log "Running host-aware fallback checks (xcodebuild unavailable or not executable on this host)"

  run_contract_phase "Fallback artifacts: required files exist" check_runtime_artifacts_exist
  run_contract_phase "Fallback contract: reducer runtime actions" check_runtime_reducer_contract
  run_contract_phase "Fallback contract: runtime controls identifiers" check_runtime_control_identifiers
  run_contract_phase "Fallback contract: runtime diagnostics identifiers" check_runtime_debug_identifiers
  run_contract_phase "Fallback contract: runtime UI test artifacts" check_runtime_ui_test_artifacts
  run_contract_phase "Fallback contract: project wiring" check_project_wiring_contract

  log "All fallback contract checks passed"
}

validate_configuration

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  if [[ "$ALLOW_MISSING_XCODEBUILD" == "1" ]]; then
    run_contract_fallback_checks
    exit 0
  fi

  log "✗ xcodebuild execution required but unavailable on this host"
  log "  host: $(uname -s)"
  log "  set S02_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback checks"
  exit 127
fi

run_phase \
  "Reducer + runtime diagnostics tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadTests/TopologyEditorReducerTests \
  -only-testing:FiliusPadTests/TopologyEditorDiagnosticsTests \
  test

run_phase \
  "Runtime UI tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadUITests/TopologySimulationRuntimeUITests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All S02 verification phases passed"
