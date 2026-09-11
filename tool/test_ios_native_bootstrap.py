import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

from ios_native_bootstrap import generate, libraries


class NativeManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "Runner.app"
        (self.app / "Frameworks").mkdir(parents=True)
        (self.app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Runner"}))
        self.reference = self.root / "order.json"
        self.reference.write_text(json.dumps({"paths": ["/usr/lib/libSystem.B.dylib", "/usr/lib/libobjc.A.dylib"]}))
        self.links = {"Runner": [("/usr/lib/libSystem.B.dylib", False)]}
        self.runtime = self.app / "Frameworks/Art3m1sRuntime.dylib"
        self.runtime.touch()
        self.links[self.runtime.name] = []

    def build(self):
        with patch("ios_native_bootstrap.libraries", side_effect=lambda path: self.links[path.name]):
            generate(self.app, products=self.root, reference=self.reference)
        return plistlib.loads((self.app / "NativeLibraries.plist").read_bytes())["steps"]

    def test_native_host_rejects_embedded_or_non_system_dependencies(self):
        for dependency in ("@rpath/Flutter.framework/Flutter", "/tmp/injected.dylib"):
            with self.subTest(dependency=dependency):
                self.links["Runner"] = [(dependency, False)]
                with self.assertRaisesRegex(ValueError, "only link system"):
                    self.build()

    def test_missing_runtime_fails_the_build(self):
        self.runtime.unlink()
        with self.assertRaisesRegex(ValueError, "was not embedded"):
            self.build()

    def test_missing_transitive_dependency_fails_the_build(self):
        self.links[self.runtime.name] = [("@rpath/Missing.framework/Missing", False)]
        with self.assertRaisesRegex(ValueError, "Missing embedded dependency"):
            self.build()

    def test_preload_order_and_strong_links_override_weak_links(self):
        (self.app / "Frameworks/Plugin.dylib").touch()
        self.links["Plugin.dylib"] = [("/usr/lib/libSystem.B.dylib", False)]
        self.links[self.runtime.name] = [
            ("/usr/lib/libobjc.A.dylib", False),
            ("/usr/lib/libSystem.B.dylib", True),
            ("@rpath/Plugin.dylib", False),
        ]
        self.assertEqual(self.build(), [
            {"path": "/usr/lib/libSystem.B.dylib", "weak": False},
            {"path": "/usr/lib/libobjc.A.dylib", "weak": False},
            {"path": "Frameworks/Plugin.dylib", "weak": False},
            {"path": "Frameworks/Art3m1sRuntime.dylib", "weak": False},
        ])

    def test_spm_bundle_is_embedded_for_bundle_main_accessors(self):
        resources = self.root / "plugin_resources.bundle"
        resources.mkdir()
        (resources / "PrivacyInfo.xcprivacy").write_bytes(b"privacy fixture")
        self.build()
        self.assertEqual((self.app / resources.name / "PrivacyInfo.xcprivacy").read_bytes(), b"privacy fixture")

    def test_dyld_parser_excludes_rpaths_and_preserves_weak_links(self):
        sample = "    -linked_dylibs:\n        /usr/lib/libSystem.B.dylib\n        weak-link /usr/lib/swift/libswiftSpatial.dylib\n    -rpaths:\n        @executable_path/Frameworks\n"
        with patch("subprocess.check_output", return_value=sample):
            self.assertEqual(libraries(Path("Runner")), [
                ("/usr/lib/libSystem.B.dylib", False),
                ("/usr/lib/swift/libswiftSpatial.dylib", True),
            ])


if __name__ == "__main__":
    unittest.main()
