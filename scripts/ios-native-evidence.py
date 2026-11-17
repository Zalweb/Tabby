"""Reuse actual CI native proof only when every native app input is identical."""
import json
import os
import subprocess
from pathlib import Path
from urllib.request import Request, urlopen

REPO = "Zalweb/Tabby"


def native_inputs(files):
    return {name: digest for name, digest in files.items()
            if name.startswith(("lib/", "assets/", "ios/"))
            and name not in {"ios/build-source-manifest.json", "ios/native-smoke-evidence.json"}
            or name in {"pubspec.yaml", "pubspec.lock", "integration_test/ios_native_smoke_test.dart", "scripts/ios-prepare.py"}}


def get(url):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Tabby-iOS-build"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    with urlopen(Request(url, headers=headers), timeout=30) as response:
        return json.load(response)


def main():
    evidence_path = Path("ios/native-smoke-evidence.json")
    if not evidence_path.exists():
        print("No prior native evidence selected; run actual simulator checks")
        return
    evidence = json.loads(evidence_path.read_text())
    sdk = json.loads(subprocess.check_output(["flutter", "--version", "--machine"]))
    if sdk["frameworkRevision"] != evidence["flutter_framework_revision"]:
        print("Flutter SDK changed; run fresh actual simulator checks")
        return
    run_id, commit = evidence["run_id"], evidence["commit"]
    if not isinstance(run_id, int) or len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
        raise ValueError("Invalid native evidence reference")
    run = get(f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}")
    if run["head_sha"] != commit or run["status"] != "completed":
        raise ValueError("Prior native run/commit not completed")
    jobs = get(f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/jobs")
    required = "Check actual iOS channels, Keychain, encryption and images"
    if not any(step["name"] == required and step["conclusion"] == "success"
               for job in jobs["jobs"] for step in job["steps"]):
        raise ValueError("Prior native simulator step did not pass")
    blob = get(f"https://api.github.com/repos/{REPO}/contents/ios/build-source-manifest.json?ref={commit}")
    import base64
    previous = json.loads(base64.b64decode(blob["content"]))
    current = json.loads(Path("ios/build-source-manifest.json").read_text())
    inputs = native_inputs(current["files"])
    if inputs != native_inputs(previous["files"]):
        print("Native app inputs changed; run fresh actual simulator checks")
        return
    output = {"mode": "reused exact native app inputs", "run_id": run_id,
              "source_commit": commit, "url": run["html_url"], "cases": 3,
              "matching_input_hashes": len(inputs), "outcome": "passed",
              "scope": "QR native registration/invalid bytes; Keychain/encrypted SQLite persistence; mascot image decode/reduced motion"}
    Path("output").mkdir(exist_ok=True)
    Path("output/native-smoke-evidence.json").write_text(json.dumps(output, indent=2) + "\n")
    with open(os.environ["GITHUB_ENV"], "a") as handle:
        handle.write("IOS_NATIVE_SMOKE_REUSED=true\n")
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
