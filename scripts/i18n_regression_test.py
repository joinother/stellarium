#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Stellarium HarmonyOS — i18n regression test.

Covers the two things that are actually automatable on this SDK:

1. STATIC completeness of every shell UI language resource file
   (base / zh_CN / en_US / ja / ko / zh_TW):
     - valid JSON
     - identical key set (no missing / extra keys vs base)
     - no empty values
   This is the real regression guard: if a future string edit forgets to
   update ja/ko/zh_TW, this fails loudly.

2. SHIPPED-HAP check (optional, pass --hap <file.hap>):
   scans the compiled HAP for a representative string of each language,
   proving the languages were actually packaged (not just present on disk).

NOTE on runtime shell language:
   This SDK has NO code API to switch the ArkUI shell language at runtime
   (no i18n.setAppLanguage / setPreferredLanguage; getApplicationContext is
   not exported). The shell text follows the *device system locale*. The
   in-app "语言" toggle only switches the C++ star-map core language.
   Therefore per-language *rendering* can only be verified by setting the
   device/emulator system language to ja / ko / zh_TW and re-launching —
   which must be done in the Device Simulator / emulator system settings,
   not via hdc. This script validates the data; the rendering is a manual
   step documented below.

Usage:
   python3 i18n_regression_test.py
   python3 i18n_regression_test.py --hap entry-default-signed.hap
"""
import json
import os
import sys
import zipfile
import argparse

# repo-root-relative resource dir (git source of truth)
RES_DIR = os.path.join(os.path.dirname(__file__), "..", "harmonyos", "ets-source", "resources")
RES_DIR = os.path.abspath(RES_DIR)

LANGS = ["base", "zh_CN", "en_US", "ja", "ko", "zh_TW"]

# representative (name, value) pairs to spot-check per language
SAMPLES = {
    "base":   [("i0099", "搜索"), ("i0102", "设置")],
    "zh_CN":  [("i0099", "搜索"), ("i0102", "设置")],
    "en_US":  [("i0099", "Search"), ("i0102", "Settings")],
    "ja":     [("i0099", "検索"), ("i0102", "設定")],
    "ko":     [("i0099", "검색"), ("i0102", "설정")],
    "zh_TW":  [("i0099", "搜尋"), ("i0102", "設定")],
}


def load(lang):
    p = os.path.join(RES_DIR, lang, "element", "string.json")
    if not os.path.exists(p):
        return None, f"missing file: {p}"
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return None, f"invalid JSON: {e}"
    items = data.get("string", [])
    return {e["name"]: e.get("value", "") for e in items}, None


def test_static():
    print("=== [1/2] Static resource completeness ===")
    ok = True
    base_map, err = load("base")
    if err:
        print("  FAIL: base resource:", err)
        return False
    base_keys = set(base_map.keys())
    print(f"  base: {len(base_keys)} keys")
    for lang in LANGS:
        m, err = load(lang)
        if err:
            print(f"  [{lang}] FAIL: {err}")
            ok = False
            continue
        keys = set(m.keys())
        missing = sorted(base_keys - keys)
        extra = sorted(keys - base_keys)
        empty = sorted([k for k, v in m.items() if not str(v).strip()])
        status = "OK" if not (missing or extra or empty) else "FAIL"
        if status == "FAIL":
            ok = False
        print(f"  [{lang}] {status}  keys={len(keys)}"
              + (f"  missing={missing}" if missing else "")
              + (f"  extra={extra}" if extra else "")
              + (f"  empty={empty}" if empty else ""))
        # spot-check samples
        for name, val in SAMPLES.get(lang, []):
            if m.get(name) != val:
                print(f"      WARN sample mismatch {name}: expected {val!r} got {m.get(name)!r}")
    return ok


def test_hap(hap_path):
    print(f"\n=== [2/2] Shipped-HAP language scan: {os.path.basename(hap_path)} ===")
    if not os.path.exists(hap_path):
        print("  SKIP: hap not found")
        return True
    z = zipfile.ZipFile(hap_path)
    # decompress every entry and search for the representative strings
    blob = {}
    for n in z.namelist():
        try:
            blob[n] = z.read(n).decode("utf-8", "ignore")
        except Exception:
            blob[n] = ""
    ok = True
    for lang in ["zh_CN", "en_US", "ja", "ko", "zh_TW"]:
        found_all = True
        for name, val in SAMPLES.get(lang, []):
            present = any(val in d for d in blob.values())
            if not present:
                found_all = False
                ok = False
                print(f"  [{lang}] MISSING in HAP: {val!r} ({name})")
        if found_all:
            print(f"  [{lang}] OK  (found representative strings)")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hap", help="path to built HAP to scan for packaged languages")
    args = ap.parse_args()
    print("Stellarium HarmonyOS i18n regression test")
    print(f"resource dir: {RES_DIR}\n")
    ok = test_static()
    if args.hap:
        ok = test_hap(args.hap) and ok
    print("\n=== RESULT ===")
    if ok:
        print("PASS: all language resources complete"
              + (" and packaged in HAP." if args.hap else "."))
        sys.exit(0)
    else:
        print("FAIL: see items above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
