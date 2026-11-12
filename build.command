#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build}"
APP_OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT}"
TARGET="${TARGET:-arm64-apple-macos14.0}"
APP="$APP_OUTPUT_DIR/快递短信助手.app"
mkdir -p "$BUILD_DIR/clang-cache" "$BUILD_DIR/swift-cache" "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xcrun clang -target "$TARGET" -fobjc-arc -fmodules-cache-path="$BUILD_DIR/clang-cache" -c Sources/LegacyText.m -o "$BUILD_DIR/LegacyText.o"
xcrun swiftc -target "$TARGET" -import-objc-header Sources/LegacyText.h "$BUILD_DIR/LegacyText.o" -module-cache-path "$BUILD_DIR/swift-cache" -parse-as-library Sources/Parcel.swift Sources/Inbox.swift Sources/BodyDecoder.swift Sources/App.swift -o "$APP/Contents/MacOS/ParcelInbox" -framework SwiftUI -framework AppKit -lsqlite3
codesign --force --sign - --identifier local.parcel.sms.inbox "$APP"
echo "已构建：$APP"
