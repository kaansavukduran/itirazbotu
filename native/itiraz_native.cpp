// İtiraz Botu yerel model köprüsü.
//
// Dart tarafı (dart:ffi) yalnızca bu dosyadaki sade C işlevlerini çağırır;
// llama.cpp'nin hızla değişen API'si burada sabit bir yüzeyin arkasına alınır.
// Ağ erişimi yoktur: model yalnızca verilen yerel dosya yolundan okunur.

#include "llama.h"

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define IB_EXPORT extern "C" __declspec(dllexport)
#else
#define IB_EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))
#include <sys/statvfs.h>
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#if TARGET_OS_IPHONE
#include <os/proc.h>
#endif
#endif

#if defined(__ANDROID__)
#include <android/log.h>
#endif

namespace {

constexpr int32_t kAbiVersion = 1;

struct Session {
    llama_model *   model   = nullptr;
    llama_context * ctx     = nullptr;
    llama_sampler * sampler = nullptr;
    const llama_vocab * vocab = nullptr;
    int32_t remaining = 0;
    int32_t n_past = 0;
    llama_token next_token = 0;
    bool has_pending = false;
    std::atomic<int32_t> cancel{0};
    std::string last_error;
};

void copy_err(char * dst, int32_t len, const std::string & msg) {
    if (!dst || len <= 0) return;
    std::snprintf(dst, (size_t) len, "%s", msg.c_str());
}

bool abort_cb(void * data) {
    auto * s = static_cast<Session *>(data);
    return s && s->cancel.load(std::memory_order_relaxed) != 0;
}

void log_cb(ggml_log_level level, const char * text, void *) {
    if (level < GGML_LOG_LEVEL_WARN || !text) return;
#if defined(__ANDROID__)
    __android_log_print(ANDROID_LOG_WARN, "itiraz_native", "%s", text);
#else
    std::fputs(text, stderr);
#endif
}

std::atomic<bool> g_backend_ready{false};

void ensure_backend() {
    bool expected = false;
    if (g_backend_ready.compare_exchange_strong(expected, true)) {
        llama_log_set(log_cb, nullptr);
        llama_backend_init();
    }
}

// Modelin kendi sohbet şablonunu uygular; yoksa sade bir biçime düşer.
std::string build_prompt(const llama_model * model, const char * system, const char * user) {
    std::vector<llama_chat_message> msgs;
    if (system && *system) msgs.push_back({"system", system});
    msgs.push_back({"user", user ? user : ""});
    const char * tmpl = llama_model_chat_template(model, nullptr);
    if (tmpl) {
        std::vector<char> buf(8192);
        int32_t n = llama_chat_apply_template(tmpl, msgs.data(), msgs.size(), true, buf.data(), (int32_t) buf.size());
        if (n > (int32_t) buf.size()) {
            buf.resize((size_t) n + 1);
            n = llama_chat_apply_template(tmpl, msgs.data(), msgs.size(), true, buf.data(), (int32_t) buf.size());
        }
        if (n > 0) return std::string(buf.data(), (size_t) n);
    }
    std::string p;
    if (system && *system) { p += "### Sistem:\n"; p += system; p += "\n\n"; }
    p += "### Kullanıcı:\n"; p += user ? user : ""; p += "\n\n### Yanıt:\n";
    return p;
}

}  // namespace

IB_EXPORT int32_t ib_abi_version(void) { return kAbiVersion; }

// Modeli yükler. Başarısızlıkta NULL döner ve err içine Türkçe açıklama yazar.
struct LoadWatch {
    volatile float * progress;
    volatile int32_t * cancel;
};

static bool load_progress_cb(float p, void * ud) {
    auto * w = static_cast<LoadWatch *>(ud);
    if (w->progress) *w->progress = p;
    return !(w->cancel && *w->cancel != 0);
}

// progress (0..1) ve cancel isteğe bağlıdır; Dart ana isolate'i bunları doğrudan okur/yazar.
IB_EXPORT void * ib_load(const char * path, int32_t n_ctx, int32_t n_threads,
                         volatile float * progress, volatile int32_t * cancel,
                         char * err, int32_t err_len) {
    ensure_backend();
    auto * s = new Session();

    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0;  // Taşınabilirlik için yalnızca CPU.
    LoadWatch watch{progress, cancel};
    mp.progress_callback = load_progress_cb;
    mp.progress_callback_user_data = &watch;
    s->model = llama_model_load_from_file(path, mp);
    if (!s->model) {
        if (cancel && *cancel != 0) {
            copy_err(err, err_len, "Model yüklemesi iptal edildi.");
            delete s;
            return nullptr;
        }
        copy_err(err, err_len, "Model dosyası açılamadı. Dosya bozuk, eksik ya da bu llama.cpp sürümüyle uyumsuz olabilir.");
        delete s;
        return nullptr;
    }
    s->vocab = llama_model_get_vocab(s->model);

    llama_context_params cp = llama_context_default_params();
    int32_t train_ctx = llama_model_n_ctx_train(s->model);
    if (n_ctx <= 0) n_ctx = 2048;
    if (train_ctx > 0 && n_ctx > train_ctx) n_ctx = train_ctx;
    cp.n_ctx = (uint32_t) n_ctx;
    cp.n_batch = 512;
    cp.n_ubatch = 512;
    if (n_threads > 0) { cp.n_threads = n_threads; cp.n_threads_batch = n_threads; }
    cp.abort_callback = abort_cb;
    cp.abort_callback_data = s;
    cp.no_perf = true;
    s->ctx = llama_init_from_model(s->model, cp);
    if (!s->ctx) {
        copy_err(err, err_len, "Model için bellek ayrılamadı. Cihaz belleği yetmiyor olabilir; daha küçük bir model deneyin.");
        llama_model_free(s->model);
        delete s;
        return nullptr;
    }
    return s;
}

IB_EXPORT void ib_free(void * h) {
    auto * s = static_cast<Session *>(h);
    if (!s) return;
    if (s->sampler) llama_sampler_free(s->sampler);
    if (s->ctx) llama_free(s->ctx);
    if (s->model) llama_model_free(s->model);
    delete s;
}

// Başka bir iş parçacığından (Dart ana isolate) çağrılabilir; üretimi durdurur.
IB_EXPORT void ib_cancel(void * h) {
    auto * s = static_cast<Session *>(h);
    if (s) s->cancel.store(1, std::memory_order_relaxed);
}

IB_EXPORT int64_t ib_model_size(void * h) {
    auto * s = static_cast<Session *>(h);
    return s ? (int64_t) llama_model_size(s->model) : 0;
}

IB_EXPORT const char * ib_last_error(void * h) {
    auto * s = static_cast<Session *>(h);
    return s ? s->last_error.c_str() : "";
}

// İstemi hazırlar ve işler. 0: tamam, 1: iptal edildi, <0: hata (ib_last_error).
IB_EXPORT int32_t ib_start(void * h, const char * system, const char * user, int32_t max_tokens,
                           float temperature, uint32_t seed) {
    auto * s = static_cast<Session *>(h);
    if (!s) return -1;
    s->cancel.store(0);
    s->has_pending = false;
    s->n_past = 0;
    llama_memory_clear(llama_get_memory(s->ctx), true);

    if (s->sampler) { llama_sampler_free(s->sampler); s->sampler = nullptr; }
    auto sp = llama_sampler_chain_default_params();
    s->sampler = llama_sampler_chain_init(sp);
    llama_sampler_chain_add(s->sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(s->vocab), 64, 1.1f, 0.0f, 0.0f));
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(s->sampler, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(s->sampler, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(s->sampler, llama_sampler_init_top_p(0.9f, 1));
        llama_sampler_chain_add(s->sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(s->sampler, llama_sampler_init_dist(seed));
    }

    std::string prompt = build_prompt(s->model, system, user);
    int32_t n = -llama_tokenize(s->vocab, prompt.c_str(), (int32_t) prompt.size(), nullptr, 0, true, true);
    if (n <= 0) { s->last_error = "İstem belirteçlere ayrılamadı."; return -2; }
    std::vector<llama_token> toks((size_t) n);
    if (llama_tokenize(s->vocab, prompt.c_str(), (int32_t) prompt.size(), toks.data(), n, true, true) < 0) {
        s->last_error = "İstem belirteçlere ayrılamadı.";
        return -2;
    }
    const int32_t n_ctx = (int32_t) llama_n_ctx(s->ctx);
    if (n + 8 >= n_ctx) { s->last_error = "Metin, modelin bağlam penceresi için çok uzun."; return -3; }
    if (max_tokens <= 0) max_tokens = 256;
    if (n + max_tokens > n_ctx) max_tokens = n_ctx - n;
    s->remaining = max_tokens;

    const int32_t n_batch = (int32_t) llama_n_batch(s->ctx);
    for (int32_t i = 0; i < n; i += n_batch) {
        int32_t len = std::min(n_batch, n - i);
        int32_t rc = llama_decode(s->ctx, llama_batch_get_one(toks.data() + i, len));
        if (rc == 2 || s->cancel.load()) return 1;
        if (rc != 0) { s->last_error = "Model istemi işleyemedi (kod " + std::to_string(rc) + ")."; return -4; }
        s->n_past += len;
    }
    return 0;
}

// Bir sonraki parçayı üretir. >=0: buf içine yazılan bayt (0 olabilir), IB_DONE (-100): bitti,
// -1: iptal, diğer negatifler: hata (ib_last_error).
// Parça UTF-8 karakterin ortasında bitebilir; Dart tarafı akış çözücüyle birleştirir.
IB_EXPORT int32_t ib_next(void * h, char * buf, int32_t buf_len) {
    auto * s = static_cast<Session *>(h);
    if (!s || !s->sampler) return -2;
    if (s->cancel.load()) return -1;
    if (s->remaining <= 0) return -100;

    llama_token tok = llama_sampler_sample(s->sampler, s->ctx, -1);
    if (llama_vocab_is_eog(s->vocab, tok)) return -100;
    s->remaining--;

    int32_t n = llama_token_to_piece(s->vocab, tok, buf, buf_len, 0, false);
    if (n < 0) n = 0;

    int32_t rc = llama_decode(s->ctx, llama_batch_get_one(&tok, 1));
    if (rc == 2 || s->cancel.load()) return -1;
    if (rc != 0) { s->last_error = "Üretim sırasında model hatası (kod " + std::to_string(rc) + ")."; return -3; }
    s->n_past++;
    return n;
}

// Verilen dizinin bulunduğu birimdeki boş alan (bayt). Hata: -1.
IB_EXPORT int64_t ib_free_disk(const char * path_utf8) {
#if defined(_WIN32)
    int wlen = MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, nullptr, 0);
    if (wlen <= 0) return -1;
    std::wstring w((size_t) wlen, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, &w[0], wlen);
    ULARGE_INTEGER avail;
    if (!GetDiskFreeSpaceExW(w.c_str(), &avail, nullptr, nullptr)) return -1;
    return (int64_t) avail.QuadPart;
#else
    struct statvfs st;
    if (statvfs(path_utf8, &st) != 0) return -1;
    return (int64_t) st.f_bavail * (int64_t) st.f_frsize;
#endif
}

// Kullanılabilir fiziksel bellek tahmini (bayt). Bilinmiyorsa -1.
IB_EXPORT int64_t ib_available_ram(void) {
#if defined(_WIN32)
    MEMORYSTATUSEX ms; ms.dwLength = sizeof(ms);
    if (!GlobalMemoryStatusEx(&ms)) return -1;
    return (int64_t) ms.ullAvailPhys;
#elif defined(__APPLE__)
#if TARGET_OS_IPHONE
    if (__builtin_available(iOS 13.0, *)) return (int64_t) os_proc_available_memory();
    return -1;
#else
    vm_statistics64_data_t vm; mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t) &vm, &count) != KERN_SUCCESS) return -1;
    int64_t page = (int64_t) sysconf(_SC_PAGESIZE);
    return ((int64_t) vm.free_count + (int64_t) vm.inactive_count + (int64_t) vm.purgeable_count) * page;
#endif
#else
    FILE * f = std::fopen("/proc/meminfo", "r");
    if (!f) return -1;
    char line[256]; long long kb = -1;
    while (std::fgets(line, sizeof(line), f)) {
        if (std::sscanf(line, "MemAvailable: %lld kB", &kb) == 1) break;
    }
    std::fclose(f);
    return kb < 0 ? -1 : (int64_t) kb * 1024;
#endif
}
