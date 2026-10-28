#!/usr/bin/env python3
"""Choose one iPhone and one iPad from `simctl list devices available -j`.

Prints GITHUB_ENV lines: IPHONE_UDID, IPHONE_NAME, IPAD_UDID, IPAD_NAME.
Prefers the newest numbered iPhone Pro and the newest iPad Pro.
"""
import json
import re
import sys

data = json.load(open(sys.argv[1]))
devices = []
for runtime, devs in data["devices"].items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in re.findall(r"\d+", runtime.split("iOS")[-1])[:2] or (0,))
    for dev in devs:
        if dev.get("isAvailable", True):
            devices.append((version, dev["name"], dev["udid"]))


def pick(pattern, fallback):
    matches = [d for d in devices if re.search(pattern, d[1])]
    if not matches:
        matches = [d for d in devices if re.search(fallback, d[1])]
    if not matches:
        return None

    def key(d):
        number = re.findall(r"\d+", d[1])
        return (d[0], int(number[0]) if number else 0, d[1])

    return sorted(matches, key=key)[-1]


iphone = pick(r"^iPhone \d+ Pro$", r"^iPhone")
ipad = pick(r"^iPad Pro", r"^iPad")
if not iphone:
    sys.exit("No iPhone simulator available")
print(f"IPHONE_UDID={iphone[2]}")
print(f"IPHONE_NAME={iphone[1]}")
print(f"IPAD_UDID={ipad[2] if ipad else ''}")
print(f"IPAD_NAME={ipad[1] if ipad else ''}")
