"""Prepare an exact iOS candidate; print no client configuration values."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-source", action="store_true")
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
