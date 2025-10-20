#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 package-unsigned-ipa <archive_path> <app_name> <output_dir> <run_number>

Description:
  Packages an unsigned .ipa from a given .xcarchive and zips dSYMs.

Arguments:
  archive_path  Path to the .xcarchive directory (e.g., build/App.xcarchive)
  app_name      Name of the .app (without extension) and resulting IPA prefix
  output_dir    Directory to place the .ipa and dSYM.zip
  run_number    GitHub Actions run number (used in IPA filename)
EOF
}

log() {
  echo "[pipeline] $*"
}

ensure_tools() {
  command -v ditto >/dev/null 2>&1 || { echo "ditto is required on macOS"; exit 1; }
}

package_unsigned_ipa() {
  local archive_path="$1"
  local app_name="$2"
  local output_dir="$3"
  local run_number="$4"

  if [[ ! -d "$archive_path" ]]; then
    echo "Archive not found: $archive_path" >&2
    exit 1
  fi

  mkdir -p "$output_dir"

  local app_path="$archive_path/Products/Applications/${app_name}.app"
  if [[ ! -d "$app_path" ]]; then
    echo "App bundle not found at: $app_path" >&2
    echo "Please ensure APP_NAME matches the built .app name." >&2
    exit 1
  fi

  local payload_dir="$output_dir/Payload"
  local ipa_path="$output_dir/${app_name}-unsigned-${run_number}.ipa"

  rm -rf "$payload_dir" "$ipa_path"
  mkdir -p "$payload_dir"

  log "Copying app bundle to Payload/"
  cp -R "$app_path" "$payload_dir/"

  log "Creating unsigned IPA: $ipa_path"
  ditto -c -k --sequesterRsrc --keepParent "$payload_dir" "$ipa_path"

  # Prepare dSYM.zip
  local dsym_zip="$output_dir/dSYM.zip"
  rm -f "$dsym_zip"

  shopt -s nullglob
  local dsym_dir="$archive_path/dSYMs"
  local dsym_files=("$dsym_dir"/*.dSYM)
  if (( ${#dsym_files[@]} > 0 )); then
    log "Zipping dSYMs to $dsym_zip"
    # ditto supports multiple sources, destination last
    ditto -c -k --sequesterRsrc --keepParent "${dsym_files[@]}" "$dsym_zip"
  else
    log "No dSYM files found in $dsym_dir; creating empty dSYM.zip"
    /usr/bin/zip -q -r "$dsym_zip" /dev/null || true
  fi

  # Cleanup Payload directory to keep workspace tidy
  rm -rf "$payload_dir"

  log "Packaging done. IPA: $ipa_path | dSYM: $dsym_zip"
}

main() {
  ensure_tools
  if [[ $# -lt 1 ]]; then
    usage; exit 1
  fi
  local cmd="$1"; shift
  case "$cmd" in
    package-unsigned-ipa)
      if [[ $# -ne 4 ]]; then usage; exit 1; fi
      package_unsigned_ipa "$@" ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage; exit 1 ;;
  esac
}

main "$@"
