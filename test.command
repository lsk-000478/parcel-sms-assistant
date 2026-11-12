#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${BUILD_DIR:-$PWD/.build}"
mkdir -p "$BUILD_DIR/tests" "$BUILD_DIR/swift-cache" "$BUILD_DIR/clang-cache"
xcrun swiftc -module-cache-path "$BUILD_DIR/swift-cache" -parse-as-library Sources/Parcel.swift Tests/ParserTests.swift -o "$BUILD_DIR/tests/parser"
"$BUILD_DIR/tests/parser"
xcrun clang -fobjc-arc -fmodules-cache-path="$BUILD_DIR/clang-cache" -c Sources/LegacyText.m -o "$BUILD_DIR/tests/LegacyText.o"
xcrun swiftc -module-cache-path "$BUILD_DIR/swift-cache" -import-objc-header Sources/LegacyText.h "$BUILD_DIR/tests/LegacyText.o" -parse-as-library Sources/BodyDecoder.swift Tests/DecoderTests.swift -o "$BUILD_DIR/tests/decoder" -framework AppKit
"$BUILD_DIR/tests/decoder"
xcrun swiftc -module-cache-path "$BUILD_DIR/swift-cache" -import-objc-header Sources/LegacyText.h "$BUILD_DIR/tests/LegacyText.o" -parse-as-library Sources/Parcel.swift Sources/Inbox.swift Sources/BodyDecoder.swift Tests/InboxTests.swift -o "$BUILD_DIR/tests/inbox" -framework AppKit -lsqlite3
"$BUILD_DIR/tests/inbox"
