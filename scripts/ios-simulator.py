"""Boot one disposable CI simulator; never select a real user's device."""
import json
import os
import subprocess

if os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("This simulator helper is limited to a disposable GitHub runner")
inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
device = next((d for runtime, devices in inventory["devices"].items() if ".iOS-" in runtime
               for d in devices if d.get("isAvailable") and "iPhone" in d["name"]), None)
if device is None:
    raise SystemExit("No available iPhone simulator runtime")
if device["state"] != "Booted":
    subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True)
subprocess.run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], check=True)
with open(os.environ["GITHUB_ENV"], "a") as handle:
    handle.write("IOS_SIMULATOR_UDID=" + device["udid"] + "\n")
print("Owned disposable simulator ready:", device["name"])
