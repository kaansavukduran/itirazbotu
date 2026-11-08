#!/usr/bin/env python3
"""Yerel model hattını (yükleme, üretim, iptal) internetsiz sınamak için minik GGUF üretir.

Ağırlıklar rastgeledir: model anlamlı Türkçe üretmez, yalnızca llama.cpp'nin dosyayı
açıp belirteç ürettiğini kanıtlar. Belirteç sözlüğü llama.cpp deposundaki
models/ggml-vocab-llama-spm.gguf dosyasından kopyalanır (ağ gerekmez).

Kullanım:  python3 tool/make_test_model.py <çıktı.gguf> [bozuk.gguf]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LLAMA = ROOT / "third_party" / "llama.cpp"
sys.path.insert(0, str(LLAMA / "gguf-py"))

import numpy as np  # noqa: E402
import gguf  # noqa: E402

out = Path(sys.argv[1] if len(sys.argv) > 1 else "test-model.gguf")
vocab = gguf.GGUFReader(str(LLAMA / "models" / "ggml-vocab-llama-spm.gguf"))

n_embd, n_layer, n_head, n_ff, n_ctx = 64, 2, 4, 128, 4096
w = gguf.GGUFWriter(str(out), "llama")
w.add_name("itiraz-test-mini (rastgele ağırlık)")
w.add_context_length(n_ctx)
w.add_embedding_length(n_embd)
w.add_block_count(n_layer)
w.add_feed_forward_length(n_ff)
w.add_head_count(n_head)
w.add_head_count_kv(n_head)
w.add_rope_dimension_count(n_embd // n_head)
w.add_layer_norm_rms_eps(1e-5)
w.add_file_type(gguf.LlamaFileType.ALL_F32)

n_vocab = 0
for name, field in vocab.fields.items():
    if not name.startswith("tokenizer."):
        continue
    vtype = field.types[0]
    if vtype == gguf.GGUFValueType.ARRAY:
        sub = field.types[1]
        if sub == gguf.GGUFValueType.STRING:
            vals = [bytes(field.parts[i]).decode("utf-8", "replace") for i in field.data]
        else:
            vals = [field.parts[i].tolist()[0] for i in field.data]
        if name == "tokenizer.ggml.tokens":
            n_vocab = len(vals)
        w.add_array(name, vals)
    elif vtype == gguf.GGUFValueType.STRING:
        w.add_string(name, bytes(field.parts[field.data[0]]).decode("utf-8"))
    else:
        val = field.parts[field.data[0]].tolist()[0]
        if vtype == gguf.GGUFValueType.UINT32:
            w.add_uint32(name, val)
        elif vtype == gguf.GGUFValueType.INT32:
            w.add_int32(name, val)
        elif vtype == gguf.GGUFValueType.BOOL:
            w.add_bool(name, bool(val))
        elif vtype == gguf.GGUFValueType.FLOAT32:
            w.add_float32(name, val)

rng = np.random.default_rng(42)
def t(*shape):
    return (rng.standard_normal(shape) * 0.02).astype(np.float32)

w.add_tensor("token_embd.weight", t(n_vocab, n_embd))
w.add_tensor("output_norm.weight", np.ones(n_embd, dtype=np.float32))
w.add_tensor("output.weight", t(n_vocab, n_embd))
for i in range(n_layer):
    p = f"blk.{i}."
    w.add_tensor(p + "attn_norm.weight", np.ones(n_embd, dtype=np.float32))
    for k in ("attn_q", "attn_k", "attn_v", "attn_output"):
        w.add_tensor(p + k + ".weight", t(n_embd, n_embd))
    w.add_tensor(p + "ffn_norm.weight", np.ones(n_embd, dtype=np.float32))
    w.add_tensor(p + "ffn_gate.weight", t(n_ff, n_embd))
    w.add_tensor(p + "ffn_up.weight", t(n_ff, n_embd))
    w.add_tensor(p + "ffn_down.weight", t(n_embd, n_ff))

w.write_header_to_file()
w.write_kv_data_to_file()
w.write_tensors_to_file()
w.close()
print(f"yazıldı: {out} ({out.stat().st_size} bayt, sözlük {n_vocab})")

if len(sys.argv) > 2:
    # Bozuk model: geçerli başlık, yarıda kesilmiş tensör verisi.
    bad = Path(sys.argv[2])
    data = out.read_bytes()
    bad.write_bytes(data[: len(data) // 3])
    print(f"yazıldı: {bad} (kesik)")
