#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${S04_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${S04_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"

log() {
  printf '[verify-s04] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid S04_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
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
      fail_config "Invalid S04_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
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

  if ! grep -Fq -- "$token" "$file"; then
    log "✗ Missing ${description}: '${token}' in ${file}"
    return "$code"
  fi
}

check_required_artifacts_exist() {
  ensure_file_exists "$ROOT_DIR/FiliusPad/FiliusPadApp.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectEnvelope.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectSnapshot.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectStore.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyEditorView.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPadTests/TopologyProjectPersistenceTests.swift" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPadUITests/TopologyProjectPersistenceWorkflowUITests.swift" 2 || return $?
  ensure_file_exists "$PROJECT_PATH/project.pbxproj" 2 || return $?
  ensure_file_exists "$ROOT_DIR/scripts/verify-s03.sh" 2 || return $?
}

check_persistence_contract_tokens() {
  local envelope_file="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectEnvelope.swift"
  local snapshot_file="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectSnapshot.swift"
  local store_file="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectStore.swift"

  require_token "$envelope_file" "formatIdentifier" "persistence envelope format identifier" 3 || return $?
  require_token "$envelope_file" "schemaVersion" "persistence envelope schema field" 3 || return $?
  require_token "$envelope_file" "assertNoUnknownKeys" "strict unknown-key rejection" 3 || return $?

  require_token "$snapshot_file" "runtimeDeviceConfigurations" "durable runtime IP snapshot field" 3 || return $?
  require_token "$snapshot_file" "duplicateRuntimeDeviceConfiguration" "snapshot duplicate runtime config guard" 3 || return $?

  require_token "$store_file" "unsupportedSchemaVersion" "store schema gate" 3 || return $?
  require_token "$store_file" "unsupportedFormat" "store format gate" 3 || return $?
  require_token "$store_file" "fileWriteFailed" "store deterministic save error" 3 || return $?
}

check_app_lifecycle_contract_tokens() {
  local app_file="$ROOT_DIR/FiliusPad/FiliusPadApp.swift"

  require_token "$app_file" "restoreAutosaveSnapshotOnLaunch" "launch restore handler" 4 || return $?
  require_token "$app_file" "scheduleDebouncedAutosaveIfNeeded" "debounced autosave handler" 4 || return $?
  require_token "$app_file" "-inject-malformed-autosave" "malformed autosave launch argument hook" 4 || return $?
  require_token "$app_file" "FILIUSPAD_AUTOSAVE_FILE" "autosave path override env hook" 4 || return $?
}

check_diagnostics_and_alert_contract_tokens() {
  local editor_view_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyEditorView.swift"
  local debug_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"

  require_token "$editor_view_file" "persistence.error.alert" "persistence alert accessibility identifier" 5 || return $?
  require_token "$editor_view_file" "dismissPersistenceError" "persistence alert dismissal action" 5 || return $?

  require_token "$debug_file" "debug.persistenceRevision" "persistence debug revision identifier" 5 || return $?
  require_token "$debug_file" "debug.lastPersistenceSaveAt" "persistence debug save timestamp identifier" 5 || return $?
  require_token "$debug_file" "debug.lastPersistenceLoadAt" "persistence debug load timestamp identifier" 5 || return $?
  require_token "$debug_file" "debug.lastPersistenceError" "persistence debug error identifier" 5 || return $?
}

check_persistence_ui_test_contract_tokens() {
  local ui_test_file="$ROOT_DIR/FiliusPadUITests/TopologyProjectPersistenceWorkflowUITests.swift"

  require_token "$ui_test_file" "final class TopologyProjectPersistenceWorkflowUITests" "S04 persistence workflow UI test class" 6 || return $?
  require_token "$ui_test_file" "-inject-malformed-autosave" "S04 malformed autosave launch argument assertion" 6 || return $?
  require_token "$ui_test_file" "persistence.error.alert" "S04 persistence alert assertion token" 6 || return $?
  require_token "$ui_test_file" "debug.lastPersistenceLoadAt" "S04 persistence load diagnostics assertion token" 6 || return $?
  require_token "$ui_test_file" "FILIUSPAD_AUTOSAVE_FILE" "S04 autosave path override token" 6 || return $?
}

check_project_wiring_contract() {
  local project_file="$PROJECT_PATH/project.pbxproj"

  require_token "$project_file" "TopologyProjectPersistenceWorkflowUITests.swift" "S04 persistence workflow UI test project wiring token" 7 || return $?
  require_token "$project_file" "TopologyProjectPersistenceTests.swift" "S04 persistence unit test wiring token" 7 || return $?
}

run_contract_fallback_checks() {
  log "Running host-aware fallback checks (xcodebuild unavailable or not executable on this host)"

  run_contract_phase "Fallback artifacts: required files exist" check_required_artifacts_exist
  run_contract_phase "Fallback contract: persistence schema/store tokens" check_persistence_contract_tokens
  run_contract_phase "Fallback contract: launch restore + autosave lifecycle" check_app_lifecycle_contract_tokens
  run_contract_phase "Fallback contract: persistence diagnostics + alert identifiers" check_diagnostics_and_alert_contract_tokens
  run_contract_phase "Fallback contract: persistence workflow UI test tokens" check_persistence_ui_test_contract_tokens
  run_contract_phase "Fallback contract: project wiring" check_project_wiring_contract
  run_contract_phase "Fallback regression: S03 verifier" env S03_VERIFY_ALLOW_MISSING_XCODEBUILD=1 bash "$ROOT_DIR/scripts/verify-s03.sh"

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
  log "  set S04_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback checks"
  exit 127
fi

run_phase "S03 regression verifier" bash "$ROOT_DIR/scripts/verify-s03.sh"

run_phase \
  "Persistence unit + reducer diagnostics tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadTests/TopologyProjectPersistenceTests \
  -only-testing:FiliusPadTests/TopologyEditorReducerTests \
  -only-testing:FiliusPadTests/TopologyEditorDiagnosticsTests \
  test

run_phase \
  "Persistence workflow UI tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadUITests/TopologyProjectPersistenceWorkflowUITests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All S04 verification phases passed"
