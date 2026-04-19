#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${M002_S02_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${M002_S02_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"
PHASE="all"

ENVELOPE_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectEnvelope.swift"
SNAPSHOT_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectSnapshot.swift"
STORE_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectStore.swift"
APP_FILE="$ROOT_DIR/FiliusPad/FiliusPadApp.swift"
EDITOR_VIEW_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyEditorView.swift"
DEBUG_OVERLAY_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"
STATE_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorState.swift"
PERSISTENCE_TEST_FILE="$ROOT_DIR/FiliusPadTests/TopologyProjectPersistenceTests.swift"
PERSISTENCE_UI_TEST_FILE="$ROOT_DIR/FiliusPadUITests/TopologyProjectPersistenceWorkflowUITests.swift"
S01_VERIFIER="$ROOT_DIR/scripts/verify-m002-s01.sh"

log() {
  printf '[verify-m002-s02] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid M002_S02_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
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
      fail_config "Invalid M002_S02_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
      ;;
  esac

  case "$PHASE" in
    all|persistence|recovery-ui|observability)
      ;;
    *)
      fail_config "Invalid --phase '$PHASE' (expected: all|persistence|recovery-ui|observability)" 94
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

emit_recovery_workflow_failure_diagnostics() {
  local result_bundle="$1"

  if [[ ! -d "$result_bundle" ]]; then
    log "recovery workflow diagnostics: result bundle missing at $result_bundle"
    return
  fi

  if ! command -v xcrun >/dev/null 2>&1; then
    log "recovery workflow diagnostics: xcrun unavailable; skipping xcresult extraction"
    return
  fi

  local json_dump
  json_dump="$(mktemp)"

  if ! xcrun xcresulttool get --legacy --path "$result_bundle" --format json >"$json_dump" 2>/dev/null; then
    if ! xcrun xcresulttool get --path "$result_bundle" --format json >"$json_dump" 2>/dev/null; then
      log "recovery workflow diagnostics: xcresulttool could not decode $result_bundle"
      rm -f "$json_dump"
      return
    fi
  fi

  local python_cmd=""
  if command -v python3 >/dev/null 2>&1; then
    python_cmd="python3"
  elif command -v python >/dev/null 2>&1; then
    python_cmd="python"
  else
    log "recovery workflow diagnostics: python unavailable; falling back to grep"
    grep -E "TopologyProjectPersistenceWorkflowUITests|failed|failure|assert|Expected|Setup failure|Timed out|persistence|recovery" "$json_dump" | head -n 160 || true
    rm -f "$json_dump"
    return
  fi

  log "recovery workflow diagnostics (xcresult filtered)"
  "$python_cmd" - "$json_dump" <<'PY'
import json
import re
import sys
from collections import OrderedDict

path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='replace') as f:
    data = json.load(f)

patterns = [
    re.compile(r'TopologyProjectPersistenceWorkflowUITests', re.I),
    re.compile(r'failed', re.I),
    re.compile(r'failure', re.I),
    re.compile(r'Setup failure', re.I),
    re.compile(r'XCTAssert', re.I),
    re.compile(r'Expected', re.I),
    re.compile(r'Timed out', re.I),
    re.compile(r'persistence', re.I),
    re.compile(r'recovery', re.I),
]

lines = []

def walk(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, str):
                candidate = f"{k}: {v}"
                if any(p.search(candidate) for p in patterns):
                    lines.append(candidate)
            else:
                walk(v)
    elif isinstance(node, list):
        for item in node:
            walk(item)

walk(data)

unique = list(OrderedDict.fromkeys(lines))
for entry in unique[:160]:
    print(entry)

if not unique:
    print('no matched failure diagnostics found in xcresult payload')
PY

  rm -f "$json_dump"
}

run_recovery_workflow_ui_phase() {
  local result_bundle="$ROOT_DIR/build/m002-s02-recovery-ui.xcresult"
  rm -rf "$result_bundle"

  local started_at
  started_at="$(date +%s)"

  log "▶ Recovery workflow UI tests"

  set +e
  run_with_optional_timeout \
    xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -resultBundlePath "$result_bundle" \
    -only-testing:FiliusPadUITests/TopologyProjectPersistenceWorkflowUITests \
    test
  local status=$?
  set -e

  local finished_at
  finished_at="$(date +%s)"
  local duration=$((finished_at - started_at))

  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 124 ]]; then
      log "✗ Recovery workflow UI tests timed out after ${duration}s"
    else
      log "✗ Recovery workflow UI tests failed after ${duration}s"
    fi

    log "  command: xcodebuild -project $PROJECT_PATH -scheme $SCHEME -destination $DESTINATION -resultBundlePath $result_bundle -only-testing:FiliusPadUITests/TopologyProjectPersistenceWorkflowUITests test"
    emit_recovery_workflow_failure_diagnostics "$result_bundle"
    exit "$status"
  fi

  log "✓ Recovery workflow UI tests passed in ${duration}s"
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
  ensure_file_exists "$ENVELOPE_FILE" 2 || return $?
  ensure_file_exists "$SNAPSHOT_FILE" 2 || return $?
  ensure_file_exists "$STORE_FILE" 2 || return $?
  ensure_file_exists "$APP_FILE" 2 || return $?
  ensure_file_exists "$EDITOR_VIEW_FILE" 2 || return $?
  ensure_file_exists "$DEBUG_OVERLAY_FILE" 2 || return $?
  ensure_file_exists "$STATE_FILE" 2 || return $?
  ensure_file_exists "$PERSISTENCE_TEST_FILE" 2 || return $?
  ensure_file_exists "$PERSISTENCE_UI_TEST_FILE" 2 || return $?
  ensure_file_exists "$S01_VERIFIER" 2 || return $?
}

check_persistence_recovery_contract_tokens() {
  require_token "$ENVELOPE_FILE" "TopologyProjectSaveReason" "envelope save-reason enum" 3 || return $?
  require_token "$ENVELOPE_FILE" "saveReason" "envelope saveReason field" 3 || return $?
  require_token "$ENVELOPE_FILE" "decodeIfPresent(TopologyProjectSaveReason.self" "envelope legacy-compatible saveReason decode" 3 || return $?

  require_token "$SNAPSHOT_FILE" "persistenceRevision" "snapshot persistence revision field" 3 || return $?
  require_token "$SNAPSHOT_FILE" "decodeIfPresent(UInt64.self, forKey: .persistenceRevision) ?? 0" "legacy-compatible persistenceRevision decode" 3 || return $?
  require_token "$SNAPSHOT_FILE" "state.lastPersistedRevision = persistenceRevision" "restore persistence revision attribution" 3 || return $?

  require_token "$STORE_FILE" "saveReason: TopologyProjectSaveReason" "store save API recovery metadata parameter" 3 || return $?
  require_token "$PERSISTENCE_TEST_FILE" "testLoadLegacyPayloadWithoutRecoveryMetadataDefaultsSafely" "legacy metadata compatibility test" 3 || return $?
}

check_recovery_ui_contract_tokens() {
  require_token "$APP_FILE" "restoreAutosaveSnapshotOnLaunch" "launch restore flow hook" 4 || return $?
  require_token "$APP_FILE" "recordPersistenceLoad" "restore persistence attribution" 4 || return $?
  require_token "$APP_FILE" "recordRecoverySuccess" "successful recovery state recording" 4 || return $?
  require_token "$EDITOR_VIEW_FILE" "recovery.notice.banner" "recovery banner identifier" 4 || return $?
  require_token "$EDITOR_VIEW_FILE" "recovery.notice.dismiss" "recovery banner dismiss control identifier" 4 || return $?
  require_token "$EDITOR_VIEW_FILE" "dismissRecoveryNotice" "recovery notice dismiss reducer action" 4 || return $?
  require_token "$EDITOR_VIEW_FILE" "persistence.error.alert" "persistence/recovery alert surface" 4 || return $?
  require_token "$PERSISTENCE_UI_TEST_FILE" "recovery.notice.banner" "recovery banner UI-test assertion token" 4 || return $?
  require_token "$PERSISTENCE_UI_TEST_FILE" "recovery.notice.dismiss" "recovery dismiss UI-test assertion token" 4 || return $?
}

check_observability_contract_tokens() {
  require_token "$STATE_FILE" "lastPersistenceLoadAt" "state load-at diagnostics field" 5 || return $?
  require_token "$STATE_FILE" "lastPersistedRevision" "state persisted-revision diagnostics field" 5 || return $?
  require_token "$STATE_FILE" "lastRecoveryMessage" "state recovery message diagnostics field" 5 || return $?
  require_token "$STATE_FILE" "lastRecoverySucceeded" "state recovery success diagnostics field" 5 || return $?
  require_token "$STATE_FILE" "isRecoveryNoticeVisible" "state recovery visibility diagnostics field" 5 || return $?
  require_token "$DEBUG_OVERLAY_FILE" "debug.lastPersistenceLoadAt" "debug load-at diagnostics identifier" 5 || return $?
  require_token "$DEBUG_OVERLAY_FILE" "debug.persistenceRevision" "debug persistence revision identifier" 5 || return $?
  require_token "$DEBUG_OVERLAY_FILE" "debug.lastRecoveryState" "debug recovery state identifier" 5 || return $?
  require_token "$DEBUG_OVERLAY_FILE" "debug.lastRecoveryAt" "debug recovery timestamp identifier" 5 || return $?
  require_token "$ROOT_DIR/FiliusPadTests/TopologyEditorDiagnosticsTests.swift" "testRecoverySuccessMetadataIsInspectableAndDismissible" "recovery success diagnostics test coverage" 5 || return $?
  require_token "$ROOT_DIR/FiliusPadTests/TopologyEditorDiagnosticsTests.swift" "testRecoveryFailureMetadataIsInspectableAndDismissible" "recovery failure diagnostics test coverage" 5 || return $?
}

run_selected_contract_phases() {
  case "$PHASE" in
    persistence)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Persistence recovery contract" check_persistence_recovery_contract_tokens
      ;;
    recovery-ui)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Recovery UI contract" check_recovery_ui_contract_tokens
      ;;
    observability)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Recovery observability contract" check_observability_contract_tokens
      ;;
    all)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Persistence recovery contract" check_persistence_recovery_contract_tokens
      run_contract_phase "Recovery UI contract" check_recovery_ui_contract_tokens
      run_contract_phase "Recovery observability contract" check_observability_contract_tokens
      run_contract_phase "S01 regression" bash "$S01_VERIFIER"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      [[ $# -lt 2 ]] && fail_config "--phase requires a value" 95
      PHASE="$2"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash ios/scripts/verify-m002-s02.sh [--phase all|persistence|recovery-ui|observability]

Host-aware verifier for M002/S02 recovery work.
EOF
      exit 0
      ;;
    *)
      fail_config "Unknown argument: $1" 96
      ;;
  esac
  shift
done

validate_configuration
run_selected_contract_phases

if [[ "$PHASE" != "all" ]]; then
  log "Selected phase '${PHASE}' passed"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  if [[ "$ALLOW_MISSING_XCODEBUILD" == "1" ]]; then
    log "Host lacks xcodebuild; contract phases complete"
    exit 0
  fi

  log "✗ xcodebuild execution required but unavailable on this host"
  log "  host: $(uname -s)"
  log "  set M002_S02_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback checks"
  exit 127
fi

run_phase \
  "Persistence and diagnostics tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadTests/TopologyProjectPersistenceTests \
  -only-testing:FiliusPadTests/TopologyEditorDiagnosticsTests \
  test

run_recovery_workflow_ui_phase

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All M002/S02 verification phases passed"
