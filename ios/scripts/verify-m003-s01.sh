#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${M003_S01_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${M003_S01_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"
PHASE="all"

REDUCER_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorReducer.swift"
STATE_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorState.swift"
SHEET_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyRuntimeDeviceSheet.swift"
OVERLAY_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"
PERSISTENCE_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectSnapshot.swift"
REDUCER_TEST_FILE="$ROOT_DIR/FiliusPadTests/TopologyEditorReducerTests.swift"
DIAGNOSTICS_TEST_FILE="$ROOT_DIR/FiliusPadTests/TopologyEditorDiagnosticsTests.swift"
PERSISTENCE_TEST_FILE="$ROOT_DIR/FiliusPadTests/TopologyProjectPersistenceTests.swift"
M002_VERIFIER="$ROOT_DIR/scripts/verify-m002-s04.sh"

log() {
  printf '[verify-m003-s01] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid M003_S01_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
  fi

  if [[ -z "$DESTINATION" ]] || [[ "$DESTINATION" != *"platform="* ]]; then
    fail_config "Invalid IOS_SIM_DESTINATION='$DESTINATION'" 91
  fi

  case "$ALLOW_MISSING_XCODEBUILD" in
    0|1)
      ;;
    *)
      fail_config "Invalid M003_S01_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
      ;;
  esac

  case "$PHASE" in
    all|contracts|regression|tests)
      ;;
    *)
      fail_config "Invalid --phase '$PHASE' (expected: all|contracts|regression|tests)" 93
      ;;
  esac
}

run_with_optional_timeout() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECONDS" "$@"
    return
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
    log "✗ ${phase} failed after ${duration}s"
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

  if ! grep -Fq -- "$token" "$file"; then
    log "✗ Missing ${description}: '${token}' in ${file}"
    return "$code"
  fi
}

check_required_artifacts_exist() {
  ensure_file_exists "$REDUCER_FILE" 2 || return $?
  ensure_file_exists "$STATE_FILE" 2 || return $?
  ensure_file_exists "$SHEET_FILE" 2 || return $?
  ensure_file_exists "$OVERLAY_FILE" 2 || return $?
  ensure_file_exists "$PERSISTENCE_FILE" 2 || return $?
  ensure_file_exists "$REDUCER_TEST_FILE" 2 || return $?
  ensure_file_exists "$DIAGNOSTICS_TEST_FILE" 2 || return $?
  ensure_file_exists "$PERSISTENCE_TEST_FILE" 2 || return $?
  ensure_file_exists "$M002_VERIFIER" 2 || return $?
}

check_service_contract_tokens() {
  require_token "$STATE_FILE" "dhcpLeaseAssigned" "DHCP runtime event code" 3 || return $?
  require_token "$STATE_FILE" "dnsResolveSucceeded" "DNS resolve runtime event code" 3 || return $?
  require_token "$STATE_FILE" "runtimeDNSRecordsByHostname" "DNS runtime state map" 3 || return $?

  require_token "$REDUCER_FILE" "dhcp lease <ipv4> <subnet-mask>" "DHCP command parser contract" 3 || return $?
  require_token "$REDUCER_FILE" "dns add <hostname> <target-ipv4>" "DNS add parser contract" 3 || return $?
  require_token "$REDUCER_FILE" "dns resolve <hostname>" "DNS resolve parser contract" 3 || return $?
  require_token "$REDUCER_FILE" "executeDHCPLeaseCommand" "DHCP execution path" 3 || return $?
  require_token "$REDUCER_FILE" "executeDNSRegisterCommand" "DNS register execution path" 3 || return $?
  require_token "$REDUCER_FILE" "executeDNSResolveCommand" "DNS resolve execution path" 3 || return $?

  require_token "$SHEET_FILE" "dhcp lease <ipv4> <subnet-mask>" "runtime sheet DHCP help" 3 || return $?
  require_token "$SHEET_FILE" "dns resolve <hostname>" "runtime sheet DNS help" 3 || return $?

  require_token "$OVERLAY_FILE" "debug.runtimeDHCPLeaseCount" "DHCP diagnostics identifier" 3 || return $?
  require_token "$OVERLAY_FILE" "debug.runtimeDNSRecordCount" "DNS diagnostics identifier" 3 || return $?
}

check_persistence_contract_tokens() {
  require_token "$PERSISTENCE_FILE" "runtimeDNSRecords" "snapshot DNS records field" 4 || return $?
  require_token "$PERSISTENCE_FILE" "TopologyRuntimeDNSRecordSnapshot" "snapshot DNS record type" 4 || return $?
  require_token "$PERSISTENCE_TEST_FILE" "runtimeDNSRecordsByHostname" "persistence DNS round-trip assertion" 4 || return $?
}

run_selected_contract_phases() {
  case "$PHASE" in
    contracts)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Service command contract" check_service_contract_tokens
      run_contract_phase "Persistence contract" check_persistence_contract_tokens
      ;;
    regression)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_phase "M002 regression" bash "$M002_VERIFIER"
      ;;
    tests)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      ;;
    all)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Service command contract" check_service_contract_tokens
      run_contract_phase "Persistence contract" check_persistence_contract_tokens
      run_phase "M002 regression" bash "$M002_VERIFIER"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      [[ $# -lt 2 ]] && fail_config "--phase requires a value" 94
      PHASE="$2"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash ios/scripts/verify-m003-s01.sh [--phase all|contracts|regression|tests]

Host-aware verifier for M003/S01 service parity core (DHCP + DNS runtime command surface).
EOF
      exit 0
      ;;
    *)
      fail_config "Unknown argument: $1" 95
      ;;
  esac
  shift
done

validate_configuration
run_selected_contract_phases

if [[ "$PHASE" == "contracts" || "$PHASE" == "regression" ]]; then
  log "Selected phase '${PHASE}' passed"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  if [[ "$ALLOW_MISSING_XCODEBUILD" == "1" ]]; then
    log "Host lacks xcodebuild; contract phases complete"
    exit 0
  fi

  log "✗ xcodebuild execution required but unavailable on this host"
  exit 127
fi

run_phase \
  "Reducer + diagnostics + persistence tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadTests/TopologyEditorReducerTests \
  -only-testing:FiliusPadTests/TopologyEditorDiagnosticsTests \
  -only-testing:FiliusPadTests/TopologyProjectPersistenceTests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All M003/S01 verification phases passed"
