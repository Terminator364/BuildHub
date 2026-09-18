import sys
import tempfile
import unittest
from pathlib import Path

from buildhub.io import read_json
from buildhub.runner import (
    WINDOWS_CONTROL_C_EXIT,
    WINDOWS_CONTROL_C_EXIT_SIGNED,
    classify_returncode,
    run_process,
)


class RunnerTests(unittest.TestCase):
    def test_control_c_exit_is_external_termination(self):
        self.assertEqual(classify_returncode(WINDOWS_CONTROL_C_EXIT), "EXTERNAL_TERMINATION")
        self.assertEqual(classify_returncode(WINDOWS_CONTROL_C_EXIT_SIGNED), "EXTERNAL_TERMINATION")

    def test_argument_with_spaces_is_not_split_and_heartbeat_finishes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            log = root / "worker.log"
            heartbeat = root / "heartbeat.json"
            result = run_process(
                [sys.executable, "-c", "import sys; print(sys.argv[1])", "hello world"],
                log_path=log,
                heartbeat_path=heartbeat,
                operation_id="runner-test",
                heartbeat_seconds=0.2,
            )
            self.assertEqual(result["classification"], "SUCCESS")
            self.assertIn("hello world", log.read_text(encoding="utf-8"))
            final = read_json(heartbeat)
            self.assertEqual(final["state"], "SUCCESS")
            self.assertEqual(final["operation_id"], "runner-test")


if __name__ == "__main__":
    unittest.main()
