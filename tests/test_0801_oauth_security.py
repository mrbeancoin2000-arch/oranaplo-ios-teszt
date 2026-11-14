"""ULTRA DEBUG regression tests for local OAuth settings without personal identifiers."""
import json
import tempfile
import unittest
from pathlib import Path
from tools.ultra_debug import safety_scan

SAMPLE = {
    'ios_client_id': '1234-example.apps.googleusercontent.com',
    'ios_bundle_id': 'hu.oranaplo.ios'
}

class LocalOAuthSafety(unittest.TestCase):
    def test_missing_oauth_does_not_cause_false_security_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(safety_scan(Path(tmp)), [])

    def test_safe_public_google_oauth_is_not_a_secret(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'google_oauth.json'
            path.write_text(json.dumps(SAMPLE), encoding='utf-8')
            self.assertEqual(safety_scan(Path(tmp)), [])

    def test_secret_in_oauth_is_rejected_without_logging_value(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'google_oauth.json'
            path.write_text(json.dumps({**SAMPLE, 'client_secret': 'TOP_SECRET_VALUE'}), encoding='utf-8')
            output = safety_scan(Path(tmp))
            self.assertTrue(output)
            self.assertNotIn('TOP_SECRET_VALUE', str(output))

    def test_invalid_oauth_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'google_oauth.json'
            path.write_text('{bad-json', encoding='utf-8')
            self.assertTrue(safety_scan(Path(tmp)))

    def test_real_secret_file_still_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'AuthKey_ZZZ.p8'
            path.write_text('SENSITIVE', encoding='utf-8')
            self.assertTrue(safety_scan(Path(tmp)))

    def test_dotenv_files_still_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp)/'.env.local').write_text('SECRET=VALUE')
            self.assertTrue(safety_scan(Path(tmp)))

    def test_ignored_logs_do_not_block_local_preflight(self):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp)/'logs'; d.mkdir()
            (d/'.env').write_text('SECRET=VALUE')
            self.assertEqual(safety_scan(Path(tmp)), [])

if __name__ == '__main__': unittest.main()
