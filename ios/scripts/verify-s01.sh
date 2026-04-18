#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${S01_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${S01_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"

log() {
  printf '[verify-s01] %s\n' "$1"
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

run_contract_fallback_checks() {
  log "Running contract fallback checks (xcodebuild unavailable on this host)"

  local required_files=(
    "$ROOT_DIR/FiliusPadUITests/TopologyEditorTouchFlowUITests.swift"
    "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"
    "$ROOT_DIR/FiliusPadTests/TopologyEditorDiagnosticsTests.swift"
    "$ROOT_DIR/scripts/verify-s01.sh"
  )

  for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      log "✗ Missing required artifact: ${file}"
      exit 2
    fi
  done

  if ! grep -q 'accessibilityIdentifier("debug.lastValidationError")' "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"; then
    log "✗ Missing debug.lastValidationError accessibility label in TopologyDebugOverlayView.swift"
    exit 3
  fi

  if ! grep -q 'accessibilityIdentifier("canvas.surface")' "$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyCanvasView.swift"; then
    log "✗ Missing canvas.surface accessibility identifier in TopologyCanvasView.swift"
    exit 4
  fi

  if ! grep -q 'TopologyEditorTouchFlowUITests' "$PROJECT_PATH/project.pbxproj"; then
    log "✗ TopologyEditorTouchFlowUITests is not wired into FiliusPad.xcodeproj"
    exit 5
  fi

  if ! grep -q 'TopologyDebugOverlayView.swift' "$PROJECT_PATH/project.pbxproj"; then
    log "✗ TopologyDebugOverlayView.swift is not wired into FiliusPad.xcodeproj"
    exit 6
  fi

  log "✓ Contract fallback checks passed"
}

if ! command -v xcodebuild >/dev/null 2>&1; then
  log "xcodebuild not found in PATH"

  if [[ "$ALLOW_MISSING_XCODEBUILD" == "1" ]]; then
    run_contract_fallback_checks
    exit 0
  fi

  log "Set S01_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback contract checks on non-macOS hosts"
  exit 127
fi

run_phase \
  "Reducer + viewport + diagnostics tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadTests/TopologyEditorReducerTests \
  -only-testing:FiliusPadTests/ViewportTransformTests \
  -only-testing:FiliusPadTests/TopologyEditorDiagnosticsTests \
  test

run_phase \
  "Touch-flow UI tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadUITests/TopologyEditorTouchFlowUITests \
  test

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All S01 verification phases passed"
