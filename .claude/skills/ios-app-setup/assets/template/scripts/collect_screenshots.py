#!/usr/bin/env python3
"""Gather the UI test screenshots into docs/screenshots.

Two sources: PNGs the UI test wrote straight to SCREENSHOT_DIR, and attachments exported by
`xcresulttool export attachments`, which names files like `iPhone-02-feed_0_<UUID>.png`.
Only files that follow the test's `<device>-<nn>-<name>.png` naming are kept, and the
export suffix is stripped. Direct writes win when both exist.
"""
import json
import os
import re
import shutil
import sys

exported_root, direct_dir, out_dir = sys.argv[1:4]
os.makedirs(out_dir, exist_ok=True)
NAME = re.compile(r"^((?:iPhone|iPad)-\d{2}-[a-z0-9-]+)(?:_\d+_[0-9A-Fa-f-]+)?\.png$")
collected = {}


def clean(name):
    match = NAME.match(os.path.basename(name))
    return match.group(1) + ".png" if match else None


def walk(node, found):
    if isinstance(node, dict):
        name = node.get("suggestedHumanReadableName") or node.get("humanReadableName")
        file = node.get("exportedFileName") or node.get("fileName")
        if name and file:
            found.append((name, file))
        for value in node.values():
            walk(value, found)
    elif isinstance(node, list):
        for value in node:
            walk(value, found)


if os.path.isdir(exported_root):
    for bundle in sorted(os.listdir(exported_root)):
        folder = os.path.join(exported_root, bundle)
        manifest = os.path.join(folder, "manifest.json")
        found = []
        if os.path.isfile(manifest):
            walk(json.load(open(manifest)), found)
        else:
            found = [(f, f) for f in os.listdir(folder)] if os.path.isdir(folder) else []
        for name, file in found:
            target = clean(name) or clean(file)
            src = os.path.join(folder, file)
            if target and os.path.isfile(src):
                collected.setdefault(target, src)

if os.path.isdir(direct_dir):
    for file in os.listdir(direct_dir):
        target = clean(file)
        if target:
            collected[target] = os.path.join(direct_dir, file)

for name, src in sorted(collected.items()):
    shutil.copyfile(src, os.path.join(out_dir, name))
    print("collected", name)

if not collected:
    print("no screenshots found", file=sys.stderr)
