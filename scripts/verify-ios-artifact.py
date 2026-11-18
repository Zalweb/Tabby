"""Recheck the private iOS build artifact before paired public publication."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import zipfile


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_ipa(ipa_path, report_path, source_path, android_manifest_path, commit):
    ipa_path = Path(ipa_path)
    report_path = Path(report_path)
    source_path = Path(source_path)
    android_manifest_path = Path(android_manifest_path)
    commit = commit.lower()
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Candidate source commit must be a full Git SHA")
    if ipa_path.name != "Tabby.ipa" or not ipa_path.is_file():
        raise ValueError("Expected the packaged Tabby.ipa artifact")
    if not report_path.is_file() or not source_path.is_file() or not android_manifest_path.is_file():
        raise ValueError("The IPA packaging report, source manifest and Android candidate manifest are required")

    report = json.loads(report_path.read_text())
    source = json.loads(source_path.read_text())
    android = json.loads(android_manifest_path.read_text())
    version_name = android.get("version_name")
    version_code = android.get("version_code")
    if not isinstance(version_name, str) or not isinstance(version_code, int):
        raise ValueError("The Android candidate manifest has no shared version")
    if android.get("commit", "").lower() != commit:
        raise ValueError("The Android candidate manifest belongs to a different source commit")
    digest = sha256(ipa_path)
    if report.get("source_commit", "").lower() != commit or source.get("source_commit", "").lower() != commit:
        raise ValueError("The iOS artifact, packaging report and source manifest must match the build commit")
    if report.get("ipa") != ipa_path.name or report.get("ipa_sha256") != digest:
        raise ValueError("The iOS packaging report does not match the IPA bytes")
    if report.get("package_identifier") != "com.zalweb.tabby" or report.get("bundle_id") != "com.zalweb.tabby":
        raise ValueError("Unexpected iOS package identifier")
    if report.get("version_name") != version_name or str(report.get("build_number")) != str(version_code):
        raise ValueError("The iOS version does not match the Android candidate")
    if str(report.get("version_code")) != str(version_code) or not report.get("unsigned"):
        raise ValueError("The iOS build number or unsigned status is invalid")
    if "arm64" not in report.get("architectures", []):
        raise ValueError("The iOS package report does not confirm arm64")
    files = source.get("files")
    if (not isinstance(files, dict) or not files or report.get("source_file_count") != len(files)
            or any(not isinstance(name, str) or not name or not re.fullmatch(r"[a-fA-F0-9]{64}", str(value))
                   for name, value in files.items())):
        raise ValueError("The iOS package report is missing its tracked source manifest")
    smoke = report.get("simulator_native_smoke")
    if not isinstance(smoke, dict) or smoke.get("outcome") != "passed" or not isinstance(smoke.get("run_id"), int) or smoke["run_id"] < 1:
        raise ValueError("The iOS build has no passed, run-linked simulator evidence")
    if smoke.get("mode") == "actual simulator checks":
        if smoke.get("source_commit", "").lower() != commit:
            raise ValueError("Current simulator evidence must match the exact build commit")
    elif smoke.get("mode") == "reused exact native app inputs":
        if (not re.fullmatch(r"[a-fA-F0-9]{40}", str(smoke.get("source_commit", "")))
                or not isinstance(smoke.get("matching_input_hashes"), int)
                or smoke["matching_input_hashes"] < 1):
            raise ValueError("Reused simulator evidence must identify its verified source and matching inputs")
    else:
        raise ValueError("iOS simulator smoke evidence must describe actual or exact-input reuse")

    with zipfile.ZipFile(ipa_path) as archive:
        if archive.testzip() is not None:
            raise ValueError("The IPA archive failed its CRC check")
        names = archive.namelist()
        info_name = "Payload/Runner.app/Info.plist"
        executable_name = "Payload/Runner.app/Runner"
        if info_name not in names or executable_name not in names:
            raise ValueError("The IPA does not contain a packaged Runner.app")
        if any(name.endswith((".mobileprovision", ".p12", ".pfx", ".key")) or name.endswith("/.env") for name in names):
            raise ValueError("The unsigned IPA contains unexpected signing or environment material")
        info = plistlib.loads(archive.read(info_name))
        if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), str(info.get("CFBundleVersion"))) != (
            "com.zalweb.tabby", version_name, str(version_code)
        ):
            raise ValueError("The packaged iOS bundle identity/version differs from the candidate")

    return {"commit": commit, "ipa_sha256": digest, "version": f"{version_name}+{version_code}", "package_identifier": "com.zalweb.tabby"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--source-manifest", required=True)
    parser.add_argument("--android-manifest", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    result = verify_ipa(args.ipa, args.report, args.source_manifest, args.android_manifest, args.commit)
    print(f"IOS_ARTIFACT_OK: {result['version']} {result['ipa_sha256']}; unsigned ARM64 package report and source commit match.")


if __name__ == "__main__":
    main()
