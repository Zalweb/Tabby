"""Synthetic contract checks; these never claim Xcode or iPhone acceptance."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
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
CLIENT = {"SUPABASE_URL": "https://synthetic.invalid", "SUPABASE_ANON_KEY": "sb_publishable_synthetic", "GOOGLE_IOS_CLIENT_ID": "123-ios.apps.googleusercontent.com", "GOOGLE_WEB_CLIENT_ID": "123-web.apps.googleusercontent.com"}


class ClientTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
