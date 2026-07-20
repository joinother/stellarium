#!/usr/bin/env python3
"""Extract non-empty text nodes and clickable nodes from an OHOS uitest dumpLayout JSON.

Usage: extract_layout.py <layout.json> [--clickable] [--bounds]
Prints one line per matching node:
  text | bounds | clickable | type
"""
import json
import sys

def walk(node, out):
    if not isinstance(node, dict):
        return
    a = node.get("attributes", {}) or {}
    text = a.get("text") or a.get("originalText") or ""
    text = text.strip()
    clickable = (a.get("clickable") == "true")
    bounds = a.get("bounds") or ""
    out.append((text, bounds, clickable, a.get("type") or ""))
    for c in node.get("children", []) or []:
        walk(c, out)

def main():
    path = sys.argv[1]
    only_clickable = "--clickable" in sys.argv
    with open(path) as f:
        data = json.load(f)
    out = []
    walk(data, out)
    texts = []
    clicks = []
    for text, bounds, clickable, typ in out:
        if text:
            texts.append((text, bounds, clickable, typ))
        if clickable and (text or bounds):
            clicks.append((text, bounds, clickable, typ))
    print("=== NON-EMPTY TEXT NODES (%d) ===" % len(texts))
    # Deduplicate while preserving order
    seen = set()
    for text, bounds, clickable, typ in texts:
        key = (text, bounds)
        if key in seen:
            continue
        seen.add(key)
        print(f"  {text!r:40} | {bounds:18} | click={clickable} | {typ}")
    if only_clickable:
        print("\n=== CLICKABLE NODES (%d) ===" % len(clicks))
        seen2 = set()
        for text, bounds, clickable, typ in clicks:
            key = (text, bounds)
            if key in seen2:
                continue
            seen2.add(key)
            print(f"  {text!r:30} | {bounds:18} | {typ}")

if __name__ == "__main__":
    main()
