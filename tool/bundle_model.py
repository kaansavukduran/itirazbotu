#!/usr/bin/env python3
""""Model dâhil" paket için bir GGUF modelini uygulama kaynaklarına ekler (ağ kullanmaz).

Model 64 MB'lık parçalara bölünür (Android dâhil her platformda belleği yormadan
kopyalanabilsin diye) ve assets/bundled_model/manifest.json yazılır. Uygulama ilk
kullanımda parçaları cihazdaki uygulama dizininde birleştirir.

Kullanım:
  python3 tool/bundle_model.py MODEL.gguf --name "Qwen2.5 0.5B Instruct" --license "Apache-2.0"
  python3 tool/bundle_model.py --clean      # paketi modelsiz hâle döndürür
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "assets" / "bundled_model"
PART = 64 * 1024 * 1024


def clean():
    for f in DEST.iterdir():
        if f.name.startswith("part_") or f.name in {"manifest.json", "MODEL_LICENSE.txt"}:
            f.unlink()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model", nargs="?")
    ap.add_argument("--name")
    ap.add_argument("--license")
    ap.add_argument("--license-file", help="Dağıtılacak modelin tam lisans metni")
    ap.add_argument("--clean", action="store_true")
    a = ap.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    if a.clean:
        clean()
        print("Paket modelsiz.")
        return
    if not a.model:
        ap.error("Bir GGUF dosyası ya da --clean belirtin.")
    src = Path(a.model)
    with src.open("rb") as f:
        if f.read(4) != b"GGUF":
            raise SystemExit("Hata: bu bir GGUF dosyası değil.")
    if a.license_file and not Path(a.license_file).is_file():
        raise SystemExit("Hata: lisans dosyası bulunamadı.")
    clean()
    if a.license_file:
        shutil.copyfile(a.license_file, DEST / "MODEL_LICENSE.txt")
    parts, sha = [], hashlib.sha256()
    with src.open("rb") as f:
        i = 0
        while chunk := f.read(PART):
            name = f"part_{i:03d}.bin"
            (DEST / name).write_bytes(chunk)
            sha.update(chunk)
            parts.append(name)
            i += 1
    manifest = {
        "file": src.name,
        "size": src.stat().st_size,
        "sha256": sha.hexdigest(),
        "parts": parts,
        "name": a.name or src.stem,
        "license": a.license,
    }
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{len(parts)} parça yazıldı → {DEST}")


if __name__ == "__main__":
    main()
