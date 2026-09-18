import json
import tempfile
import unittest
from pathlib import Path

from buildhub.io import atomic_write_json, read_json


class IoTests(unittest.TestCase):
    def test_reads_utf8_bom_json(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "legacy.json"
            p.write_bytes(b"\xef\xbb\xbf" + json.dumps({"ok": True}).encode("utf-8"))
            self.assertEqual(read_json(p), {"ok": True})

    def test_writer_emits_plain_utf8(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "state.json"
            atomic_write_json(p, {"value": "é"})
            self.assertFalse(p.read_bytes().startswith(b"\xef\xbb\xbf"))
            self.assertEqual(read_json(p)["value"], "é")


if __name__ == "__main__":
    unittest.main()
