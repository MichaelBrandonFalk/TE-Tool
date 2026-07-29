#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/repaired-a11-work"

APPLE_ZIP="$DIST_DIR/TE-Tool-A11-macOS-Apple-Silicon.zip"
INTEL_ZIP="$DIST_DIR/TE-Tool-A11-macOS-Intel.zip"

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
  local package_folder="$2"
  local stage_dir="$WORK_DIR/$package_folder"
  local extract_dir="$WORK_DIR/extract-$package_folder"
  local package_dir="$stage_dir/$package_folder"
  local output_zip="$DIST_DIR/${source_zip##*/}"
  local app_path="$package_dir/TE Tool Version 3.app"

  if [[ ! -f "$source_zip" ]]; then
    echo "Missing source zip: $source_zip" >&2
    exit 1
  fi

  rm -rf "$stage_dir" "$extract_dir"
  mkdir -p "$stage_dir" "$extract_dir"
  ditto -x -k --noqtn --noextattr "$source_zip" "$extract_dir"

  if [[ -d "$extract_dir/$package_folder" ]]; then
    ditto --noqtn --noextattr "$extract_dir/$package_folder" "$package_dir"
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
    ditto -c -k --keepParent --norsrc --noextattr --noqtn --zlibCompressionLevel 9 "$package_folder" "$output_zip"
  )

  shasum -a 256 "$output_zip"
}

mkdir -p "$WORK_DIR"
repair_zip "$APPLE_ZIP" "TE Tool Version A11 Apple Silicon"
repair_zip "$INTEL_ZIP" "TE Tool Version A11 Intel"
