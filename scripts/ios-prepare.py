"""Prepare an exact iOS candidate; print no client configuration values."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
from urllib.parse import urlparse


def validate_client(config):
    required = {"SUPABASE_URL", "SUPABASE_ANON_KEY", "GOOGLE_IOS_CLIENT_ID", "GOOGLE_WEB_CLIENT_ID"}
    if set(config) != required or any(not isinstance(v, str) or not v.strip() for v in config.values()):
        raise ValueError("Exactly four nonempty public client fields are required")
    parsed = urlparse(config["SUPABASE_URL"])
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("An HTTPS Supabase client URL without credentials is required")
    key = config["SUPABASE_ANON_KEY"]
    if key.startswith("sb_secret_"):
        raise ValueError("Server secrets cannot be compiled into the client")
    if key.count(".") == 2:
        payload = json.loads(base64.urlsafe_b64decode(key.split(".")[1] + "=="))
        if payload.get("role") != "anon":
            raise ValueError("Only an anon-role client key is allowed")
    elif not key.startswith("sb_publishable_"):
        raise ValueError("Expected a publishable or anon-role client key")
    for field in ["GOOGLE_IOS_CLIENT_ID", "GOOGLE_WEB_CLIENT_ID"]:
        if not re.fullmatch(r"[0-9]+-[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com", config[field]):
            raise ValueError("Invalid public Google client identifier")
    return config


def patch_plist(plist, client_id):
    url_types = plist.setdefault("CFBundleURLTypes", [])
    google_entry = next((entry for entry in url_types if entry.get("CFBundleURLName") == "google"), None)
    if google_entry is None:
        google_entry = {"CFBundleURLName": "google"}
        url_types.append(google_entry)
    google_entry.update({"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": [".".join(reversed(client_id.split(".")))]})
    supabase_entry = next((entry for entry in url_types if entry.get("CFBundleURLName") == "supabase"), None)
    if supabase_entry is None:
        supabase_entry = {"CFBundleTypeRole": "Editor", "CFBundleURLName": "supabase", "CFBundleURLSchemes": []}
        url_types.append(supabase_entry)
    if "io.supabase.tabby" not in supabase_entry.setdefault("CFBundleURLSchemes", []):
        supabase_entry["CFBundleURLSchemes"].append("io.supabase.tabby")
    plist["GIDClientID"] = client_id
    plist["FlutterDeepLinkingEnabled"] = False
    return plist


def pubspec_version(root):
    text = (root / "pubspec.yaml").read_text()
    match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]{0,8})\s*$", text, re.M)
    if not match:
        raise ValueError("pubspec.yaml must define a semantic version and positive build number")
    return match.group(1), int(match.group(2))


def resolve_build_number(root, requested, require_pubspec=False):
    version_name, shared_number = pubspec_version(root)
    if requested == 0:
        return version_name, shared_number
    if requested < 1 or requested > 999999999:
        raise ValueError("Build number must be a positive bounded integer")
    if require_pubspec and requested != shared_number:
        raise ValueError("Production iOS build number must match pubspec.yaml")
    return version_name, requested


def generate_current_manifest(root, expected_commit=None):
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip().lower()
    if not re.fullmatch(r"[a-f0-9]{40}", commit) or (expected_commit and commit != expected_commit.lower()):
        raise ValueError("Current iOS source must match the exact checked-out GitHub commit")
    dirty = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=root, text=True)
    if dirty.strip():
        raise ValueError("Current iOS source checkout must be clean before generating its manifest")

    entries = subprocess.check_output(["git", "ls-files", "-z"], cwd=root)
    files = {}
    for raw_name in entries.split(b"\0"):
        if not raw_name:
            continue
        name = raw_name.decode("utf-8")
        if name == "ios/build-source-manifest.json":
            continue
        target = (root / name).resolve()
        if not target.is_relative_to(root) or not target.is_file():
            raise ValueError("Tracked iOS source input is missing or escapes the checkout: " + name)
        files[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    if not files:
        raise ValueError("No tracked source files were found for the iOS manifest")
    return {"schema": 1, "source_commit": commit, "android_baseline": commit, "files": files}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-source", action="store_true")
    parser.add_argument("--verify-current-source", action="store_true")
    parser.add_argument("--source-output")
    parser.add_argument("--expected-commit")
    parser.add_argument("--resolve-build-number", type=int)
    parser.add_argument("--require-pubspec-version", action="store_true")
    parser.add_argument("--client-output")
    args = parser.parse_args()
    root = Path.cwd().resolve()
    manifest = json.loads((root / "ios/build-source-manifest.json").read_text())
    if args.verify_source:
        for name, expected in manifest["files"].items():
            target = (root / name).resolve()
            if not target.is_relative_to(root) or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
                raise ValueError("Candidate source does not match its frozen manifest: " + name)
        print("Frozen source hashes verified:", len(manifest["files"]))
        return
    if args.verify_current_source:
        if not args.source_output:
            parser.error("--verify-current-source requires --source-output")
        output = Path(args.source_output).resolve()
        if output.is_relative_to(root):
            raise ValueError("Generated iOS source manifest must stay outside the checkout")
        current = generate_current_manifest(root, args.expected_commit)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(current, indent=2) + "\n")
        print("Current tracked source manifest generated:", len(current["files"]), "files at", current["source_commit"])
        return
    if args.resolve_build_number is not None:
        version_name, build_number = resolve_build_number(root, args.resolve_build_number, args.require_pubspec_version)
        print(f"{version_name}+{build_number}")
        return
    if not args.client_output:
        parser.error("--client-output or --verify-source is required")
    config = validate_client(json.loads(os.environ["TABBY_IOS_BUILD_CONFIG"]))
    expected = json.loads((root / "ios/client-config-hashes.json").read_text())
    if {k: hashlib.sha256(v.encode()).hexdigest() for k, v in config.items()} != expected:
        raise ValueError("Client configuration differs from the reviewed Android/backend candidate")
    output = Path(args.client_output).resolve()
    if output.is_relative_to(root):
        raise ValueError("Client config must stay outside the source/artifact tree")
    output.write_text(json.dumps(config))
    output.chmod(0o600)
    target = root / "ios/Runner/Info.plist"
    with target.open("rb") as handle:
        plist = plistlib.load(handle)
    with target.open("wb") as handle:
        plistlib.dump(patch_plist(plist, config["GOOGLE_IOS_CLIENT_ID"]), handle, sort_keys=False)
    print("Public client hashes and native OAuth callback ownership verified")


if __name__ == "__main__":
    main()
