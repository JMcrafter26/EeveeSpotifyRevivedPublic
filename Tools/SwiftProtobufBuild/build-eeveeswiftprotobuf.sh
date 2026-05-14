#!/usr/bin/env bash
# Build EeveeSwiftProtobuf.framework from apple/swift-protobuf source.
#
# The module is renamed SwiftProtobuf → EeveeSwiftProtobuf so that @objc
# class names don't collide with the SwiftProtobuf statically embedded in
# Spotify's SpotifyShared.framework.
#
# Reads:
#   SWIFTPROTOBUF_VERSION  version tag to fetch (default: 1.29.0)
#   THEOS                  path to your theos install (required)
#
# Output: $THEOS/lib/iphone/rootless/EeveeSwiftProtobuf.framework
#
# Re-run whenever SWIFTPROTOBUF_VERSION changes or `swift --version` jumps
# a major.  The resulting framework is committed to the package via the
# Makefile internal-stage:: rule.

set -euo pipefail

FRAMEWORK_NAME="EeveeSwiftProtobuf"
ORIGINAL_NAME="SwiftProtobuf"
SWIFTPROTOBUF_VERSION="${SWIFTPROTOBUF_VERSION:-1.29.0}"

: "${THEOS:?THEOS environment variable is not set}"

DEST_DIR="$THEOS/lib/iphone/rootless"
DEST="$DEST_DIR/$FRAMEWORK_NAME.framework"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# ── 1. Download source ──────────────────────────────────────────────────────
echo "==> Downloading swift-protobuf $SWIFTPROTOBUF_VERSION"
curl -fsSL \
    "https://github.com/apple/swift-protobuf/archive/refs/tags/$SWIFTPROTOBUF_VERSION.tar.gz" \
    -o "$BUILD_DIR/swiftprotobuf.tar.gz"
tar xzf "$BUILD_DIR/swiftprotobuf.tar.gz" -C "$BUILD_DIR"
SRC_DIR="$BUILD_DIR/swift-protobuf-$SWIFTPROTOBUF_VERSION"

# ── 2. Build with xcodebuild, overriding the module/product name ────────────
echo "==> Building $FRAMEWORK_NAME.framework (iOS arm64, release)"
xcodebuild \
    -scheme "$ORIGINAL_NAME" \
    -destination "generic/platform=iOS" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/derived" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/pkgs" \
    PRODUCT_NAME="$FRAMEWORK_NAME" \
    PRODUCT_MODULE_NAME="$FRAMEWORK_NAME" \
    PRODUCT_BUNDLE_IDENTIFIER="org.swift.protobuf.$FRAMEWORK_NAME" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    INSTALL_PATH="/Library/Frameworks" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS=arm64 \
    -quiet \
    2>&1 | grep -Ev "^(note:|warning:.*deprecated|$)" || true

# ── 3. Locate the built framework ───────────────────────────────────────────
BUILT="$(find "$BUILD_DIR/derived" \
    -name "${FRAMEWORK_NAME}.framework" \
    -path "*/Release-iphoneos/*" \
    | head -1)"

if [ -z "$BUILT" ]; then
    echo "ERROR: $FRAMEWORK_NAME.framework not found in derived data." >&2
    echo "Derived data layout:" >&2
    find "$BUILD_DIR/derived" -name "*.framework" | head -20 >&2
    exit 1
fi

# ── 4. Install into Theos lib directory ─────────────────────────────────────
echo "==> Installing to $DEST"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -r "$BUILT" "$DEST"

echo "==> Done — $DEST"
