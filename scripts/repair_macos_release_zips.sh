#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   SOURCE_VERSION=A11 RELEASE_VERSION=A11.1 scripts/repair_macos_release_zips.sh
#
# The script intentionally expects a new RELEASE_VERSION for package changes.
# Set ALLOW_SAME_VERSION=1 only for local diagnostics.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/repaired-release-work"
SOURCE_VERSION="${SOURCE_VERSION:-A11}"
RELEASE_VERSION="${RELEASE_VERSION:-$SOURCE_VERSION}"

if [[ "${ALLOW_SAME_VERSION:-0}" != "1" && "$RELEASE_VERSION" == "$SOURCE_VERSION" ]]; then
  echo "RELEASE_VERSION must differ from SOURCE_VERSION for a published package change." >&2
  echo "Example: SOURCE_VERSION=A11 RELEASE_VERSION=A11.1 $0" >&2
  exit 1
fi

APPLE_ZIP="$DIST_DIR/TE-Tool-${SOURCE_VERSION}-macOS-Apple-Silicon.zip"
INTEL_ZIP="$DIST_DIR/TE-Tool-${SOURCE_VERSION}-macOS-Intel.zip"
APPLE_OUTPUT_ZIP="$DIST_DIR/TE-Tool-${RELEASE_VERSION}-macOS-Apple-Silicon.zip"
INTEL_OUTPUT_ZIP="$DIST_DIR/TE-Tool-${RELEASE_VERSION}-macOS-Intel.zip"

repair_python_launchers() {
  local app_path="$1"
  local pybin="$app_path/Contents/Resources/pyenv/bin"

  [[ -d "$pybin" ]] || return 0

  for name in python python3 python3.9; do
    local launcher="$pybin/$name"
    rm -f "$launcher"
    printf '%s\n' '#!/bin/sh' 'exec /usr/bin/env python3 "$@"' > "$launcher"
    chmod 755 "$launcher"
  done
}

sign_macho_resources() {
  local app_path="$1"

  while IFS= read -r -d '' file_path; do
    if ! file -b "$file_path" | grep -q 'Mach-O'; then
      continue
    fi

    case "$file_path" in
      "$app_path/Contents/MacOS/"*)
        ;;
      "$app_path/Contents/Resources/Dialog.app/"*)
        ;;
      *)
        codesign --force --sign - --timestamp=none "$file_path" >/dev/null
        ;;
    esac
  done < <(find "$app_path/Contents" -type f -print0)
}

repair_zip() {
  local source_zip="$1"
  local source_package_folder="$2"
  local output_package_folder="$3"
  local output_zip="$4"
  local stage_dir="$WORK_DIR/$output_package_folder"
  local extract_dir="$WORK_DIR/extract-$output_package_folder"
  local package_dir="$stage_dir/$output_package_folder"
  local app_path="$package_dir/TE Tool Version 3.app"

  if [[ ! -f "$source_zip" ]]; then
    echo "Missing source zip: $source_zip" >&2
    exit 1
  fi

  rm -rf "$stage_dir" "$extract_dir"
  mkdir -p "$stage_dir" "$extract_dir"
  ditto -x -k --noqtn --noextattr "$source_zip" "$extract_dir"

  if [[ -d "$extract_dir/$source_package_folder" ]]; then
    ditto --noqtn --noextattr "$extract_dir/$source_package_folder" "$package_dir"
  elif [[ -d "$extract_dir/$output_package_folder" ]]; then
    ditto --noqtn --noextattr "$extract_dir/$output_package_folder" "$package_dir"
  elif [[ -d "$extract_dir/TE Tool Version 3.app" ]]; then
    mkdir -p "$package_dir"
    ditto --noqtn --noextattr "$extract_dir" "$package_dir"
  fi

  if [[ ! -d "$app_path" ]]; then
    echo "Missing app bundle in $source_zip" >&2
    exit 1
  fi

  chmod -R u+rwX "$stage_dir"
  find "$app_path" -maxdepth 1 -type f -delete
  find "$stage_dir" -name ".DS_Store" -type f -delete
  xattr -cr "$stage_dir" 2>/dev/null || true

  repair_python_launchers "$app_path"
  sign_macho_resources "$app_path"

  if [[ -d "$app_path/Contents/Resources/Dialog.app" ]]; then
    codesign --force --deep --sign - --timestamp=none "$app_path/Contents/Resources/Dialog.app"
  fi

  codesign --force --deep --sign - --timestamp=none "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"

  rm -f "$output_zip"
  (
    cd "$stage_dir"
    ditto -c -k --keepParent --norsrc --noextattr --noqtn --zlibCompressionLevel 9 "$output_package_folder" "$output_zip"
  )

  shasum -a 256 "$output_zip"
}

mkdir -p "$WORK_DIR"
repair_zip "$APPLE_ZIP" "TE Tool Version ${SOURCE_VERSION} Apple Silicon" "TE Tool Version ${RELEASE_VERSION} Apple Silicon" "$APPLE_OUTPUT_ZIP"
repair_zip "$INTEL_ZIP" "TE Tool Version ${SOURCE_VERSION} Intel" "TE Tool Version ${RELEASE_VERSION} Intel" "$INTEL_OUTPUT_ZIP"
