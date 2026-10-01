#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   SOURCE_VERSION=Version-11.8 RELEASE_VERSION=11.9 scripts/repair_macos_release_zips.sh
#
# The script intentionally expects a new RELEASE_VERSION for package changes.
# Set ALLOW_SAME_VERSION=1 only for local diagnostics.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/repaired-release-work"
SOURCE_VERSION="${SOURCE_VERSION:-Version-11.8}"
RELEASE_VERSION="${RELEASE_VERSION:-$SOURCE_VERSION}"

ARM64_FFMPEG_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip"
ARM64_FFMPEG_SHA256="c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"
ARM64_FFPROBE_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffprobe.zip"
ARM64_FFPROBE_SHA256="fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6"
ARM64_JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-macos-arm64"
ARM64_JQ_SHA256="a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603"
ARM64_TOOLS_DIR="$WORK_DIR/dependencies/arm64"

if [[ "${ALLOW_SAME_VERSION:-0}" != "1" && "$RELEASE_VERSION" == "$SOURCE_VERSION" ]]; then
  echo "RELEASE_VERSION must differ from SOURCE_VERSION for a published package change." >&2
  echo "Example: SOURCE_VERSION=Version-11.8 RELEASE_VERSION=11.9 $0" >&2
  exit 1
fi

version_number() {
  local value="$1"

  value="${value#Version-}"
  value="${value#Version }"
  value="${value#V}"
  value="${value#v}"
  value="${value#A}"
  printf '%s\n' "$value"
}

version_slug() {
  local value="$1"
  local numeric_version
  numeric_version=$(version_number "$value")

  case "$value" in
    A*) printf '%s\n' "$value" ;;
    Version-*) printf '%s\n' "$value" ;;
    *) printf 'Version-%s\n' "$numeric_version" ;;
  esac
}

SOURCE_DISPLAY_VERSION="${SOURCE_DISPLAY_VERSION:-$(version_number "$SOURCE_VERSION")}"
RELEASE_DISPLAY_VERSION="${RELEASE_DISPLAY_VERSION:-$(version_number "$RELEASE_VERSION")}"
SOURCE_ASSET_SLUG="${SOURCE_ASSET_SLUG:-$(version_slug "$SOURCE_VERSION")}"
RELEASE_ASSET_SLUG="${RELEASE_ASSET_SLUG:-$(version_slug "$RELEASE_VERSION")}"

APPLE_ZIP="$DIST_DIR/TE-Tool-${SOURCE_ASSET_SLUG}-macOS-Apple-Silicon.zip"
INTEL_ZIP="$DIST_DIR/TE-Tool-${SOURCE_ASSET_SLUG}-macOS-Intel.zip"
APPLE_OUTPUT_ZIP="$DIST_DIR/TE-Tool-${RELEASE_ASSET_SLUG}-macOS-Apple-Silicon.zip"
INTEL_OUTPUT_ZIP="$DIST_DIR/TE-Tool-${RELEASE_ASSET_SLUG}-macOS-Intel.zip"
APP_BUNDLE_NAME="TE Tool Version ${RELEASE_DISPLAY_VERSION}"

set_plist_string() {
  local plist="$1"
  local key="$2"
  local value="$3"

  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

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

sha256_matches() {
  local file_path="$1"
  local expected_sha="$2"
  local actual_sha

  [[ -f "$file_path" ]] || return 1
  actual_sha=$(shasum -a 256 "$file_path" | awk '{print $1}')
  [[ "$actual_sha" == "$expected_sha" ]]
}

download_verified_file() {
  local url="$1"
  local expected_sha="$2"
  local output_path="$3"

  if ! sha256_matches "$output_path" "$expected_sha"; then
    rm -f "$output_path"
    curl --fail --location --silent --show-error "$url" --output "$output_path"
  fi

  if ! sha256_matches "$output_path" "$expected_sha"; then
    echo "Checksum verification failed for $output_path" >&2
    exit 1
  fi
}

prepare_arm64_tools() {
  local ffmpeg_zip="$ARM64_TOOLS_DIR/ffmpeg.zip"
  local ffprobe_zip="$ARM64_TOOLS_DIR/ffprobe.zip"

  mkdir -p "$ARM64_TOOLS_DIR"
  download_verified_file "$ARM64_FFMPEG_URL" "$ARM64_FFMPEG_SHA256" "$ffmpeg_zip"
  download_verified_file "$ARM64_FFPROBE_URL" "$ARM64_FFPROBE_SHA256" "$ffprobe_zip"
  download_verified_file "$ARM64_JQ_URL" "$ARM64_JQ_SHA256" "$ARM64_TOOLS_DIR/jq"

  rm -f "$ARM64_TOOLS_DIR/ffmpeg" "$ARM64_TOOLS_DIR/ffprobe"
  ditto -x -k --noqtn --noextattr "$ffmpeg_zip" "$ARM64_TOOLS_DIR"
  ditto -x -k --noqtn --noextattr "$ffprobe_zip" "$ARM64_TOOLS_DIR"
  chmod 755 "$ARM64_TOOLS_DIR/ffmpeg" "$ARM64_TOOLS_DIR/ffprobe" "$ARM64_TOOLS_DIR/jq"
}

verify_binary_architecture() {
  local binary_path="$1"
  local expected_arch="$2"
  local binary_arches

  binary_arches=$(lipo -archs "$binary_path" 2>/dev/null || true)
  if [[ " $binary_arches " != *" $expected_arch "* ]]; then
    echo "Architecture check failed: $binary_path is [$binary_arches], expected $expected_arch." >&2
    exit 1
  fi
}

overlay_current_resources() {
  local app_path="$1"
  local package_dir="$2"
  local target_arch="$3"

  install -m 755 "$ROOT_DIR/Resources/script" "$app_path/Contents/Resources/script"
  install -m 755 "$ROOT_DIR/Resources/metadata_helpers.sh" "$app_path/Contents/Resources/metadata_helpers.sh"
  install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
  install -m 644 "$ROOT_DIR/Installation Instructions.pdf" "$package_dir/Installation Instructions.pdf"

  if [[ "$target_arch" == "arm64" ]]; then
    install -m 755 "$ARM64_TOOLS_DIR/ffmpeg" "$app_path/Contents/Resources/ffmpeg"
    install -m 755 "$ARM64_TOOLS_DIR/ffprobe" "$app_path/Contents/Resources/ffprobe"
    install -m 755 "$ARM64_TOOLS_DIR/jq" "$app_path/Contents/Resources/jq"
  else
    install -m 755 "$ROOT_DIR/Resources/ffmpeg" "$app_path/Contents/Resources/ffmpeg"
    install -m 755 "$ROOT_DIR/Resources/ffprobe" "$app_path/Contents/Resources/ffprobe"
    install -m 755 "$ROOT_DIR/Resources/jq" "$app_path/Contents/Resources/jq"
  fi

  verify_binary_architecture "$app_path/Contents/Resources/ffmpeg" "$target_arch"
  verify_binary_architecture "$app_path/Contents/Resources/ffprobe" "$target_arch"
  verify_binary_architecture "$app_path/Contents/Resources/jq" "$target_arch"
}

set_bundle_metadata() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"

  set_plist_string "$plist" "CFBundleName" "$APP_BUNDLE_NAME"
  set_plist_string "$plist" "CFBundleDisplayName" "$APP_BUNDLE_NAME"
  set_plist_string "$plist" "CFBundleExecutable" "$APP_BUNDLE_NAME"
  set_plist_string "$plist" "CFBundleIconFile" "AppIcon"
  set_plist_string "$plist" "CFBundleIconName" "AppIcon"
  set_plist_string "$plist" "CFBundleShortVersionString" "$RELEASE_DISPLAY_VERSION"
  set_plist_string "$plist" "CFBundleVersion" "$RELEASE_DISPLAY_VERSION"
}

find_packaged_app() {
  local package_dir="$1"

  [[ -d "$package_dir" ]] || return 0
  find "$package_dir" -maxdepth 1 -name "*.app" -type d -print -quit
}

rename_app_bundle() {
  local package_dir="$1"
  local app_path="$2"
  local target_app_path="$package_dir/${APP_BUNDLE_NAME}.app"

  if [[ "$app_path" != "$target_app_path" ]]; then
    mv "$app_path" "$target_app_path"
  fi

  printf '%s\n' "$target_app_path"
}

rename_main_executable() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  local macos_dir="$app_path/Contents/MacOS"
  local current_executable
  current_executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || true)

  if [[ -n "$current_executable" && -f "$macos_dir/$current_executable" && "$current_executable" != "$APP_BUNDLE_NAME" ]]; then
    mv "$macos_dir/$current_executable" "$macos_dir/$APP_BUNDLE_NAME"
  elif [[ ! -f "$macos_dir/$APP_BUNDLE_NAME" ]]; then
    local only_executable
    only_executable=$(find "$macos_dir" -maxdepth 1 -type f -perm -111 -print -quit)
    if [[ -n "$only_executable" ]]; then
      mv "$only_executable" "$macos_dir/$APP_BUNDLE_NAME"
    fi
  fi

  chmod 755 "$macos_dir/$APP_BUNDLE_NAME"
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
  local target_arch="$5"
  local stage_dir="$WORK_DIR/$output_package_folder"
  local extract_dir="$WORK_DIR/extract-$output_package_folder"
  local package_dir="$stage_dir/$output_package_folder"
  local app_path=""

  if [[ ! -f "$source_zip" ]]; then
    echo "Missing source zip: $source_zip" >&2
    exit 1
  fi

  rm -rf "$stage_dir" "$extract_dir"
  mkdir -p "$stage_dir" "$extract_dir"
  ditto -x -k --noqtn --noextattr "$source_zip" "$extract_dir"

  for candidate in \
    "$source_package_folder" \
    "${source_package_folder/TE Tool Version /TE Tool }" \
    "${source_package_folder/Version $SOURCE_DISPLAY_VERSION/$SOURCE_VERSION}" \
    "${source_package_folder/TE Tool Version $SOURCE_DISPLAY_VERSION/TE Tool $SOURCE_VERSION}" \
    "$output_package_folder"; do
    if [[ -d "$extract_dir/$candidate" ]]; then
      ditto --noqtn --noextattr "$extract_dir/$candidate" "$package_dir"
      break
    fi
  done
  if [[ ! -d "$package_dir" || -z "$(find_packaged_app "$package_dir")" ]]; then
    mkdir -p "$package_dir"
    ditto --noqtn --noextattr "$extract_dir" "$package_dir"
  fi

  app_path=$(find_packaged_app "$package_dir")
  if [[ -z "$app_path" || ! -d "$app_path" ]]; then
    echo "Missing app bundle in $source_zip" >&2
    exit 1
  fi

  app_path=$(rename_app_bundle "$package_dir" "$app_path")
  chmod -R u+rwX "$stage_dir"
  find "$app_path" -maxdepth 1 -type f -delete
  find "$stage_dir" -name ".DS_Store" -type f -delete
  xattr -cr "$stage_dir" 2>/dev/null || true

  repair_python_launchers "$app_path"
  overlay_current_resources "$app_path" "$package_dir" "$target_arch"
  rename_main_executable "$app_path"
  set_bundle_metadata "$app_path"
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
prepare_arm64_tools
repair_zip "$APPLE_ZIP" "TE Tool Version ${SOURCE_DISPLAY_VERSION} Apple Silicon" "TE Tool Version ${RELEASE_DISPLAY_VERSION} Apple Silicon" "$APPLE_OUTPUT_ZIP" "arm64"
repair_zip "$INTEL_ZIP" "TE Tool Version ${SOURCE_DISPLAY_VERSION} Intel" "TE Tool Version ${RELEASE_DISPLAY_VERSION} Intel" "$INTEL_OUTPUT_ZIP" "x86_64"
