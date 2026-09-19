import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from buildhub.io import fsync_file, fsync_parent_dir, read_json, sha256_file
from buildhub.receipt import CommitConflict, CommitOutcomeUnknown, publish_verified, reconcile_publication


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

    def test_publish_flushes_artifact_before_committed_receipt(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"power-loss durable artifact")

            with patch("buildhub.receipt.fsync_file", wraps=fsync_file) as sync, \
                 patch("buildhub.receipt.fsync_parent_dir", wraps=fsync_parent_dir) as dirsync:
                result = publish_verified(src, dst, receipt, operation_id="op-fsync")

            self.assertEqual(result["status"], "COMMITTED")
            self.assertGreaterEqual(sync.call_count, 2)
            self.assertEqual(sync.call_args_list[-1].args[0], dst)
            self.assertGreaterEqual(dirsync.call_count, 1)
            self.assertEqual(dirsync.call_args_list[0].args[0], dst.parent)

    def test_materialized_committed_receipt_never_triggers_blind_artifact_rollback(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"new durable bytes")
            dst.write_bytes(b"previous durable bytes")

            def materialize_receipt_then_fail(path, value):
                Path(path).write_text(json.dumps(value), encoding="utf-8")
                raise OSError("simulated failure after receipt replace boundary")

            real_sync = fsync_file
            def fail_receipt_sync(path):
                if Path(path) == receipt:
                    raise OSError("simulated receipt durability retry failure")
                return real_sync(path)

            with patch("buildhub.receipt.atomic_write_json", side_effect=materialize_receipt_then_fail), \
                 patch("buildhub.receipt.fsync_file", side_effect=fail_receipt_sync):
                with self.assertRaises(CommitOutcomeUnknown):
                    publish_verified(src, dst, receipt, operation_id="op-uncertain")

            self.assertEqual(dst.read_bytes(), b"new durable bytes")
            materialized = read_json(receipt)
            self.assertEqual(materialized["status"], "COMMITTED")
            self.assertEqual(materialized["operation_id"], "op-uncertain")
            self.assertEqual(materialized["published_sha256"], sha256_file(dst))

    def test_materialized_receipt_can_self_heal_on_bounded_durability_retry(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"self-heal")

            calls = {"n": 0}
            def materialize_receipt_then_fail(path, value):
                calls["n"] += 1
                Path(path).write_text(json.dumps(value), encoding="utf-8")
                raise OSError("simulated post-replace error")

            with patch("buildhub.receipt.atomic_write_json", side_effect=materialize_receipt_then_fail):
                result = publish_verified(src, dst, receipt, operation_id="op-heal")

            self.assertEqual(result["status"], "COMMITTED")
            self.assertEqual(calls["n"], 1)
            self.assertEqual(sha256_file(dst), result["published_sha256"])

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

    def test_reconcile_publication_classifies_interrupted_boundaries(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"payload")

            self.assertEqual(
                reconcile_publication(src, dst, receipt, operation_id="op-r")["status"],
                "NOT_COMMITTED",
            )

            dst.write_bytes(b"payload")
            self.assertEqual(
                reconcile_publication(src, dst, receipt, operation_id="op-r")["status"],
                "ARTIFACT_PRESENT_RECEIPT_MISSING",
            )

            result = publish_verified(src, dst, receipt, operation_id="op-r")
            self.assertEqual(result["status"], "COMMITTED")
            self.assertEqual(
                reconcile_publication(src, dst, receipt, operation_id="op-r")["status"],
                "COMMITTED",
            )

            dst.write_bytes(b"corrupt")
            self.assertEqual(
                reconcile_publication(src, dst, receipt, operation_id="op-r")["status"],
                "RECEIPT_PRESENT_ARTIFACT_MISMATCH",
            )

    def test_reconcile_publication_rejects_other_operation_receipt(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"payload")
            publish_verified(src, dst, receipt, operation_id="op-a")
            state = reconcile_publication(src, dst, receipt, operation_id="op-b")
            self.assertEqual(state["status"], "CONFLICT")
            self.assertEqual(state["receipt_operation_id"], "op-a")

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

    def test_different_operation_cannot_overwrite_committed_receipt(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "source.bin"
            dst = root / "published.bin"
            receipt = root / "receipt.json"
            src.write_bytes(b"first artifact")
            original = publish_verified(src, dst, receipt, operation_id="op-original")

            src.write_bytes(b"second artifact")
            with self.assertRaises(CommitConflict):
                publish_verified(src, dst, receipt, operation_id="op-other")

            self.assertEqual(read_json(receipt), original)
            self.assertEqual(dst.read_bytes(), b"first artifact")


if __name__ == "__main__":
    unittest.main()
