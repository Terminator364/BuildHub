import tempfile
import unittest
import zipfile
from pathlib import Path

from buildhub.package import create_package, verify_package, PackageVerificationError


class PackageTests(unittest.TestCase):
    def test_package_is_deterministic_and_verifiable(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "a.txt").write_text("A", encoding="utf-8")
            (root / "b.txt").write_text("B", encoding="utf-8")
            one = root / "one.zip"
            two = root / "two.zip"
            first = create_package(root, one, ["b.txt", "a.txt"])
            second = create_package(root, two, ["a.txt", "b.txt"])
            self.assertEqual(first["sha256"], second["sha256"])
            self.assertEqual(verify_package(one)["status"], "PASS")

    def test_package_tamper_is_detected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "a.txt").write_text("A", encoding="utf-8")
            package = root / "bundle.zip"
            create_package(root, package, ["a.txt"])
            with zipfile.ZipFile(package, "a") as zf:
                zf.writestr("a.txt", b"TAMPERED")
            with self.assertRaises(PackageVerificationError):
                verify_package(package)


if __name__ == "__main__":
    unittest.main()
