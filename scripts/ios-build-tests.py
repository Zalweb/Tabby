"""Synthetic contract checks; these never claim Xcode or iPhone acceptance."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
import zipfile


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), Path(__file__).with_name(name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


prepare = module("ios-prepare")
package = module("ios-package")
native = module("ios-native-evidence")
artifact = module("verify-ios-artifact")
CLIENT = {"SUPABASE_URL": "https://synthetic.invalid", "SUPABASE_ANON_KEY": "sb_publishable_synthetic", "GOOGLE_IOS_CLIENT_ID": "123-ios.apps.googleusercontent.com", "GOOGLE_WEB_CLIENT_ID": "123-web.apps.googleusercontent.com"}


class ClientTests(unittest.TestCase):
    def test_native_reuse_changes_for_app_inputs_but_not_packaging_or_documentation(self):
        inputs = {"lib/main.dart": "a", "ios/Runner/AppDelegate.swift": "b",
                  "pubspec.lock": "c", "integration_test/ios_native_smoke_test.dart": "d",
                  "scripts/ios-prepare.py": "e", "assets/branding/mascot.png": "f"}
        extras = {"scripts/ios-package.py": "x", "docs/report.md": "y",
                  "ios/build-source-manifest.json": "z", "ios/native-smoke-evidence.json": "z"}
        self.assertEqual(native.native_inputs({**inputs, **extras}), inputs)
        self.assertNotEqual(native.native_inputs({**inputs, "lib/main.dart": "changed"}), inputs)
    def test_current_manifest_is_tied_to_clean_exact_tracked_git_checkout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "ios").mkdir()
            (root / "lib").mkdir()
            (root / "pubspec.yaml").write_text("version: 1.0.4+25\n")
            (root / "ios/build-source-manifest.json").write_text("{}\n")
            (root / "lib/main.dart").write_text("tracked source\n")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Synthetic Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "synthetic@example.invalid"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)
            commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
            manifest = prepare.generate_current_manifest(root, commit)
            self.assertEqual(manifest["source_commit"], commit)
            self.assertEqual(set(manifest["files"]), {"pubspec.yaml", "lib/main.dart"})
            with self.assertRaisesRegex(ValueError, "exact checked-out GitHub commit"):
                prepare.generate_current_manifest(root, "0" * 40)
    def test_public_fields_validate_without_server_credentials(self):
        self.assertEqual(prepare.validate_client(CLIENT), CLIENT)
        for patch in [{"SUPABASE_ANON_KEY": "sb_secret_synthetic"}, {"SUPABASE_URL": "http://synthetic.invalid"}, {"SUPABASE_URL": "https://name:password@synthetic.invalid"}, {"GOOGLE_IOS_CLIENT_ID": "not-a-client"}, {"SERVICE_ROLE_KEY": "forbidden"}]:
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                prepare.validate_client({**CLIENT, **patch})

    def test_oauth_patch_is_idempotent_and_preserves_unrelated_callback(self):
        plist = {"CFBundleURLTypes": [{"CFBundleURLName": "other", "CFBundleURLSchemes": ["unrelated"]}]}
        first = prepare.patch_plist(plist, CLIENT["GOOGLE_IOS_CLIENT_ID"])
        second = prepare.patch_plist(copy.deepcopy(first), CLIENT["GOOGLE_IOS_CLIENT_ID"])
        self.assertEqual(first, second)
        self.assertFalse(second["FlutterDeepLinkingEnabled"])
        self.assertEqual(len(second["CFBundleURLTypes"]), 3)
        self.assertEqual(second["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["unrelated"])


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Runner.app"
        self.app.mkdir()
        self.info = prepare.patch_plist({"CFBundleIdentifier": "com.zalweb.tabby", "CFBundleVersion": "23", "CFBundleShortVersionString": "1.0.4", "CFBundleExecutable": "Runner"}, CLIENT["GOOGLE_IOS_CLIENT_ID"])
        self.write_info()
        executable = self.app / "Runner"
        executable.write_bytes(b"synthetic-fixture-not-an-actual-Mach-O")
        executable.chmod(0o755)
        image = self.app / "Frameworks/App.framework/flutter_assets/assets/branding/mascot/synthetic.png"
        image.parent.mkdir(parents=True)
        image.write_bytes(b"synthetic-branding-fixture")
        self.image = image
        self.source = {"files": {"assets/branding/mascot/synthetic.png": package.digest(image)}}

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    @staticmethod
    def fake_apple_tool(args, **kwargs):
        # Explicit fake tool results test guards, not native build validity.
        return SimpleNamespace(stdout="arm64\n" if args[0] == "lipo" else "", returncode=0 if args[0] == "lipo" else 1)

    def inspect(self):
        return package.inspect_app(self.app, "23", CLIENT, self.source, self.fake_apple_tool)

    def test_accepts_expected_unsigned_identity_and_asset_hash(self):
        self.assertTrue(self.inspect()["unsigned"])
        self.assertEqual(self.inspect()["branding_assets_verified"], 1)

    def test_rejects_wrong_bundle_version_callback_and_artwork(self):
        for field, value in [("CFBundleIdentifier", "other.app"), ("CFBundleVersion", "22"), ("FlutterDeepLinkingEnabled", True)]:
            old = self.info[field]
            self.info[field] = value
            self.write_info()
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.inspect()
            self.info[field] = old
        self.write_info()
        self.image.write_bytes(b"changed")
        with self.assertRaises(ValueError):
            self.inspect()

    def test_rejects_signed_root_or_missing_device_architecture(self):
        for arch, signature in [("x86_64", 1), ("arm64", 0)]:
            def tool(args, **kwargs):
                return SimpleNamespace(stdout=arch, returncode=0 if args[0] == "lipo" else signature)
            with self.subTest(arch=arch, signature=signature), self.assertRaises(ValueError):
                package.inspect_app(self.app, "23", CLIENT, self.source, tool)

    def test_flutter_percent_encodes_asset_names_with_spaces(self):
        name = "assets/branding/Tabby Cat.png"
        encoded = self.app / "Frameworks/App.framework/flutter_assets/assets/branding/Tabby%20Cat.png"
        encoded.write_bytes(b"synthetic space-name asset")
        self.source["files"][name] = package.digest(encoded)
        self.assertEqual(self.inspect()["branding_assets_verified"], 2)

    def test_rejects_private_material_in_payload(self):
        (self.app / "unwanted.p12").write_bytes(b"synthetic-not-a-key")
        with self.assertRaises(ValueError):
            self.inspect()

    def test_packages_payload_and_preserves_executable_flag(self):
        output = Path(self.temp.name) / "output/fixture.ipa"
        package.package_app(self.app, output)
        with zipfile.ZipFile(output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertIn("Payload/Runner.app/Info.plist", archive.namelist())
            self.assertTrue((archive.getinfo("Payload/Runner.app/Runner").external_attr >> 16) & 0o111)


class PublishedIPAVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ipa = self.root / "Tabby.ipa"
        self.report_path = self.root / "Tabby.ipa.json"
        self.source_path = self.root / "ios-build-source-manifest.json"
        self.android_path = self.root / "candidate-manifest.json"
        self.commit = "a" * 40
        self.android = {"commit": self.commit, "version_name": "1.0.4", "version_code": 25}
        self.source = {"schema": 1, "source_commit": self.commit, "android_baseline": self.commit,
                       "files": {"lib/main.dart": "b" * 64}}
        self.report = {"ipa": "Tabby.ipa", "ipa_sha256": "", "source_commit": self.commit,
                       "package_identifier": "com.zalweb.tabby", "bundle_id": "com.zalweb.tabby",
                       "version_name": "1.0.4", "build_number": "25", "version_code": 25,
                       "architectures": ["arm64"], "unsigned": True, "source_file_count": 1,
                       "simulator_native_smoke": {"outcome": "passed", "mode": "actual simulator checks",
                                                   "run_id": 7, "source_commit": self.commit}}
        info = {"CFBundleIdentifier": "com.zalweb.tabby", "CFBundleShortVersionString": "1.0.4", "CFBundleVersion": "25"}
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Runner.app/Runner", b"synthetic-arm64-fixture")
        self.report["ipa_sha256"] = artifact.sha256(self.ipa)
        self.write_json(self.report_path, self.report)
        self.write_json(self.source_path, self.source)
        self.write_json(self.android_path, self.android)

    @staticmethod
    def write_json(path, value):
        path.write_text(json.dumps(value))

    def verify(self):
        return artifact.verify_ipa(self.ipa, self.report_path, self.source_path, self.android_path, self.commit)

    def test_checks_ipa_bytes_bundle_shared_version_source_and_unsigned_report(self):
        result = self.verify()
        self.assertEqual(result["ipa_sha256"], self.report["ipa_sha256"])
        self.assertEqual(result["version"], "1.0.4+25")

    def test_rejects_digest_source_package_version_architecture_or_signed_mismatch(self):
        for field, value in [("ipa_sha256", "c" * 64), ("source_commit", "d" * 40),
                             ("package_identifier", "another.app"), ("build_number", "24"),
                             ("architectures", ["x86_64"]), ("unsigned", False),
                             ("simulator_native_smoke", "unverified")]:
            old = self.report[field]
            self.report[field] = value
            self.write_json(self.report_path, self.report)
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.verify()
            self.report[field] = old
        self.write_json(self.report_path, self.report)

    def test_rejects_packaged_bundle_identity_and_private_material(self):
        info = {"CFBundleIdentifier": "another.app", "CFBundleShortVersionString": "1.0.4", "CFBundleVersion": "25"}
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Runner.app/Runner", b"synthetic")
            archive.writestr("Payload/Runner.app/embedded.mobileprovision", b"synthetic")
        self.report["ipa_sha256"] = artifact.sha256(self.ipa)
        self.write_json(self.report_path, self.report)
        with self.assertRaisesRegex(ValueError, "signing or environment material"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
