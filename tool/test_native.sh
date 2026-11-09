#!/usr/bin/env bash
# Linux/macOS: llama.cpp köprüsünü derler, internetsiz test modeli üretir ve
# gerçek yerel model testlerini çalıştırır.
set -euo pipefail
cd "$(dirname "$0")/.."
# Bu test ağ kullanmaz; alt modül geliştirme kurulumu sırasında hazırlanmalı.
if [[ ! -f third_party/llama.cpp/CMakeLists.txt ]]; then
  echo 'llama.cpp eksik. Kurulum sırasında: git submodule update --init --recursive'
  exit 1
fi
cmake -S native -B build/native -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build/native --target itiraz_native --parallel "${ITIRAZ_BUILD_JOBS:-4}"
python3 -c "import numpy" 2>/dev/null || { echo "numpy gerekli: pip install numpy"; exit 1; }
python3 tool/make_test_model.py build/test-model.gguf build/bozuk.gguf
LIB=build/native/libitiraz_native.so
[[ "$(uname)" == Darwin ]] && LIB=$(find build/native -name itiraz_native -path '*framework*' -type f | head -1)
ITIRAZ_NATIVE_LIB="$PWD/$LIB" ITIRAZ_TEST_MODEL="$PWD/build/test-model.gguf" \
ITIRAZ_BAD_MODEL="$PWD/build/bozuk.gguf" flutter test test/local_model_test.dart
