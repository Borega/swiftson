#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/FiliusPad/TopologyEditor/Assets/parity-asset-manifest.json"

CHECK_ONLY=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash ios/scripts/sync-java-parity-assets.sh [--check] [--dry-run]

Options:
  --check    Validate manifest + source files without copying.
  --dry-run  Print planned copy operations without writing files.
EOF
}

log() {
  printf '[sync-java-parity-assets] %s\n' "$1"
}

fail() {
  log "✗ $1"
  exit "$2"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "Unknown argument: $1" 64
      ;;
  esac
  shift
done

if [[ ! -f "$MANIFEST_PATH" ]]; then
  fail "Missing manifest: $MANIFEST_PATH" 2
fi

pick_json_runner() {
  if command -v node >/dev/null 2>&1; then
    echo "node"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
    return
  fi

  if command -v python >/dev/null 2>&1; then
    echo "python"
    return
  fi

  fail "Neither node nor python is available to parse $MANIFEST_PATH" 69
}

JSON_RUNNER="$(pick_json_runner)"

read_manifest_value() {
  local key="$1"

  case "$JSON_RUNNER" in
    node)
      node - "$MANIFEST_PATH" "$key" <<'NODE'
const fs = require('fs');
const manifestPath = process.argv[2];
const key = process.argv[3];

const data = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const value = data[key];
if (typeof value !== 'string' || value.trim() === '') {
  process.exit(2);
}
process.stdout.write(value);
NODE
      ;;
    python3|python)
      "$JSON_RUNNER" - "$MANIFEST_PATH" "$key" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
key = sys.argv[2]

with open(manifest_path, 'r', encoding='utf-8') as handle:
    data = json.load(handle)

value = data.get(key)
if not isinstance(value, str) or not value.strip():
    raise SystemExit(2)

print(value)
PY
      ;;
    *)
      fail "Unsupported JSON runner: $JSON_RUNNER" 70
      ;;
  esac
}

emit_manifest_rows() {
  case "$JSON_RUNNER" in
    node)
      node - "$MANIFEST_PATH" <<'NODE'
const fs = require('fs');
const manifestPath = process.argv[2];
const data = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const assets = data.assets;

if (!Array.isArray(assets) || assets.length === 0) {
  process.exit(3);
}

for (const asset of assets) {
  const id = String(asset.id ?? '').trim();
  const src = String(asset.source ?? '').trim();
  const dst = String(asset.target ?? '').trim();
  const required = asset.required !== false;

  if (!id || !src || !dst) {
    process.exit(4);
  }

  process.stdout.write(`${id}\t${src}\t${dst}\t${required ? 1 : 0}\n`);
}
NODE
      ;;
    python3|python)
      "$JSON_RUNNER" - "$MANIFEST_PATH" <<'PY'
import json
import sys

manifest_path = sys.argv[1]

with open(manifest_path, 'r', encoding='utf-8') as handle:
    data = json.load(handle)

assets = data.get('assets')
if not isinstance(assets, list) or not assets:
    raise SystemExit(3)

for asset in assets:
    aid = str(asset.get('id', '')).strip()
    src = str(asset.get('source', '')).strip()
    dst = str(asset.get('target', '')).strip()
    required = bool(asset.get('required', True))

    if not aid or not src or not dst:
        raise SystemExit(4)

    print(f"{aid}\t{src}\t{dst}\t{1 if required else 0}")
PY
      ;;
    *)
      fail "Unsupported JSON runner: $JSON_RUNNER" 70
      ;;
  esac
}

JAVA_RESOURCE_ROOT_RELATIVE="$(read_manifest_value javaResourceRoot)"
TARGET_ROOT_RELATIVE="$(read_manifest_value targetRoot)"
JAVA_RESOURCE_ROOT="$REPO_ROOT/$JAVA_RESOURCE_ROOT_RELATIVE"
TARGET_ROOT="$REPO_ROOT/$TARGET_ROOT_RELATIVE"

if [[ ! -d "$JAVA_RESOURCE_ROOT" ]]; then
  fail "Java resource root does not exist: $JAVA_RESOURCE_ROOT" 3
fi

if [[ $CHECK_ONLY -eq 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$TARGET_ROOT"
fi

MANIFEST_ROWS="$(emit_manifest_rows)"
if [[ -z "$MANIFEST_ROWS" ]]; then
  fail "Manifest contains no asset rows" 5
fi

required_missing=0
optional_missing=0
copied_count=0
validated_count=0

while IFS=$'\t' read -r asset_id source_relative target_relative required_flag; do
  [[ -z "$asset_id" ]] && continue

  source_path="$JAVA_RESOURCE_ROOT/$source_relative"
  target_path="$TARGET_ROOT/$target_relative"

  if [[ ! -f "$source_path" ]]; then
    if [[ "$required_flag" == "1" ]]; then
      log "✗ missing required source asset [$asset_id]: $source_path"
      required_missing=$((required_missing + 1))
    else
      log "⚠ missing optional source asset [$asset_id]: $source_path"
      optional_missing=$((optional_missing + 1))
    fi
    continue
  fi

  validated_count=$((validated_count + 1))

  if [[ $CHECK_ONLY -eq 1 ]]; then
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "↺ dry-run copy [$asset_id]: $source_path -> $target_path"
    copied_count=$((copied_count + 1))
    continue
  fi

  mkdir -p "$(dirname "$target_path")"
  cp "$source_path" "$target_path"
  copied_count=$((copied_count + 1))
  log "✓ copied [$asset_id]"
done <<< "$MANIFEST_ROWS"

if [[ $required_missing -gt 0 ]]; then
  fail "Missing $required_missing required source assets declared by manifest" 6
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  log "Manifest check passed ($validated_count assets validated, $optional_missing optional assets missing)"
  exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
  log "Dry-run complete ($copied_count planned copies, $optional_missing optional assets missing)"
  exit 0
fi

log "Sync complete ($copied_count files copied, $optional_missing optional assets missing)"
