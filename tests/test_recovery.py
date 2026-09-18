import tempfile
import unittest
from pathlib import Path

from buildhub.recovery import RecoveryJournal, StaleRecoveryError


class RecoveryTests(unittest.TestCase):
    def test_committed_step_cannot_be_replayed(self):
        with tempfile.TemporaryDirectory() as td:
            journal = RecoveryJournal(Path(td) / "recovery.json")
            journal.begin("install-1", "payload-A")
            journal.commit("install-1", "payload-A", "receipt-A")
            with self.assertRaises(StaleRecoveryError):
                journal.begin("install-1", "payload-A")

    def test_payload_change_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            journal = RecoveryJournal(Path(td) / "recovery.json")
            journal.begin("install-1", "payload-A")
            with self.assertRaises(StaleRecoveryError):
                journal.commit("install-1", "payload-B", "receipt-B")


if __name__ == "__main__":
    unittest.main()
