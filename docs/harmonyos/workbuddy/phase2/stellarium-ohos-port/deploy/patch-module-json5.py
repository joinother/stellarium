#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch-module-json5.py — Stellarium 鸿蒙工程 module.json5 自动补丁脚本

用途：
  在运行 ohos-build-stellarium.sh 生成 DevEco 工程（build/libstellarium-harmonyos）之后，
  由主构建脚本自动调用；也可手动执行，确保工程声明三端设备类型与必要权限。

行为：
  1. 参数可以是 module.json5 的具体文件路径，也可以是包含它的目录（脚本用 os.walk 查找）。
  2. 备份原文件为 module.json5.bak，再写回。
  3. 做以下修改（不存在则新增）：
     - deviceTypes 合并去重为 ["phone","tablet","2in1"]
     - requestPermissions 合并去重加入三个权限（ACCELEROMETER / GYROSCOPE / INTERNET）
     - module 顶层确保 "name":"entry"，保留已有 srcEntry
     - 若 abilities 数组存在，确保每个 ability 的 deviceTypes 也覆盖三端
  4. 打印修改摘要；找不到文件或 JSON 解析失败则打印清晰错误并 exit 1。

用法：
  python3 patch-module-json5.py <path-to-module.json5 或 目录>
"""

import json
import os
import shutil
import subprocess
import sys

TARGET_DEVICE_TYPES = ["phone", "tablet", "2in1"]
TARGET_PERMISSIONS = [
    "ohos.permission.ACCELEROMETER",
    "ohos.permission.GYROSCOPE",
    "ohos.permission.INTERNET",
]


def find_module_json5(target):
    """若 target 是文件直接返回；若是目录用 os.walk 找第一个 module.json5。"""
    if os.path.isfile(target):
        return target
    if os.path.isdir(target):
        candidates = []
        for root, _dirs, files in os.walk(target):
            for f in files:
                if f == "module.json5":
                    candidates.append(os.path.join(root, f))
        main_candidates = [
            p for p in candidates
            if os.sep + "src" + os.sep + "main" + os.sep in p
        ]
        if main_candidates:
            return sorted(main_candidates)[0]
        if candidates:
            return sorted(candidates)[0]
        raise FileNotFoundError(
            "在目录中未找到 module.json5: %s" % target
        )
    raise FileNotFoundError("路径既不存在也不是文件/目录: %s" % target)


def merge_unique(base, additions):
    """保留 base 原有顺序，去重后追加 additions 中缺失的项。"""
    result = []
    seen = set()
    for item in (base or []):
        if item not in seen:
            result.append(item)
            seen.add(item)
    for item in additions:
        if item not in seen:
            result.append(item)
            seen.add(item)
    return result


def load_json5(path):
    """优先用 DevEco 自带的 JSON5 解析器，兼容注释、单引号和尾逗号。"""
    node = shutil.which("node")
    if not node:
        candidate = "/Applications/DevEco-Studio.app/Contents/tools/node/bin/node"
        if os.path.isfile(candidate):
            node = candidate
    module = os.environ.get(
        "JSON5_MODULE",
        "/Applications/DevEco-Studio.app/Contents/tools/"
        "hvigor/hvigor-ohos-plugin/node_modules/json5",
    )
    if node and os.path.isdir(module):
        script = (
            "const fs=require('fs');"
            "const JSON5=require(process.argv[1]);"
            "const p=process.argv[2];"
            "process.stdout.write(JSON.stringify(JSON5.parse(fs.readFileSync(p,'utf8'))));"
        )
        result = subprocess.run(
            [node, "-e", script, module, path],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        raise ValueError(result.stderr.strip() or "JSON5 解析失败")
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main():
    if len(sys.argv) != 2:
        print("用法: python3 patch-module-json5.py <module.json5 路径 或 目录>")
        sys.exit(1)

    arg = sys.argv[1]
    try:
        path = find_module_json5(arg)
    except FileNotFoundError as e:
        print("错误: %s" % e)
        sys.exit(1)

    print("目标文件: %s" % path)

    try:
        data = load_json5(path)
    except json.JSONDecodeError as e:
        print("错误: JSON 解析失败 (%s): %s" % (path, e))
        sys.exit(1)
    except OSError as e:
        print("错误: 无法读取文件 %s: %s" % (path, e))
        sys.exit(1)

    # 规范化顶层：module.json5 可能是 {"module": {...}} 或扁平结构
    if "module" in data and isinstance(data["module"], dict):
        root = data["module"]
        is_wrapped = True
    else:
        root = data
        is_wrapped = False

    changes = []

    # 1) deviceTypes
    old_dt = root.get("deviceTypes")
    new_dt = merge_unique(old_dt, TARGET_DEVICE_TYPES)
    if new_dt != old_dt:
        root["deviceTypes"] = new_dt
        changes.append("deviceTypes -> %s" % new_dt)

    # 2) requestPermissions（去重，保留 name/reason/usedScene 等已有字段）
    existing_perms = root.get("requestPermissions")
    existing_names = []
    if isinstance(existing_perms, list):
        for p in existing_perms:
            if isinstance(p, dict) and "name" in p:
                existing_names.append(p["name"])

    need_add = [p for p in TARGET_PERMISSIONS if p not in existing_names]
    if need_add:
        if not isinstance(root.get("requestPermissions"), list):
            root["requestPermissions"] = []
        for perm in need_add:
            root["requestPermissions"].append({
                "name": perm,
                "reason": "$string:app_name",
                "usedScene": ["available", "ability", "want"],
            })
        changes.append("requestPermissions 新增 -> %s" % need_add)
    elif existing_names:
        # 已存在则保持，仅记录
        changes.append("requestPermissions 已含 %d 项(未改动)" % len(existing_names))

    # 3) module 顶层 name / srcEntry
    if root.get("name") != "entry":
        root["name"] = "entry"
        changes.append("name -> entry")
    # srcEntry 若存在则保留，不主动新增（避免破坏未生成入口的工程）

    # 4) abilities 每项 deviceTypes 覆盖三端
    abilities = root.get("abilities")
    if isinstance(abilities, list):
        abil_changed = 0
        for ab in abilities:
            if not isinstance(ab, dict):
                continue
            ab_dt = ab.get("deviceTypes")
            new_ab_dt = merge_unique(ab_dt, TARGET_DEVICE_TYPES)
            if new_ab_dt != ab_dt:
                ab["deviceTypes"] = new_ab_dt
                abil_changed += 1
        if abil_changed:
            changes.append("abilities deviceTypes 覆盖三端 (%d 项更新)" % abil_changed)

    # 写回（先备份）
    backup = path + ".bak"
    try:
        with open(backup, "w", encoding="utf-8") as fh:
            json.dump(data if is_wrapped else root, fh, indent=2, ensure_ascii=False)
    except OSError as e:
        print("警告: 备份失败 %s: %s" % (backup, e))

    try:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data if is_wrapped else root, fh, indent=2, ensure_ascii=False)
    except OSError as e:
        print("错误: 写回失败 %s: %s" % (path, e))
        sys.exit(1)

    print("-" * 40)
    if changes:
        print("修改摘要:")
        for c in changes:
            print("  + %s" % c)
    else:
        print("无需修改（已满足三端配置）。")
    print("备份: %s" % backup)
    print("完成。")


if __name__ == "__main__":
    main()
