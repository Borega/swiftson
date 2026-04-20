#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${M004_S02_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${M004_S02_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"
PHASE="all"

STORE_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/Persistence/TopologyProjectStore.swift"
PERSISTENCE_TEST_FILE="$ROOT_DIR/FiliusPadTests/TopologyProjectPersistenceTests.swift"
FIXTURE_SIMPLE="$ROOT_DIR/FiliusPadTests/Fixtures/FLS/einfaches_rechnernetz_komplett.konfiguration.xml"
FIXTURE_COMPLEX="$ROOT_DIR/FiliusPadTests/Fixtures/FLS/zwei_rechnernetze_komplett.konfiguration.xml"
SAMPLE_SIMPLE_ARCHIVE="$ROOT_DIR/../javaversion/filius-master/beispiele/einfaches_rechnernetz_komplett.fls"
SAMPLE_COMPLEX_ARCHIVE="$ROOT_DIR/../javaversion/filius-master/beispiele/zwei_rechnernetze_komplett.fls"
M004_S01_VERIFIER="$ROOT_DIR/scripts/verify-m004-s01.sh"

log() {
  printf '[verify-m004-s02] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid M004_S02_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
  fi

  if [[ -z "$DESTINATION" ]] || [[ "$DESTINATION" != *"platform="* ]]; then
    fail_config "Invalid IOS_SIM_DESTINATION='$DESTINATION'" 91
  fi

  case "$ALLOW_MISSING_XCODEBUILD" in
    0|1)
      ;;
    *)
      fail_config "Invalid M004_S02_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
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
  ensure_file_exists "$STORE_FILE" 2 || return $?
  ensure_file_exists "$PERSISTENCE_TEST_FILE" 2 || return $?
  ensure_file_exists "$FIXTURE_SIMPLE" 2 || return $?
  ensure_file_exists "$FIXTURE_COMPLEX" 2 || return $?
  ensure_file_exists "$SAMPLE_SIMPLE_ARCHIVE" 2 || return $?
  ensure_file_exists "$SAMPLE_COMPLEX_ARCHIVE" 2 || return $?
  ensure_file_exists "$M004_S01_VERIFIER" 2 || return $?
}

check_fixture_structure_contract() {
  require_token "$FIXTURE_SIMPLE" "java.beans.XMLDecoder" "fixture XMLDecoder root marker" 4 || return $?
  require_token "$FIXTURE_SIMPLE" "filius.gui.netzwerksicht.GUIKnotenItem" "fixture GUI node item marker" 4 || return $?

  require_token "$FIXTURE_COMPLEX" "java.beans.XMLDecoder" "legacy fixture XMLDecoder root marker" 4 || return $?
  require_token "$FIXTURE_COMPLEX" "filius.hardware.knoten.Vermittlungsrechner" "legacy unsupported class attribution marker" 4 || return $?
}

check_compatibility_contract_tokens() {
  require_token "$STORE_FILE" "TopologyFLSImportReport" "FLS import report contract" 3 || return $?
  require_token "$STORE_FILE" "importedNodeCount" "imported count signal contract" 3 || return $?
  require_token "$STORE_FILE" "skippedNodeCount" "skipped count signal contract" 3 || return $?
  require_token "$STORE_FILE" "warnings: [String]" "deterministic warnings contract" 3 || return $?

  require_token "$STORE_FILE" "mapLegacyNodeType" "type-first compatibility mapping" 3 || return $?
  require_token "$STORE_FILE" "mapLegacyNodeClass" "legacy class fallback mapping" 3 || return $?
  require_token "$STORE_FILE" "Skipped unsupported FILIUS node type" "unsupported type attribution" 3 || return $?
  require_token "$STORE_FILE" "Skipped unsupported FILIUS node class" "unsupported class attribution" 3 || return $?
  require_token "$STORE_FILE" "malformedConfigurationXML" "malformed XML compatibility error" 3 || return $?
  require_token "$STORE_FILE" "unsupportedConfigurationStructure" "unsupported structure compatibility error" 3 || return $?

  require_token "$PERSISTENCE_TEST_FILE" "testSampleFLSWorkflowImportEditExportReimport" "sample workflow regression test" 3 || return $?
  require_token "$PERSISTENCE_TEST_FILE" "testSampleFLSImportReportsUnsupportedLegacyClassesWithAttribution" "legacy attribution regression test" 3 || return $?
  require_token "$PERSISTENCE_TEST_FILE" "report.importedNodeCount" "test inspection surface for imported count" 3 || return $?
  require_token "$PERSISTENCE_TEST_FILE" "report.skippedNodeCount" "test inspection surface for skipped count" 3 || return $?
  require_token "$PERSISTENCE_TEST_FILE" "report.warnings" "test inspection surface for warning attribution" 3 || return $?
}

run_selected_phases() {
  case "$PHASE" in
    contracts)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Fixture assumptions" check_fixture_structure_contract
      run_contract_phase "Compatibility contracts" check_compatibility_contract_tokens
      ;;
    regression)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_phase "M004/S01 regression chain" bash "$M004_S01_VERIFIER"
      ;;
    tests)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      ;;
    all)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Fixture assumptions" check_fixture_structure_contract
      run_contract_phase "Compatibility contracts" check_compatibility_contract_tokens
      run_phase "M004/S01 regression chain" bash "$M004_S01_VERIFIER"
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
Usage: bash ios/scripts/verify-m004-s02.sh [--phase all|contracts|regression|tests]

Host-aware closure verifier for M004/S02 Java .fls compatibility workflow + legacy attribution.
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
run_selected_phases

if [[ "$PHASE" == "contracts" || "$PHASE" == "regression" ]]; then
  log "Selected phase '${PHASE}' passed"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  if [[ "$ALLOW_MISSING_XCODEBUILD" == "1" ]]; then
    log "Host lacks xcodebuild; contracts/regression complete"
    exit 0
  fi

  log "✗ xcodebuild execution required but unavailable on this host"
  exit 127
fi

run_phase \
  "TopologyProjectPersistenceTests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadTests/TopologyProjectPersistenceTests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All M004/S02 verification phases passed"