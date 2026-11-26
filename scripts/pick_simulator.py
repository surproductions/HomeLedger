#!/usr/bin/env python3
"""Print the UDID of the best available iPhone simulator (newest iOS runtime, preferring an iPhone 16/15 model)."""
import json
import re
import subprocess
import sys

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
candidates = []
for runtime, devices in data["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        name = d["name"]
        if not name.startswith("iPhone"):
            continue
        preference = 0
        if re.fullmatch(r"iPhone \d+ Pro", name):
            preference = 3
        elif re.fullmatch(r"iPhone \d+", name):
            preference = 2
        candidates.append((version, preference, name, d["udid"]))

if not candidates:
    sys.exit("No iPhone simulator available")
candidates.sort()
version, _, name, udid = candidates[-1]
print(f"{name} iOS {version[0]}.{version[1]}", file=sys.stderr)
print(udid)
