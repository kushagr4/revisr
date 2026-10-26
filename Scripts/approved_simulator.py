#!/usr/bin/env python3
"""Print the UDID of an approved Revisr test simulator (iPhone 13 or newer, never an iPad).

Testing policy (docs/IOS_TESTING_POLICY.md): reuse the dedicated Revisr test devices; never
create a simulator per scenario; never test on iPads or on iPhone 12 and older.

  python3 Scripts/approved_simulator.py            standard device (default "Revisr Flexible TMUA QA")
  python3 Scripts/approved_simulator.py --large    larger device   (default "Revisr R1 Pro Max QA")

Use the result as the only destination:
  xcodebuild test ... -destination "platform=iOS Simulator,id=$(python3 Scripts/approved_simulator.py)"
"""
import json
import re
import subprocess
import sys

PREFERRED = {"standard": "Revisr Flexible TMUA QA", "large": "Revisr R1 Pro Max QA"}
# iPhone 13 family and newer, including e, Air, mini, Plus and Pro models. iPhone SE and iPads are excluded.
APPROVED = re.compile(r"\.iPhone-(1[3-9]|[2-9][0-9])(e|-|$)|\.iPhone-Air(-|$)")
LARGE = re.compile(r"(Pro-Max|Plus|iPhone-Air)")


def approved(device_type):
    return bool(APPROVED.search(device_type)) and "iPad" not in device_type and "iPhone-SE" not in device_type


def main():
    size = "large" if "--large" in sys.argv else "standard"
    listing = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                                        check=True, capture_output=True, text=True).stdout)
    devices = [device for group in listing["devices"].values() for device in group]
    candidates = [device for device in devices if approved(device["deviceTypeIdentifier"])]
    for device in candidates:
        if device["name"] == PREFERRED[size]:
            print(device["udid"])
            return
    fallback = [device for device in candidates if bool(LARGE.search(device["deviceTypeIdentifier"])) == (size == "large")]
    if fallback:
        sys.stderr.write("note: preferred device %r not found; using existing %r (no new simulator created)\n"
                         % (PREFERRED[size], fallback[0]["name"]))
        print(fallback[0]["udid"])
        return
    sys.stderr.write("error: no approved iPhone 13+ simulator available; ask before creating one\n")
    raise SystemExit(1)


if __name__ == "__main__":
    main()
