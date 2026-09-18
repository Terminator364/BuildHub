import sys
import tempfile
import time
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

    def test_timeout_is_bounded_and_never_success(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            result = run_process(
                [sys.executable, "-c", "import time; time.sleep(30)"],
                log_path=root / "worker.log",
                heartbeat_path=root / "heartbeat.json",
                operation_id="timeout-test",
                timeout_seconds=0.5,
                heartbeat_seconds=0.2,
            )
            self.assertEqual(result["classification"], "TIMEOUT")
            final = read_json(root / "heartbeat.json")
            self.assertEqual(final["state"], "TIMEOUT")

    def test_timeout_terminates_descendant_process(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            sentinel = root / "child-survived.txt"
            child_code = (
                "import pathlib,time;"
                "time.sleep(1.5);"
                f"pathlib.Path({str(sentinel)!r}).write_text('alive', encoding='utf-8')"
            )
            parent_code = (
                "import subprocess,sys,time;"
                f"subprocess.Popen([sys.executable, '-c', {child_code!r}]);"
                "time.sleep(30)"
            )
            result = run_process(
                [sys.executable, "-c", parent_code],
                log_path=root / "tree.log",
                heartbeat_path=root / "tree-heartbeat.json",
                operation_id="tree-timeout",
                timeout_seconds=0.5,
                heartbeat_seconds=0.2,
            )
            self.assertEqual(result["classification"], "TIMEOUT")
            time.sleep(2.0)
            self.assertFalse(sentinel.exists(), "descendant escaped process-tree cancellation")


if __name__ == "__main__":
    unittest.main()
