import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from buildhub.cli import main


class CliTests(unittest.TestCase):
    def test_zero_args_prints_help(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = main([])
        self.assertEqual(code, 0)
        self.assertIn("BuildHub", output.getvalue())

    def test_many_paths_and_spaces_are_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            a = root / "one file.txt"
            b = root / "two file.txt"
            a.write_text("a", encoding="utf-8")
            b.write_text("b", encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = main(["hash", str(a), str(b)])
            self.assertEqual(code, 0)
            text = output.getvalue()
            self.assertIn(str(a), text)
            self.assertIn(str(b), text)


if __name__ == "__main__":
    unittest.main()
