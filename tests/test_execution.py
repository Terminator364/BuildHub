import unittest

from buildhub.execution import choose_execution_backend


class ExecutionTests(unittest.TestCase):
    def test_remote_quota_exhaustion_falls_back_local(self):
        plan = choose_execution_backend(remote_status="QUOTA_EXHAUSTED")
        self.assertEqual(plan.backend, "LOCAL")
        self.assertTrue(plan.local_state_authoritative)

    def test_remote_unavailable_falls_back_local(self):
        plan = choose_execution_backend(remote_status="UNAVAILABLE")
        self.assertEqual(plan.backend, "LOCAL")

    def test_available_remote_can_accelerate(self):
        plan = choose_execution_backend(remote_status="AVAILABLE")
        self.assertEqual(plan.backend, "REMOTE")

    def test_no_backend_fails_closed(self):
        with self.assertRaises(RuntimeError):
            choose_execution_backend(remote_status="UNAVAILABLE", local_available=False)


if __name__ == "__main__":
    unittest.main()
