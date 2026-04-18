#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${M002_S03_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${M002_S03_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"
PHASE="all"

GRAPH_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/Model/TopologyGraph.swift"
STATE_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorState.swift"
REDUCER_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/State/TopologyEditorReducer.swift"
DEBUG_OVERLAY_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"
RUNTIME_SHEET_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyRuntimeDeviceSheet.swift"
REDUCER_TEST_FILE="$ROOT_DIR/FiliusPadTests/TopologyEditorReducerTests.swift"
DIAGNOSTICS_TEST_FILE="$ROOT_DIR/FiliusPadTests/TopologyEditorDiagnosticsTests.swift"
PING_UI_TEST_FILE="$ROOT_DIR/FiliusPadUITests/TopologyRuntimePingWorkflowUITests.swift"
INTEGRATED_UI_TEST_FILE="$ROOT_DIR/FiliusPadUITests/TopologyIntegratedAcceptanceUITests.swift"
S02_VERIFIER="$ROOT_DIR/scripts/verify-m002-s02.sh"

log() {
  printf '[verify-m002-s03] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid M002_S03_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
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
      fail_config "Invalid M002_S03_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
      ;;
  esac

  case "$PHASE" in
    all|model|runtime|tests)
      ;;
    *)
      fail_config "Invalid --phase '$PHASE' (expected: all|model|runtime|tests)" 94
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
  ensure_file_exists "$GRAPH_FILE" 2 || return $?
  ensure_file_exists "$STATE_FILE" 2 || return $?
  ensure_file_exists "$REDUCER_FILE" 2 || return $?
  ensure_file_exists "$DEBUG_OVERLAY_FILE" 2 || return $?
  ensure_file_exists "$RUNTIME_SHEET_FILE" 2 || return $?
  ensure_file_exists "$REDUCER_TEST_FILE" 2 || return $?
  ensure_file_exists "$DIAGNOSTICS_TEST_FILE" 2 || return $?
  ensure_file_exists "$PING_UI_TEST_FILE" 2 || return $?
  ensure_file_exists "$INTEGRATED_UI_TEST_FILE" 2 || return $?
  ensure_file_exists "$S02_VERIFIER" 2 || return $?
}

check_model_contract_tokens() {
  require_token "$GRAPH_FILE" "shortestPathHopCount" "shortest-path hop metric helper" 3 || return $?
  require_token "$GRAPH_FILE" "shortestPathNodeIDs" "shortest-path route helper" 3 || return $?
  require_token "$GRAPH_FILE" "deterministicAdjacencyMap" "deterministic adjacency expansion" 3 || return $?
  require_token "$REDUCER_TEST_FILE" "testShortestPathNodeIDsPrefersLexicographicallyStableRouteWhenHopsTie" "deterministic tie-route reducer coverage" 3 || return $?
}

check_runtime_contract_tokens() {
  require_token "$STATE_FILE" "traceSucceeded" "trace runtime event code" 4 || return $?
  require_token "$STATE_FILE" "traceRejectedTopologyUnreachable" "trace unreachable runtime event code" 4 || return $?
  require_token "$STATE_FILE" "runtimeCommandRejectedUnsupported" "unsupported runtime command event code" 4 || return $?

  require_token "$REDUCER_FILE" "parseRuntimeCommand" "runtime command parser" 4 || return $?
  require_token "$REDUCER_FILE" "executeTraceCommand" "trace command execution path" 4 || return $?
  require_token "$REDUCER_FILE" "routeDetail(" "path-aware route metadata encoding" 4 || return $?
  require_token "$REDUCER_FILE" "latencyMs=" "latency diagnostics token" 4 || return $?
  require_token "$REDUCER_FILE" "hops=" "hop diagnostics token" 4 || return $?

  require_token "$RUNTIME_SHEET_FILE" "ping|trace <target-ipv4>" "runtime command extension hint" 4 || return $?
  require_token "$DEBUG_OVERLAY_FILE" "debug.lastRuntimeRoute" "path-aware debug overlay identifier" 4 || return $?
}

check_tests_contract_tokens() {
  require_token "$REDUCER_TEST_FILE" "testExecuteTraceSuccessReportsDeterministicPathAndHopMetadata" "trace success reducer test coverage" 5 || return $?
  require_token "$REDUCER_TEST_FILE" "testExecuteTraceRejectsUnsupportedCommandVerbExplicitly" "unsupported command reducer test coverage" 5 || return $?
  require_token "$DIAGNOSTICS_TEST_FILE" "testTraceSuccessPublishesPathAwareRuntimeDiagnostics" "trace diagnostics coverage" 5 || return $?
  require_token "$DIAGNOSTICS_TEST_FILE" "testUnsupportedRuntimeCommandUsesExplicitAttributableFault" "unsupported diagnostics coverage" 5 || return $?
  require_token "$PING_UI_TEST_FILE" "runtime.device.sheet" "runtime UI workflow contract" 5 || return $?
}

run_selected_contract_phases() {
  case "$PHASE" in
    model)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Model path-metrics contract" check_model_contract_tokens
      ;;
    runtime)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Runtime command extension contract" check_runtime_contract_tokens
      ;;
    tests)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Runtime-depth test contract" check_tests_contract_tokens
      ;;
    all)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Model path-metrics contract" check_model_contract_tokens
      run_contract_phase "Runtime command extension contract" check_runtime_contract_tokens
      run_contract_phase "Runtime-depth test contract" check_tests_contract_tokens
      run_contract_phase "S02 regression" bash "$S02_VERIFIER"
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
Usage: bash ios/scripts/verify-m002-s03.sh [--phase all|model|runtime|tests]

Host-aware verifier for M002/S03 runtime-depth and path-aware diagnostics work.
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
  log "  set M002_S03_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback checks"
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
  "Runtime ping + integration UI tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadUITests/TopologyRuntimePingWorkflowUITests \
  -only-testing:FiliusPadUITests/TopologyIntegratedAcceptanceUITests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All M002/S03 verification phases passed"
