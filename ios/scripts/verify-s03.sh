#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${S03_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${S03_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"

log() {
  printf '[verify-s03] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid S03_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
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
      fail_config "Invalid S03_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
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
    log "✗ ${phase} failed after ${duration}s"
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

  if [[ -z "$token" ]]; then
    log "✗ Malformed empty token provided for ${description}"
    return "$code"
  fi

  if ! grep -Fq "$token" "$file"; then
    log "✗ Missing ${description}: '${token}' in ${file}"
    return "$code"
  fi
}

check_required_artifacts_exist() {
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyEditorView.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyRuntimeDeviceSheet.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorReducer.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPadUITests/TopologyRuntimePingWorkflowUITests.swift" 2 || return $?
  ensure_file_exists "$PROJECT_PATH/project.pbxproj" 2 || return $?
  ensure_file_exists "$ROOT_DIR/scripts/verify-s02.sh" 2 || return $?
}

check_runtime_reducer_contract() {
  local reducer_file="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorReducer.swift"

  require_token "$reducer_file" "saveRuntimeDeviceIP" "runtime reducer action" 3 || return $?
  require_token "$reducer_file" "executePing" "runtime reducer action" 3 || return $?
  require_token "$reducer_file" "pingRejectedUnknownTarget" "runtime reducer ping rejection" 3 || return $?
  require_token "$reducer_file" "pingSucceeded" "runtime reducer ping success" 3 || return $?
}

check_runtime_sheet_contract() {
  local editor_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyEditorView.swift"
  local sheet_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyRuntimeDeviceSheet.swift"

  require_token "$editor_file" ".sheet(item:" "runtime sheet binding" 4 || return $?
  require_token "$sheet_file" "runtime.device.sheet" "runtime sheet accessibility identifier" 4 || return $?
  require_token "$sheet_file" "runtime.device.ip" "runtime IP input identifier" 4 || return $?
  require_token "$sheet_file" "runtime.device.command" "runtime command input identifier" 4 || return $?
}

check_runtime_diagnostics_identifiers() {
  local debug_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"

  require_token "$debug_file" "debug.lastPingEvent" "runtime ping diagnostics identifier" 5 || return $?
  require_token "$debug_file" "debug.lastPingFault" "runtime ping diagnostics identifier" 5 || return $?
  require_token "$debug_file" "debug.openedRuntimeDevice" "runtime opened-device diagnostics identifier" 5 || return $?
}

check_runtime_ui_test_contract() {
  local ui_test_file="$ROOT_DIR/FiliusPadUITests/TopologyRuntimePingWorkflowUITests.swift"

  require_token "$ui_test_file" "final class TopologyRuntimePingWorkflowUITests" "S03 runtime ping UI test class" 6 || return $?
  require_token "$ui_test_file" "pingSucceeded" "S03 ping success assertion token" 6 || return $?
  require_token "$ui_test_file" "pingRejectedUnknownTarget" "S03 ping failure assertion token" 6 || return $?
  require_token "$ui_test_file" "runtime.device.sheet" "S03 runtime sheet assertion token" 6 || return $?
}

check_project_wiring_contract() {
  local project_file="$PROJECT_PATH/project.pbxproj"

  require_token "$project_file" "TopologyRuntimePingWorkflowUITests.swift" "S03 project wiring token" 7 || return $?
  require_token "$project_file" "TopologySimulationRuntimeUITests.swift" "S02 runtime UI regression wiring token" 7 || return $?
  require_token "$project_file" "TopologyRuntimeDeviceSheet.swift" "runtime sheet wiring token" 7 || return $?
}

run_contract_fallback_checks() {
  log "Running host-aware fallback checks (xcodebuild unavailable or not executable on this host)"

  run_contract_phase "Fallback artifacts: required files exist" check_required_artifacts_exist
  run_contract_phase "Fallback contract: reducer runtime ping tokens" check_runtime_reducer_contract
  run_contract_phase "Fallback contract: runtime sheet identifiers" check_runtime_sheet_contract
  run_contract_phase "Fallback contract: runtime diagnostics identifiers" check_runtime_diagnostics_identifiers
  run_contract_phase "Fallback contract: runtime UI test tokens" check_runtime_ui_test_contract
  run_contract_phase "Fallback contract: project wiring" check_project_wiring_contract
  run_contract_phase "Fallback regression: S02 verifier" env S02_VERIFY_ALLOW_MISSING_XCODEBUILD=1 bash "$ROOT_DIR/scripts/verify-s02.sh"

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
  log "  set S03_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback checks"
  exit 127
fi

run_phase "S02 regression verifier" bash "$ROOT_DIR/scripts/verify-s02.sh"

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
  "Runtime ping workflow UI tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadUITests/TopologyRuntimePingWorkflowUITests \
  -only-testing:FiliusPadUITests/TopologySimulationRuntimeUITests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All S03 verification phases passed"
