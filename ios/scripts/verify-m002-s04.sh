#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT_SECONDS="${M002_S04_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${M002_S04_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"
PHASE="all"

S03_VERIFIER="$ROOT_DIR/scripts/verify-m002-s03.sh"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package-ipa.sh"
EXPECTED_IPA_PATH="$ROOT_DIR/build/ipa/FiliusPad.ipa"

log() {
  printf '[verify-m002-s04] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid M002_S04_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
  fi

  case "$ALLOW_MISSING_XCODEBUILD" in
    0|1)
      ;;
    *)
      fail_config "Invalid M002_S04_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 91
      ;;
  esac

  case "$PHASE" in
    all|regression|packaging)
      ;;
    *)
      fail_config "Invalid --phase '$PHASE' (expected: all|regression|packaging)" 92
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
  ensure_file_exists "$S03_VERIFIER" 2 || return $?
  ensure_file_exists "$PACKAGE_SCRIPT" 2 || return $?
}

check_regression_chain_tokens() {
  require_token "$S03_VERIFIER" "verify-m002-s02.sh" "S03→S02 chain verifier dependency" 3 || return $?
  require_token "$S03_VERIFIER" "S02 regression" "S03 regression phase attribution" 3 || return $?
}

check_packaging_tokens() {
  require_token "$PACKAGE_SCRIPT" "FILIUSPAD_UNSIGNED" "package unsigned mode env contract" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "FILIUSPAD_PACKAGE_DRY_RUN" "package dry-run env contract" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "FiliusPad.ipa" "package IPA artifact naming contract" 4 || return $?
}

host_supports_xcodebuild() {
  [[ "$(uname -s)" == "Darwin" ]] && command -v xcodebuild >/dev/null 2>&1
}

run_regression_phase() {
  run_phase "regression (S03→S02→S01 chain)" bash "$S03_VERIFIER"
}

run_packaging_phase() {
  local package_dry_run=0

  if ! host_supports_xcodebuild; then
    if [[ "$ALLOW_MISSING_XCODEBUILD" == "1" ]]; then
      package_dry_run=1
      log "Host lacks xcodebuild; packaging phase using FILIUSPAD_PACKAGE_DRY_RUN=1 fallback"
    else
      log "✗ xcodebuild execution required but unavailable for packaging phase"
      log "  host: $(uname -s)"
      log "  set M002_S04_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run non-mac packaging fallback"
      exit 127
    fi
  fi

  run_phase \
    "packaging (unsigned IPA continuity)" \
    env \
    FILIUSPAD_UNSIGNED=1 \
    FILIUSPAD_PACKAGE_DRY_RUN="$package_dry_run" \
    FILIUSPAD_IPA_OUTPUT_PATH="$EXPECTED_IPA_PATH" \
    bash "$PACKAGE_SCRIPT"

  if [[ "$package_dry_run" == "1" ]]; then
    log "✓ packaging fallback contract passed (artifact path contract: ${EXPECTED_IPA_PATH})"
    return
  fi

  if [[ ! -f "$EXPECTED_IPA_PATH" ]]; then
    log "✗ Expected IPA artifact not found at ${EXPECTED_IPA_PATH}"
    exit 41
  fi

  log "✓ unsigned IPA artifact present: ${EXPECTED_IPA_PATH}"
}

run_selected_phases() {
  case "$PHASE" in
    regression)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Regression-chain contract" check_regression_chain_tokens
      run_regression_phase
      ;;
    packaging)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Unsigned packaging contract" check_packaging_tokens
      run_packaging_phase
      ;;
    all)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Regression-chain contract" check_regression_chain_tokens
      run_contract_phase "Unsigned packaging contract" check_packaging_tokens
      run_regression_phase
      run_packaging_phase
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      [[ $# -lt 2 ]] && fail_config "--phase requires a value" 93
      PHASE="$2"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash ios/scripts/verify-m002-s04.sh [--phase all|regression|packaging]

Canonical host-aware verifier for M002/S04 closure.
Phases:
  regression  Run M002/S03 verifier chain (transitively S02→S01)
  packaging   Run unsigned IPA continuity gate via ios/scripts/package-ipa.sh
  all         Run regression then packaging phases (default)

Environment:
  M002_S04_VERIFY_TIMEOUT_SECONDS               Optional integer timeout applied per phase.
  M002_S04_VERIFY_ALLOW_MISSING_XCODEBUILD      1 (default) allows non-mac dry-run packaging fallback.
                                                0 enforces macOS + xcodebuild for packaging.
EOF
      exit 0
      ;;
    *)
      fail_config "Unknown argument: $1" 94
      ;;
  esac
  shift
done

validate_configuration
run_selected_phases

if [[ "$PHASE" != "all" ]]; then
  log "Selected phase '${PHASE}' passed"
  exit 0
fi

log "All M002/S04 verification phases passed"
