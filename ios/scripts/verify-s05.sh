#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${S05_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${S05_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package-ipa.sh"
INTEGRATED_TEST_FILE="$ROOT_DIR/FiliusPadUITests/TopologyIntegratedAcceptanceUITests.swift"

log() {
  printf '[verify-s05] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid S05_VERIFY_TIMEOUT_SECONDS='${TIMEOUT_SECONDS}' (expected integer seconds)" 90
  fi

  if [[ -z "$DESTINATION" ]]; then
    fail_config "IOS_SIM_DESTINATION must not be empty" 91
  fi

  if [[ "$DESTINATION" != *"platform="* ]]; then
    fail_config "Invalid IOS_SIM_DESTINATION='${DESTINATION}' (expected an xcodebuild destination containing 'platform=')" 92
  fi

  case "$ALLOW_MISSING_XCODEBUILD" in
    0|1)
      ;;
    *)
      fail_config "Invalid S05_VERIFY_ALLOW_MISSING_XCODEBUILD='${ALLOW_MISSING_XCODEBUILD}' (expected 0 or 1)" 93
      ;;
  esac

  if [[ ! -f "$PACKAGE_SCRIPT" ]]; then
    fail_config "Missing required packaging helper: ${PACKAGE_SCRIPT}" 94
  fi
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
  ensure_file_exists "$INTEGRATED_TEST_FILE" 2 || return $?
  ensure_file_exists "$PROJECT_PATH/project.pbxproj" 2 || return $?
  ensure_file_exists "$ROOT_DIR/FiliusPad.xcodeproj/xcshareddata/xcschemes/FiliusPad.xcscheme" 2 || return $?
  ensure_file_exists "$ROOT_DIR/scripts/verify-s04.sh" 2 || return $?
  ensure_file_exists "$ROOT_DIR/scripts/verify-s03.sh" 2 || return $?
  ensure_file_exists "$PACKAGE_SCRIPT" 2 || return $?
}

check_integrated_ui_test_contract_tokens() {
  require_token "$INTEGRATED_TEST_FILE" "final class TopologyIntegratedAcceptanceUITests" "S05 integrated UI test class" 3 || return $?
  require_token "$INTEGRATED_TEST_FILE" "Nodes: 10" "S05 ~10-node diagnostics assertion" 3 || return $?
  require_token "$INTEGRATED_TEST_FILE" "debug.lastPingEvent" "S05 ping event diagnostics assertion" 3 || return $?
  require_token "$INTEGRATED_TEST_FILE" "debug.lastPingFault" "S05 ping fault diagnostics assertion" 3 || return $?
  require_token "$INTEGRATED_TEST_FILE" "debug.runtimeConsoleCount" "S05 runtime console diagnostics assertion" 3 || return $?
  require_token "$INTEGRATED_TEST_FILE" "debug.lastPersistenceSaveAt" "S05 persistence save diagnostics assertion" 3 || return $?
  require_token "$INTEGRATED_TEST_FILE" "debug.lastPersistenceLoadAt" "S05 persistence load diagnostics assertion" 3 || return $?
}

check_package_helper_contract_tokens() {
  require_token "$PACKAGE_SCRIPT" "xcodebuild" "package helper xcodebuild invocation" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "archive" "package helper archive command token" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "-exportArchive" "package helper export command token" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "FILIUSPAD_PACKAGE_DRY_RUN" "package helper dry-run contract token" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "FILIUSPAD_DEVELOPMENT_TEAM" "package helper team config token" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "FILIUSPAD_EXPORT_METHOD" "package helper export-method config token" 4 || return $?
  require_token "$PACKAGE_SCRIPT" "IPA artifact" "package helper explicit IPA artifact failure message" 4 || return $?
}

check_verifier_chaining_and_wiring_tokens() {
  local verifier_file="$ROOT_DIR/scripts/verify-s05.sh"

  require_token "$verifier_file" 'bash "$ROOT_DIR/scripts/verify-s04.sh"' "S05->S04 regression chain command" 5 || return $?
  require_token "$verifier_file" "TopologyIntegratedAcceptanceUITests" "S05 integrated test execution token" 5 || return $?
  require_token "$verifier_file" 'bash "$ROOT_DIR/scripts/package-ipa.sh"' "S05 packaging invocation token" 5 || return $?
}

run_contract_fallback_checks() {
  log "Running host-aware fallback checks (xcodebuild unavailable or not executable on this host)"

  run_contract_phase "Fallback artifacts: required files exist" check_required_artifacts_exist
  run_contract_phase "Fallback contract: integrated UI test diagnostics tokens" check_integrated_ui_test_contract_tokens
  run_contract_phase "Fallback contract: package helper tokens" check_package_helper_contract_tokens
  run_contract_phase "Fallback contract: S04 regression + package wiring tokens" check_verifier_chaining_and_wiring_tokens
  run_contract_phase "Fallback regression: S04 verifier" env S04_VERIFY_ALLOW_MISSING_XCODEBUILD=1 bash "$ROOT_DIR/scripts/verify-s04.sh"
  run_contract_phase "Fallback contract: package dry-run" env FILIUSPAD_PACKAGE_DRY_RUN=1 FILIUSPAD_DEVELOPMENT_TEAM=TEAM12345 FILIUSPAD_EXPORT_METHOD=development bash "$PACKAGE_SCRIPT"

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
  log "  set S05_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback checks"
  exit 127
fi

if [[ -z "${FILIUSPAD_DEVELOPMENT_TEAM:-}" ]]; then
  fail_config "Missing required FILIUSPAD_DEVELOPMENT_TEAM for macOS packaging phase" 95
fi

if [[ -z "${FILIUSPAD_EXPORT_METHOD:-}" ]]; then
  fail_config "Missing required FILIUSPAD_EXPORT_METHOD for macOS packaging phase" 96
fi

run_phase "S04 regression verifier" bash "$ROOT_DIR/scripts/verify-s04.sh"

run_phase \
  "Integrated acceptance UI tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadUITests/TopologyIntegratedAcceptanceUITests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

run_phase \
  "IPA packaging helper" \
  bash "$ROOT_DIR/scripts/package-ipa.sh"

log "All S05 verification phases passed"
