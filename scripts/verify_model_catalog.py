#!/usr/bin/env python3
"""Check Resources/ModelCatalog.json against the live Hugging Face Hub.

For every catalog entry this confirms the repository exists, is not gated,
and contains the listed GGUF file, and that the catalog's sizeBytes and
sha256 match what the Hub reports. Exits non-zero on any mismatch so the
app never ships a fabricated repository, filename or size.

  --discover   also print every .gguf file (size + sha256) in each repo,
               which is how new entries' metadata should be filled in.
"""
import json
import sys
import urllib.request

CATALOG = "Resources/ModelCatalog.json"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "anchord-catalog-check"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main():
    discover = "--discover" in sys.argv
    with open(CATALOG) as f:
        entries = json.load(f)["models"]

    failures = 0
    for e in entries:
        repo, name = e["repository"], e["fileName"]
        print(f"\n== {e['id']}  ({repo})")
        try:
            info = get(f"https://huggingface.co/api/models/{repo}")
            tree = get(f"https://huggingface.co/api/models/{repo}/tree/main")
        except Exception as exc:  # noqa: BLE001
            print(f"  FAIL repository unreachable: {exc}")
            failures += 1
            continue

        if info.get("gated"):
            print(f"  FAIL repository is gated ({info.get('gated')}); not downloadable anonymously")
            failures += 1

        files = {t["path"]: t for t in tree if t.get("type") == "file"}
        if discover:
            for path, t in sorted(files.items()):
                if path.endswith(".gguf"):
                    lfs = t.get("lfs") or {}
                    print(f"  file {path} size={lfs.get('size', t.get('size'))} sha256={lfs.get('oid')}")

        t = files.get(name)
        if t is None:
            print(f"  FAIL file not found: {name}")
            failures += 1
            continue
        lfs = t.get("lfs") or {}
        size, sha = lfs.get("size", t.get("size")), lfs.get("oid")
        if e.get("sizeBytes") != size:
            print(f"  FAIL sizeBytes {e.get('sizeBytes')} != hub {size}")
            failures += 1
        if e.get("sha256") != sha:
            print(f"  FAIL sha256 {e.get('sha256')} != hub {sha}")
            failures += 1
        if e.get("sizeBytes") == size and e.get("sha256") == sha:
            print(f"  OK {name} size={size}")

    print(f"\n{len(entries)} entries, {failures} problem(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
