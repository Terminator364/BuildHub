import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from buildhub.io import read_json, sha256_file
from buildhub.receipt import CommitConflict, publish_verified


class ReceiptTests(unittest.TestCase):
    def test_commit_requires_matching_destination_readback(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"verified artifact")

            result = publish_verified(src, dst, receipt, operation_id="op-1")

            self.assertEqual(result["status"], "COMMITTED")
            self.assertTrue(result["readback_verified"])
            self.assertEqual(sha256_file(src), sha256_file(dst))
            self.assertEqual(read_json(receipt)["published_sha256"], sha256_file(dst))

    def test_finalization_failure_restores_previous_destination(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"new candidate")
            dst.write_bytes(b"previous validated")

            with patch("buildhub.receipt.atomic_write_json", side_effect=OSError("receipt failure")):
                with self.assertRaises(OSError):
                    publish_verified(src, dst, receipt, operation_id="op-2")

            self.assertEqual(dst.read_bytes(), b"previous validated")

    def test_same_committed_operation_is_idempotent(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"same payload")
            first = publish_verified(src, dst, receipt, operation_id="stable-op")

            with patch("buildhub.receipt.shutil.copyfile", side_effect=AssertionError("must not rewrite")):
                replay = publish_verified(src, dst, receipt, operation_id="stable-op")

            self.assertEqual(first, replay)

    def test_same_operation_with_changed_source_is_conflict(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"version one")
            publish_verified(src, dst, receipt, operation_id="stable-op")
            src.write_bytes(b"version two")

            with self.assertRaises(CommitConflict):
                publish_verified(src, dst, receipt, operation_id="stable-op")


if __name__ == "__main__":
    unittest.main()
