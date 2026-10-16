#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-11.12}"
ARCH="${ARCH:-amd64}"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/linux-mint-deb-work"
PACKAGE_ROOT="$WORK_DIR/te-tool_${VERSION}_${ARCH}"
OUTPUT="$DIST_DIR/TE-Tool-Version-${VERSION}-Linux-Mint-${ARCH}.deb"

command -v dpkg-deb >/dev/null || {
  echo "dpkg-deb is required to build the Linux Mint package." >&2
  exit 1
}

rm -rf "$WORK_DIR"
mkdir -p \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/lib/te-tool/resources" \
  "$PACKAGE_ROOT/usr/share/applications" \
  "$PACKAGE_ROOT/usr/share/doc/te-tool" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/512x512/apps"

cat > "$PACKAGE_ROOT/DEBIAN/control" <<EOF
Package: te-tool
Version: $VERSION
Section: video
Priority: optional
Architecture: $ARCH
Maintainer: Michael Brandon Falk
Depends: bash, python3 (>= 3.10), python3-tk, ffmpeg, jq, libimage-exiftool-perl
Description: Technical Evaluation checks for SVOD and broadcast media
 TE Tool provides a desktop interface for automated FFmpeg and FFprobe media
 checks, including Phase 1, Phase 2, audio, luma, chroma, and caption tests.
EOF

install -m 755 "$ROOT_DIR/cross_platform/te_tool_app.py" "$PACKAGE_ROOT/usr/lib/te-tool/te_tool_app.py"
install -m 755 "$ROOT_DIR/Resources/script" "$PACKAGE_ROOT/usr/lib/te-tool/resources/script"
install -m 755 "$ROOT_DIR/Resources/metadata_helpers.sh" "$PACKAGE_ROOT/usr/lib/te-tool/resources/metadata_helpers.sh"
install -m 755 "$ROOT_DIR/Resources/Cussbuster2000.py" "$PACKAGE_ROOT/usr/lib/te-tool/resources/Cussbuster2000.py"
install -m 644 "$ROOT_DIR/docs/app-icon.png" "$PACKAGE_ROOT/usr/lib/te-tool/resources/app-icon.png"
install -m 644 "$ROOT_DIR/TE TOOLS User Manual.pdf" "$PACKAGE_ROOT/usr/lib/te-tool/resources/TE TOOLS User Manual.pdf"
install -m 644 "$ROOT_DIR/Installation Instructions.pdf" "$PACKAGE_ROOT/usr/lib/te-tool/resources/Installation Instructions.pdf"
install -m 644 "$ROOT_DIR/docs/app-icon.png" "$PACKAGE_ROOT/usr/share/icons/hicolor/512x512/apps/te-tool.png"
install -m 644 "$ROOT_DIR/cross_platform/README-Linux.txt" "$PACKAGE_ROOT/usr/share/doc/te-tool/README.txt"
install -m 644 "$ROOT_DIR/packaging/THIRD_PARTY_NOTICES.txt" "$PACKAGE_ROOT/usr/share/doc/te-tool/THIRD_PARTY_NOTICES.txt"

cat > "$PACKAGE_ROOT/usr/bin/te-tool" <<'EOF'
#!/bin/sh
export TE_RESOURCE_DIR=/usr/lib/te-tool/resources
exec python3 /usr/lib/te-tool/te_tool_app.py "$@"
EOF
chmod 755 "$PACKAGE_ROOT/usr/bin/te-tool"

cat > "$PACKAGE_ROOT/usr/share/applications/te-tool.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=TE Tool Version $VERSION
Comment=Run technical evaluation checks on media files
Exec=te-tool %F
Icon=te-tool
Terminal=false
Categories=AudioVideo;Utility;
MimeType=video/quicktime;video/mp4;
StartupNotify=true
EOF

rm -f "$OUTPUT"
dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$OUTPUT"
sha256sum "$OUTPUT"
