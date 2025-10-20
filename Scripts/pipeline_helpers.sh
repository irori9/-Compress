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
  app_name      Name of the .app (without extension). Only used as a fallback for naming.
  output_dir    Directory to place the .ipa and dSYM.zip
  run_number    GitHub Actions run number (used in IPA filename)
EOF
}

log() {
  echo "[pipeline] $*"
}

ensure_tools() {
  command -v ditto >/dev/null 2>&1 || { echo "ditto is required on macOS"; exit 1; }
  [[ -x /usr/libexec/PlistBuddy ]] || { echo "/usr/libexec/PlistBuddy is required"; exit 1; }
}

package_unsigned_ipa() {
  local archive_path="$1"
  local app_name_fallback="$2"
  local output_dir="$3"
  local run_number="$4"

  if [[ ! -d "$archive_path" ]]; then
    echo "Archive not found: $archive_path" >&2
    exit 1
  fi

  mkdir -p "$output_dir"

  # Read the ApplicationPath from the .xcarchive Info.plist to find the built .app
  local info_plist="$archive_path/Info.plist"
  local rel_app_path=""
  if [[ -f "$info_plist" ]]; then
    rel_app_path=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$info_plist" 2>/dev/null || true)
  fi

  # Build absolute path to the .app within the archive
  local app_path=""
  if [[ -n "$rel_app_path" ]]; then
    # Expect something like "Applications/AppName.app"
    app_path="$archive_path/Products/$rel_app_path"
  else
    # Fallback to the provided app name
    app_path="$archive_path/Products/Applications/${app_name_fallback}.app"
  fi

  if [[ ! -d "$app_path" ]]; then
    echo "App bundle not found at: $app_path" >&2
    echo "Ensure the archive contains an application or that the app_name fallback is correct." >&2
    exit 1
  fi

  # Determine actual app bundle name (e.g., AppName.app)
  local app_name
  app_name=$(basename "$app_path")
  local app_name_noext
  app_name_noext="${app_name%.app}"

  local payload_dir="$output_dir/Payload"
  local ipa_path="$output_dir/${app_name_noext}-unsigned-${run_number}.ipa"

  rm -rf "$payload_dir" "$ipa_path"
  mkdir -p "$payload_dir"

  log "Copying app bundle to Payload/ via ditto"
  /usr/bin/ditto "$app_path" "$payload_dir/$app_name"

  log "Creating unsigned IPA: $ipa_path"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$payload_dir" "$ipa_path"

  # Prepare dSYM.zip
  local dsym_zip="$output_dir/dSYM.zip"
  rm -f "$dsym_zip"

  shopt -s nullglob
  local dsym_dir="$archive_path/dSYMs"
  local dsym_files=("$dsym_dir"/*.dSYM)
  if (( ${#dsym_files[@]} > 0 )); then
    log "Zipping dSYMs to $dsym_zip"
    # ditto supports multiple sources, destination last
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${dsym_files[@]}" "$dsym_zip"
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
