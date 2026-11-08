#!/usr/bin/env bash
# Linux/macOS: llama.cpp köprüsünü derler, internetsiz test modeli üretir ve
# gerçek yerel model testlerini çalıştırır.
set -euo pipefail
cd "$(dirname "$0")/.."
git submodule update --init --recursive >/dev/null 2>&1 || true
cmake -S native -B build/native -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build/native --target itiraz_native
python3 -c "import numpy" 2>/dev/null || { echo "numpy gerekli: pip install numpy"; exit 1; }
python3 tool/make_test_model.py build/test-model.gguf build/bozuk.gguf
LIB=build/native/libitiraz_native.so
[[ "$(uname)" == Darwin ]] && LIB=$(find build/native -name itiraz_native -path '*framework*' -type f | head -1)
ITIRAZ_NATIVE_LIB="$PWD/$LIB" ITIRAZ_TEST_MODEL="$PWD/build/test-model.gguf" \
ITIRAZ_BAD_MODEL="$PWD/build/bozuk.gguf" flutter test test/local_model_test.dart
