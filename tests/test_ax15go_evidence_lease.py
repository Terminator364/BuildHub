import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AX15GoEvidenceLeaseTests(unittest.TestCase):
    def test_publication_lease_binds_identity_and_rechecks_at_effect(self):
        lease = json.loads((ROOT / ".project-memory" / "AX15GO_EVIDENCE_LEASE_R5.json").read_text(encoding="utf-8"))
        self.assertTrue(lease["rules"]["generation_change_invalidates_immediately"])
        self.assertTrue(lease["rules"]["health_snapshot_never_authorizes_mutation_alone"])
        self.assertTrue(lease["rules"]["mutation_preconditions_checked_at_effect_boundary"])
        self.assertTrue(lease["rules"]["no_full_health_probe_per_turn"])
        fields = set(lease["capabilities"]["PUBLICATION"]["generation_vector"])
        self.assertTrue({"operation_id", "source_hash", "artifact_hash", "destination_identity", "expected_publication_revision"} <= fields)
        self.assertIn("COMMIT_OUTCOME_UNKNOWN", lease["capabilities"]["PUBLICATION"]["commit_guard"])


if __name__ == "__main__":
    unittest.main()
