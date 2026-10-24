#!/usr/bin/env python3
"""Gather screenshots into docs/screenshots.

Two sources: PNGs the UI test wrote straight to SCREENSHOT_DIR, and attachments exported by
`xcresulttool export attachments`, whose manifest maps opaque file names to the names the test
gave them. Direct writes win when both exist.
"""
import json
import os
import shutil
import sys

exported_root, direct_dir, out_dir = sys.argv[1:4]
os.makedirs(out_dir, exist_ok=True)
collected = {}


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
    for bundle in os.listdir(exported_root):
        folder = os.path.join(exported_root, bundle)
        manifest = os.path.join(folder, "manifest.json")
        if not os.path.isfile(manifest):
            continue
        found = []
        walk(json.load(open(manifest)), found)
        for name, file in found:
            src = os.path.join(folder, file)
            if not os.path.isfile(src) or not name.lower().endswith(".png"):
                if os.path.isfile(src) and not name.lower().endswith(".png"):
                    name = name + ".png"
                else:
                    continue
            collected.setdefault(os.path.basename(name), src)

if os.path.isdir(direct_dir):
    for file in os.listdir(direct_dir):
        if file.lower().endswith(".png"):
            collected[file] = os.path.join(direct_dir, file)

for name, src in sorted(collected.items()):
    shutil.copyfile(src, os.path.join(out_dir, name))
    print("collected", name)

if not collected:
    print("no screenshots found", file=sys.stderr)
