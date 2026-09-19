import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AX15GoGrayHealthTests(unittest.TestCase):
    def test_publication_health_requires_independent_dimensions(self):
        health = json.loads((ROOT / ".project-memory" / "AX15GO_GRAY_HEALTH_R4.json").read_text(encoding="utf-8"))
        self.assertEqual(health["status"], "ENGINEERING_CONTRACT_NOT_FIELD_PROOF")
        self.assertGreaterEqual(len(health["required_dimensions"]), 7)
        self.assertTrue(health["rules"]["command_exit_zero_is_not_commit_health"])
        self.assertTrue(health["rules"]["artifact_exists_is_not_commit_health"])
        self.assertTrue(health["rules"]["unknown_outcome_is_not_healthy"])
        self.assertIn("RECEIPT_WRITABLE_AND_READBACK_VERIFIED", health["required_dimensions"])
        self.assertIn("OPERATION_IDENTITY_VALID", health["required_dimensions"])
        self.assertTrue(health["rules"]["capability_scoped_health_required"])
        self.assertNotIn("DESTINATION_WRITABLE", health["capability_scopes"]["LOCAL_BUILD"])
        self.assertIn("DESTINATION_WRITABLE", health["capability_scopes"]["PUBLICATION"])


if __name__ == "__main__":
    unittest.main()
