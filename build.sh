#!/bin/bash
set -e
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
DIR="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$DIR/build"; mkdir -p "$DIR/build"

xcrun -sdk iphoneos clang -fobjc-arc -O2 \
    -arch arm64 -isysroot "$SDK" -mios-version-min=11.0 \
    -dynamiclib -install_name @rpath/AdCleaner.dylib \
    -framework UIKit -framework Foundation \
    -o "$DIR/build/AdCleaner.dylib" \
    "$DIR/AdCleaner.m"

ldid -S "$DIR/build/AdCleaner.dylib" 2>/dev/null || echo "签名跳过"
echo "[完成] $(ls -lh "$DIR/build/AdCleaner.dylib" | awk '{print $5}')"
file "$DIR/build/AdCleaner.dylib"
