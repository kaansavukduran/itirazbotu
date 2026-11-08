#!/usr/bin/env bash
# macOS + Xcode gerektirir. itiraz_native köprüsünü (llama.cpp dâhil) macOS (arm64+x86_64),
# iOS cihaz (arm64) ve iOS simülatör (arm64+x86_64) için derleyip tek bir xcframework yapar.
# Çıktı: native/apple/itiraz_native.xcframework  (ItirazNative.podspec bunu kullanır)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=$ROOT/build/apple
rm -rf "$OUT" native/apple/itiraz_native.xcframework
GEN=(-G Xcode)

build() { # ad, ek cmake argümanları...
  local name=$1; shift
  cmake -S native -B "$OUT/$name" "${GEN[@]}" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO "$@"
  cmake --build "$OUT/$name" --config Release --target itiraz_native
}

build macos -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
build ios -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
build iossim -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0

fw() { find "$OUT/$1" -type d -name 'itiraz_native.framework' -path '*Release*' | head -1; }
xcodebuild -create-xcframework \
  -framework "$(fw macos)" -framework "$(fw ios)" -framework "$(fw iossim)" \
  -output native/apple/itiraz_native.xcframework
echo "Hazır: native/apple/itiraz_native.xcframework"
