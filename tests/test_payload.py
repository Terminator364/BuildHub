import json
import tempfile
import unittest
from pathlib import Path

from buildhub.io import sha256_file
from buildhub.payload import PayloadValidationError, validate_payload


class PayloadTests(unittest.TestCase):
    def _manifest(self, root: Path, *, required_modules=None):
        payload = root / "payload.txt"
        payload.write_text("complete", encoding="utf-8")
        manifest = root / "payload.json"
        manifest.write_text(json.dumps({
            "schema": "buildhub.payload/v1",
            "files": [{"path": "payload.txt", "sha256": sha256_file(payload)}],
            "required_modules": required_modules or [],
        }), encoding="utf-8")
        return manifest, payload

    def test_complete_payload_passes(self):
        with tempfile.TemporaryDirectory() as td:
            manifest, _ = self._manifest(Path(td), required_modules=["json"])
            self.assertEqual(validate_payload(manifest)["status"], "PASS")

    def test_missing_payload_file_fails_before_activation(self):
        with tempfile.TemporaryDirectory() as td:
            manifest, payload = self._manifest(Path(td))
            payload.unlink()
            with self.assertRaises(PayloadValidationError):
                validate_payload(manifest)

    def test_hash_changed_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            manifest, payload = self._manifest(Path(td))
            payload.write_text("changed", encoding="utf-8")
            with self.assertRaises(PayloadValidationError):
                validate_payload(manifest)

    def test_missing_required_module_fails(self):
        with tempfile.TemporaryDirectory() as td:
            manifest, _ = self._manifest(Path(td), required_modules=["buildhub_module_that_does_not_exist"])
            with self.assertRaises(PayloadValidationError):
                validate_payload(manifest)


if __name__ == "__main__":
    unittest.main()
