"""Inspect a real unsigned device archive and package it for user-side signing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import zipfile
from urllib.parse import quote


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_app(app, build_number, config, source, run=subprocess.run):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier"), str(info.get("CFBundleVersion")), info.get("CFBundleShortVersionString")) != ("com.zalweb.tabby", str(build_number), "1.0.4"):
        raise ValueError("Unexpected bundle identity/version")
    if info.get("CFBundleExecutable") != "Runner" or info.get("FlutterDeepLinkingEnabled") is not False:
        raise ValueError("Unexpected executable or OAuth callback owner")
    schemes = {s for entry in info.get("CFBundleURLTypes", []) for s in entry.get("CFBundleURLSchemes", [])}
    if "io.supabase.tabby" not in schemes or ".".join(reversed(config["GOOGLE_IOS_CLIENT_ID"].split("."))) not in schemes:
        raise ValueError("Missing native OAuth URL schemes")
    executable = app / "Runner"
    architectures = run(["lipo", "-archs", str(executable)], check=True, capture_output=True, text=True).stdout.split()
    if "arm64" not in architectures:
        raise ValueError("An arm64 iOS device executable is required")
    signature = run(["codesign", "-dv", str(app)], capture_output=True, text=True)
    if signature.returncode == 0:
        raise ValueError("Expected an unsigned root app for user-side signing")
    assets = app / "Frameworks/App.framework/flutter_assets"
    checked = 0
    for name, expected in source["files"].items():
        if name.startswith("assets/branding/"):
            if digest(assets / quote(name, safe="/")) != expected:
                raise ValueError("Bundled artwork differs from reviewed source: " + name)
            checked += 1
    if not checked:
        raise ValueError("No reviewed branding assets were verified")
    for target in app.rglob("*"):
        if target.name == ".env" or target.suffix.lower() in {".p12", ".pfx", ".key", ".mobileprovision"}:
            raise ValueError("Unexpected private/signing material in unsigned payload")
        if target.is_symlink() and not target.resolve().is_relative_to(app.resolve()):
            raise ValueError("Payload symlink escapes the application")
    return {"bundle_id": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"], "build_number": str(build_number), "architectures": architectures, "unsigned": True, "branding_assets_verified": checked, "flutter_callback_handler_disabled": True}


def package_app(app, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for target in sorted(app.rglob("*")):
            name = "Payload/Runner.app/" + target.relative_to(app).as_posix()
            if target.is_symlink():
                entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(target))
            elif target.is_file():
                entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                entry.create_system = 3
                mode = stat.S_IMODE(target.stat().st_mode)
                if target == app / "Runner":
                    mode |= 0o111
                entry.external_attr = (stat.S_IFREG | mode) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, target.read_bytes())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None or "Payload/Runner.app/Runner" not in archive.namelist():
            raise ValueError("IPA integrity or Payload layout is invalid")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--client-config", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[1-9][0-9]{0,8}", args.build_number):
        raise ValueError("Build number must be a positive bounded integer")
    source = json.loads(Path("ios/build-source-manifest.json").read_text())
    app = Path(args.archive) / "Products/Applications/Runner.app"
    output = Path(args.output)
    config = json.loads(Path(args.client_config).read_text())
    report = inspect_app(app, args.build_number, config, source)
    package_app(app, output)
    native_evidence = output.parent / "native-smoke-evidence.json"
    report.update({"ipa": output.name, "ipa_sha256": digest(output), "source_commit": os.environ.get("GITHUB_SHA"), "android_baseline": source["android_baseline"], "public_client_hashes": {k: hashlib.sha256(v.encode()).hexdigest() for k, v in config.items()}, "source_file_count": len(source["files"]), "simulator_native_smoke": json.loads(native_evidence.read_text()) if native_evidence.exists() else "Required preceding workflow step; see CI logs", "physical_iphone_verified": False})
    output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
    (output.parent / "README.txt").write_text("Tabby unsigned iOS sideload build\n\nSign/install this IPA with AltStore or Sideloadly using your own Apple account. It is not directly installable or a TestFlight/App Store release. Keep the same signing identity/bundle ID for upgrades. Changing bundle ID may require browser Google sign-in fallback.\n\nCore screens, debt/sync behavior and mascots share the recorded Android source. iOS adds QR export to Files/native share. Remote background push and damaged-storage recovery remain Android-only. Local iOS notifications, Face ID and wallet/Google journeys still need testing on your iPhone.\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
