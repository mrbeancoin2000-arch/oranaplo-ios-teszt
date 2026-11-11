"""Guard against the Windows cp1250 regression in Python test sources."""
import ast
from pathlib import Path
import unittest

TEST_DIR = Path(__file__).resolve().parent


class TextEncodingTests(unittest.TestCase):
    def test_test_sources_declare_utf8_when_reading_text(self):
        for script in TEST_DIR.glob("test_*.py"):
            tree = ast.parse(script.read_text(encoding="utf-8"), filename=str(script))
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                if not isinstance(node.func, ast.Attribute):
                    continue
                if node.func.attr != "read_text":
                    continue
                has_encoding = bool(node.args) or any(
                    kw.arg == "encoding" for kw in node.keywords
                )
                self.assertTrue(
                    has_encoding,
                    f"{script.name}:{node.lineno} calls read_text without explicit UTF-8 encoding",
                )


if __name__ == "__main__":
    unittest.main()
