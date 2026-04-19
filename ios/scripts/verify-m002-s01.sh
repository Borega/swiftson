#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="FiliusPad"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (10th generation)}"
TIMEOUT_SECONDS="${M002_S01_VERIFY_TIMEOUT_SECONDS:-}"
ALLOW_MISSING_XCODEBUILD="${M002_S01_VERIFY_ALLOW_MISSING_XCODEBUILD:-1}"
PHASE="all"
VISUAL_THRESHOLD="${M002_S01_VISUAL_SIMILARITY_THRESHOLD:-0.94}"

MANIFEST_PATH="$ROOT_DIR/FiliusPad/TopologyEditor/Assets/parity-asset-manifest.json"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync-java-parity-assets.sh"
PALETTE_VIEW_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyPaletteView.swift"
CANVAS_VIEW_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyCanvasView.swift"
EDITOR_VIEW_FILE="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyEditorView.swift"
VISUAL_BASELINE_DIR="$ROOT_DIR/FiliusPadUITests/ParityBaselines"

log() {
  printf '[verify-m002-s01] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_configuration() {
  if [[ -n "$TIMEOUT_SECONDS" ]] && [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid M002_S01_VERIFY_TIMEOUT_SECONDS='$TIMEOUT_SECONDS' (expected integer seconds)" 90
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
      fail_config "Invalid M002_S01_VERIFY_ALLOW_MISSING_XCODEBUILD='$ALLOW_MISSING_XCODEBUILD' (expected 0 or 1)" 92
      ;;
  esac

  case "$PHASE" in
    all|assets|palette|canvas|interaction)
      ;;
    *)
      fail_config "Invalid --phase '$PHASE' (expected: all|assets|palette|canvas|interaction)" 94
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

emit_touch_flow_failure_diagnostics() {
  local result_bundle="$1"

  if [[ ! -d "$result_bundle" ]]; then
    log "touch-flow diagnostics: result bundle missing at $result_bundle"
    return
  fi

  if ! command -v xcrun >/dev/null 2>&1; then
    log "touch-flow diagnostics: xcrun unavailable; skipping xcresult extraction"
    return
  fi

  local summary_output
  summary_output="$(xcrun xcresulttool get test-results summary --path "$result_bundle" 2>/dev/null || true)"
  if [[ -n "$summary_output" ]]; then
    log "touch-flow diagnostics summary"
    printf '%s\n' "$summary_output"
  fi

  local tests_output
  tests_output="$(xcrun xcresulttool get test-results tests --path "$result_bundle" 2>/dev/null || true)"
  if [[ -n "$tests_output" ]]; then
    log "touch-flow diagnostics (filtered)"
    printf '%s\n' "$tests_output" \
      | grep -E "TopologyEditorTouchFlowUITests|failed|failure|message|assert|Expected|Setup failure|Malformed input guard" \
      | head -n 120 || true
  fi
}

run_touch_flow_ui_phase() {
  local result_bundle="$ROOT_DIR/build/m002-s01-touchflow.xcresult"
  rm -rf "$result_bundle"

  local started_at
  started_at="$(date +%s)"

  log "▶ Touch-flow UI tests"

  set +e
  run_with_optional_timeout \
    xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -resultBundlePath "$result_bundle" \
    -only-testing:FiliusPadUITests/TopologyEditorTouchFlowUITests \
    test
  local status=$?
  set -e

  local finished_at
  finished_at="$(date +%s)"
  local duration=$((finished_at - started_at))

  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 124 ]]; then
      log "✗ Touch-flow UI tests timed out after ${duration}s"
    else
      log "✗ Touch-flow UI tests failed after ${duration}s"
    fi

    log "  command: xcodebuild -project $PROJECT_PATH -scheme $SCHEME -destination $DESTINATION -resultBundlePath $result_bundle -only-testing:FiliusPadUITests/TopologyEditorTouchFlowUITests test"
    emit_touch_flow_failure_diagnostics "$result_bundle"
    exit "$status"
  fi

  log "✓ Touch-flow UI tests passed in ${duration}s"
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
  ensure_file_exists "$MANIFEST_PATH" 2 || return $?
  ensure_file_exists "$SYNC_SCRIPT" 2 || return $?
  ensure_file_exists "$PALETTE_VIEW_FILE" 2 || return $?
  ensure_file_exists "$CANVAS_VIEW_FILE" 2 || return $?
  ensure_file_exists "$EDITOR_VIEW_FILE" 2 || return $?
  ensure_file_exists "$PROJECT_PATH/project.pbxproj" 2 || return $?
}

check_manifest_contract_tokens() {
  require_token "$MANIFEST_PATH" '"iconMode": "default"' "default icon-mode declaration" 3 || return $?
  require_token "$MANIFEST_PATH" '"id": "palette.pc"' "palette pc asset mapping" 3 || return $?
  require_token "$MANIFEST_PATH" '"source": "gfx/hardware/server.png"' "server icon source mapping" 3 || return $?
  require_token "$MANIFEST_PATH" '"id": "palette.switch"' "palette switch asset mapping" 3 || return $?
  require_token "$MANIFEST_PATH" '"source": "gfx/hardware/switch.png"' "switch icon source mapping" 3 || return $?
  require_token "$MANIFEST_PATH" '"id": "palette.cable"' "palette cable mapping" 3 || return $?
}

check_asset_sync_contract() {
  ensure_file_exists "$SYNC_SCRIPT" 4 || return $?
  require_token "$SYNC_SCRIPT" 'parity-asset-manifest.json' "sync script manifest reference" 4 || return $?
  require_token "$SYNC_SCRIPT" '--check' "sync script check mode" 4 || return $?
  require_token "$SYNC_SCRIPT" 'Missing $required_missing required source assets declared by manifest' "sync script hard-fail message" 4 || return $?

  bash "$SYNC_SCRIPT" --check
}

check_project_resource_wiring_contract() {
  local project_file="$PROJECT_PATH/project.pbxproj"

  require_token "$project_file" "JavaParity in Resources" "Xcode resource build wiring for Java parity assets" 9 || return $?
  require_token "$project_file" "Assets/JavaParity" "Xcode folder reference path for Java parity assets" 9 || return $?
}

check_palette_contract_tokens() {
  require_token "$PALETTE_VIEW_FILE" "palette.toolbar" "palette toolbar accessibility identifier" 5 || return $?
  require_token "$PALETTE_VIEW_FILE" "runtime.control.start" "runtime start control identifier" 5 || return $?
  require_token "$PALETTE_VIEW_FILE" "runtime.control.stop" "runtime stop control identifier" 5 || return $?
  require_token "$PALETTE_VIEW_FILE" "hardware/server.png" "palette Java parity PC icon mapping" 5 || return $?
  require_token "$PALETTE_VIEW_FILE" "hardware/switch.png" "palette Java parity switch icon mapping" 5 || return $?
  require_token "$PALETTE_VIEW_FILE" "hardware/kabel.png" "palette Java parity cable icon mapping" 5 || return $?
  require_token "$PALETTE_VIEW_FILE" "TopologyParityAssetLoader" "palette parity asset loader usage" 5 || return $?
}

check_canvas_contract_tokens() {
  require_token "$CANVAS_VIEW_FILE" "canvas.surface" "canvas accessibility identifier" 6 || return $?
  require_token "$CANVAS_VIEW_FILE" "canvas.linkLayer" "canvas link-layer identifier" 6 || return $?
  require_token "$CANVAS_VIEW_FILE" "canvas.nodeLayer" "canvas node-layer identifier" 6 || return $?
  require_token "$CANVAS_VIEW_FILE" "hardware/server.png" "canvas Java parity PC icon mapping" 6 || return $?
  require_token "$CANVAS_VIEW_FILE" "hardware/switch.png" "canvas Java parity switch icon mapping" 6 || return $?
  require_token "$CANVAS_VIEW_FILE" "allgemein/entwurfshg.png" "canvas Java parity background mapping" 6 || return $?
  require_token "$CANVAS_VIEW_FILE" "TopologyParityAssetLoader" "canvas parity asset loader usage" 6 || return $?
}

check_interaction_contract_tokens() {
  local debug_overlay_file="$ROOT_DIR/FiliusPad/TopologyEditor/View/TopologyDebugOverlayView.swift"
  local touch_flow_test_file="$ROOT_DIR/FiliusPadUITests/TopologyEditorTouchFlowUITests.swift"

  require_token "$EDITOR_VIEW_FILE" "handleCanvasTap" "tap placement flow hook" 7 || return $?
  require_token "$EDITOR_VIEW_FILE" "dropDestination(for: String.self)" "palette drag-drop destination wiring" 7 || return $?
  require_token "$EDITOR_VIEW_FILE" "handlePaletteDrop" "palette drag-drop handler" 7 || return $?
  require_token "$EDITOR_VIEW_FILE" "setInteractionMode" "interaction diagnostics reducer action" 7 || return $?
  require_token "$PALETTE_VIEW_FILE" "onDrag" "palette drag source wiring" 7 || return $?
  require_token "$debug_overlay_file" "debug.lastInteractionMode" "interaction diagnostics overlay identifier" 7 || return $?
  require_token "$touch_flow_test_file" "debug.lastInteractionMode" "interaction diagnostics UI-test assertion token" 7 || return $?
}

check_visual_baseline_contract() {
  ensure_file_exists "$VISUAL_BASELINE_DIR/.keep" 8 || return $?

  local threshold_regex='^0\.[0-9]+$|^1(\.0+)?$'
  if [[ ! "$VISUAL_THRESHOLD" =~ $threshold_regex ]]; then
    log "✗ Invalid visual threshold '${VISUAL_THRESHOLD}' (expected decimal in [0,1])"
    return 8
  fi

  if command -v node >/dev/null 2>&1; then
    if ! node - "$VISUAL_THRESHOLD" <<'NODE'
const threshold = Number(process.argv[2]);
if (!Number.isFinite(threshold) || threshold < 0.94) {
  process.exit(1);
}
NODE
    then
      log "✗ Visual similarity threshold must be >= 0.94 (current: ${VISUAL_THRESHOLD})"
      return 8
    fi
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$VISUAL_THRESHOLD" <<'PY'
import sys
threshold = float(sys.argv[1])
if threshold < 0.94:
    raise SystemExit(1)
PY
    then
      log "✗ Visual similarity threshold must be >= 0.94 (current: ${VISUAL_THRESHOLD})"
      return 8
    fi
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    if ! python - "$VISUAL_THRESHOLD" <<'PY'
import sys
threshold = float(sys.argv[1])
if threshold < 0.94:
    raise SystemExit(1)
PY
    then
      log "✗ Visual similarity threshold must be >= 0.94 (current: ${VISUAL_THRESHOLD})"
      return 8
    fi
    return 0
  fi

  log "✗ Neither node nor python is available to validate visual threshold"
  return 8
}

run_selected_contract_phases() {
  case "$PHASE" in
    assets)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Asset manifest contract" check_manifest_contract_tokens
      run_contract_phase "Asset sync contract" check_asset_sync_contract
      run_contract_phase "Project resource wiring contract" check_project_resource_wiring_contract
      ;;
    palette)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Palette contract" check_palette_contract_tokens
      ;;
    canvas)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Canvas contract" check_canvas_contract_tokens
      ;;
    interaction)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Interaction contract" check_interaction_contract_tokens
      run_contract_phase "Visual baseline contract" check_visual_baseline_contract
      ;;
    all)
      run_contract_phase "Artifacts exist" check_required_artifacts_exist
      run_contract_phase "Asset manifest contract" check_manifest_contract_tokens
      run_contract_phase "Asset sync contract" check_asset_sync_contract
      run_contract_phase "Project resource wiring contract" check_project_resource_wiring_contract
      run_contract_phase "Palette contract" check_palette_contract_tokens
      run_contract_phase "Canvas contract" check_canvas_contract_tokens
      run_contract_phase "Interaction contract" check_interaction_contract_tokens
      run_contract_phase "Visual baseline contract" check_visual_baseline_contract
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
Usage: bash ios/scripts/verify-m002-s01.sh [--phase all|assets|palette|canvas|interaction]

Host-aware verifier for M002/S01 parity foundation.
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
  log "  set M002_S01_VERIFY_ALLOW_MISSING_XCODEBUILD=1 to run fallback checks"
  exit 127
fi

run_phase \
  "Reducer + canvas tests" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:FiliusPadTests/TopologyEditorReducerTests \
  -only-testing:FiliusPadTests/TopologyEditorDiagnosticsTests \
  test

run_touch_flow_ui_phase

run_phase \
  "Project build" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

log "All M002/S01 verification phases passed"
