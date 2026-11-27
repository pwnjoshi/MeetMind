import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

import validate_ipa


class SignedIPAValidationTests(unittest.TestCase):
    def make_ipa(self, path: Path, *, commit: str = "a" * 40, signed: bool = True) -> None:
        info = {
            key: "Used by this test app."
            for key in validate_ipa.REQUIRED
        }
        info.update({
            "ITSAppUsesNonExemptEncryption": False,
            "CFBundleDisplayName": "Manent",
            "CFBundleIdentifier": "com.meetmind.app",
            "LSApplicationCategoryType": "public.app-category.productivity",
            "UIBackgroundModes": ["audio", "processing"],
            "BGTaskSchedulerPermittedIdentifiers": ["com.meetmind.app.analysis"],
            "ManentBuildCommit": commit,
        })
        manifest = {
            "NSPrivacyTracking": False,
            "NSPrivacyTrackingDomains": [],
            "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": [
                {
                    "NSPrivacyAccessedAPIType": category,
                    "NSPrivacyAccessedAPITypeReasons": ["TEST.1"],
                }
                for category in validate_ipa.REQUIRED_API_CATEGORIES
            ],
        }
        with zipfile.ZipFile(path, "w") as archive:
            prefix = "Payload/Manent.app/"
            archive.writestr(prefix + "Info.plist", plistlib.dumps(info))
            archive.writestr(prefix + "PrivacyInfo.xcprivacy", plistlib.dumps(manifest))
            archive.writestr(prefix + "Assets.car", b"assets")
            if signed:
                archive.writestr(prefix + "embedded.mobileprovision", b"profile")
                archive.writestr(prefix + "_CodeSignature/CodeResources", b"signature resources")

    def test_accepts_expected_signed_ipa_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "Manent.ipa"
            self.make_ipa(ipa)
            data = validate_ipa.validate(
                ipa,
                expected_commit="a" * 40,
                expected_bundle_id="com.meetmind.app",
                require_signing=True,
            )
            self.assertEqual(data["ManentBuildCommit"], "a" * 40)

    def test_rejects_wrong_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "Manent.ipa"
            self.make_ipa(ipa)
            with self.assertRaisesRegex(ValueError, "ManentBuildCommit"):
                validate_ipa.validate(ipa, expected_commit="b" * 40)

    def test_rejects_unsigned_ipa_when_signing_is_required(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "Manent.ipa"
            self.make_ipa(ipa, signed=False)
            with self.assertRaisesRegex(ValueError, "signing material"):
                validate_ipa.validate(ipa, require_signing=True)


if __name__ == "__main__":
    unittest.main()
