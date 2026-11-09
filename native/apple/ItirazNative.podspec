# İtiraz Botu yerel model köprüsü (llama.cpp a691b234, yalnızca CPU + Accelerate).
# Önce macOS'ta oluşturun:  ./tool/build_apple.sh   → native/apple/itiraz_native.xcframework
Pod::Spec.new do |s|
  s.name                  = 'ItirazNative'
  s.version               = '1.0.0'
  s.summary               = 'İtiraz Botu için cihaz üzerinde llama.cpp köprüsü'
  s.homepage              = 'https://github.com/kaansavukduran/itirazbotu'
  s.license               = { :type => 'MIT', :text => 'llama.cpp ve ggml MIT lisanslıdır; bkz. third_party/llama.cpp/LICENSE' }
  s.author                = 'İtiraz Botu'
  s.source                = { :path => '.' }
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.vendored_frameworks   = 'itiraz_native.xcframework'
  s.frameworks            = 'Accelerate'
end
