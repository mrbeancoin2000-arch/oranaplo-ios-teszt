"""Upload allowlist regression: CI inputs present, private QA logs excluded."""
from pathlib import Path
from tempfile import TemporaryDirectory
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[1]
from sys import path as python_path
python_path.insert(0, str(ROOT/'tools'))
from verify_ci_staging import check, REQUIRED

class TestCIStaging062(unittest.TestCase):
    def stage(self, directory):
        stage = Path(directory)
        for rel in REQUIRED:
            (stage/rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/rel, stage/rel)
        return stage

    def test_valid_synthetic_stage_passes(self):
        with TemporaryDirectory() as directory:
            self.assertEqual(check(self.stage(directory)), [])

    def test_missing_csv_stops_before_github_push(self):
        with TemporaryDirectory() as directory:
            stage=self.stage(directory)
            (stage/'tests/fixtures/qa_061/NAPI_SZINKRON_NAPLO_TEMPLATE.csv').unlink()
            self.assertTrue(any('Missing GitHub build input' in x for x in check(stage)))

    def test_private_qa_log_never_uploaded(self):
        with TemporaryDirectory() as directory:
            stage=self.stage(directory)
            private=stage/'docs/QA_061/NAPI_SZINKRON_NAPLO.csv'
            private.parent.mkdir(parents=True, exist_ok=True)
            private.write_text('personal', encoding='utf-8')
            self.assertTrue(any('PRIVATE FILE' in x for x in check(stage)))

    def test_private_qa_notes_never_uploaded(self):
        with TemporaryDirectory() as directory:
            stage=self.stage(directory)
            private=stage/'docs/QA_061/DAILY_NOTES.md'
            private.parent.mkdir(parents=True, exist_ok=True)
            private.write_text('private notes',encoding='utf-8')
            self.assertTrue(any('PRIVATE QA FOLDER' in x for x in check(stage)))

if __name__ == '__main__': unittest.main()
