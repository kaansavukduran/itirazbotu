# İtiraz Botu yerel model köprüsü: llama.cpp (sabit sürüm, third_party/llama.cpp)
# statik olarak derlenir ve tek bir paylaşımlı kütüphaneye (itiraz_native) bağlanır.
cmake_minimum_required(VERSION 3.14)
project(itiraz_native LANGUAGES C CXX)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(LLAMA_DIR "${CMAKE_CURRENT_LIST_DIR}/../third_party/llama.cpp")
if(NOT EXISTS "${LLAMA_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "llama.cpp bulunamadı. Çalıştırın: git submodule update --init --recursive")
endif()

# Ağ, araç ve test bileşenleri kapalı; yalnızca çekirdek kütüphane.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_UI OFF CACHE BOOL "" FORCE)
set(LLAMA_USE_PREBUILT_UI OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_SUBPROCESS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_MTMD OFF CACHE BOOL "" FORCE)
set(LLAMA_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
# Taşınabilir ikili: derleyen makinenin CPU'suna özel komut seti kullanma.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
# Metal/GPU kapalı: tüm platformlarda aynı, öngörülebilir CPU yolu (Apple'da Accelerate).
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
if(ANDROID)
  set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
endif()

if(WIN32)
  # Flutter'ın Windows şablonu UNICODE tanımlar; llama.cpp kendi ayarını kullansın.
  remove_definitions(-DUNICODE -D_UNICODE)
endif()

add_subdirectory("${LLAMA_DIR}" llama_build EXCLUDE_FROM_ALL)

add_library(itiraz_native SHARED "${CMAKE_CURRENT_LIST_DIR}/itiraz_native.cpp")
target_link_libraries(itiraz_native PRIVATE llama ggml)
target_compile_features(itiraz_native PRIVATE cxx_std_17)
target_compile_definitions(itiraz_native PRIVATE IB_BUILDING_DLL)
set_target_properties(itiraz_native PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
if(ANDROID)
  target_link_libraries(itiraz_native PRIVATE log)
  # 16 KB sayfa boyutlu Android cihazlarla uyum.
  target_link_options(itiraz_native PRIVATE "-Wl,-z,max-page-size=16384")
endif()
if(MSVC)
  # Türkçe hata iletileri UTF-8 olarak derlensin.
  target_compile_options(itiraz_native PRIVATE /utf-8)
endif()
if(APPLE)
  # iOS/macOS: CocoaPods ile gömülen dinamik çerçeve (bkz. tool/build_apple.sh).
  set_target_properties(itiraz_native PROPERTIES
    FRAMEWORK TRUE
    MACOSX_FRAMEWORK_IDENTIFIER com.itirazbotu.itirazNative
    MACOSX_FRAMEWORK_BUNDLE_VERSION 1
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING 1.0.0
    INSTALL_NAME_DIR "@rpath"
    BUILD_WITH_INSTALL_NAME_DIR ON)
  target_link_libraries(itiraz_native PRIVATE "-framework Accelerate")
endif()
