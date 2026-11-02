#!/usr/bin/env python3
"""更新官网首页里“在线资源更新仍在筹备”的过时表述（联网版已上线）。

只在命中时改写，改写前备份；index.txt（RSC payload）与 index.html（SSR 输出）
同步替换，避免水合前后文案不一致。
"""
import shutil
import time

OLD = "以本地星图和随应用打包的资料为基础。在线资源更新仍在筹备，不把尚未上线的服务当作现有能力。"
NEW = "以本地星图和随应用打包的资料为基础；卫星星历与星表可在联网时更新，也可全程离线使用。"

BASE = "/srv/skyinstrument/website/current/"
stamp = time.strftime("%Y%m%d%H%M%S")

for name in ("index.txt", "index.html"):
    path = BASE + name
    try:
        text = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        print(f"skip {name}: not found")
        continue
    if OLD not in text:
        print(f"skip {name}: phrase not present")
        continue
    shutil.copy2(path, path + ".bak-" + stamp)
    open(path, "w", encoding="utf-8").write(text.replace(OLD, NEW))
    print(f"patched {name} (backup {name}.bak-{stamp})")
