"""Regression tests for the Nov 11 2026 concatenated GitHub run ID error."""
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'tools/select_github_run.py'
TOKEN='a'*32
SHA='b'*40

def item(num, token=TOKEN, sha=SHA, event='workflow_dispatch'):
    return dict(databaseId=num, displayTitle='OraNaplo CI '+token,
                headSha=sha, event=event)

class CloudRunSelectionTests(unittest.TestCase):
    def cli(self, rows, token=TOKEN, sha=SHA):
        return subprocess.run([sys.executable, str(SCRIPT), '--token',token,'--sha',sha],
                              input=json.dumps(rows),text=True,capture_output=True)

    def test_selects_only_new_run_not_concatenated_ids(self):
        rows=[item(43010519868),item(42983325432,token='c'*32),
              item(42980395421,token='d'*32),item(42896063897,token='e'*32)]
        r=self.cli(rows)
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(r.stdout.strip(),'43010519868')
        self.assertEqual(len(r.stdout.split()),1)

    def test_rejects_old_run_same_commit(self):
        r=self.cli([item(42983325432,token='c'*32)])
        self.assertEqual(r.returncode,2)
        self.assertFalse(r.stdout.strip())

    def test_rejects_wrong_commit(self):
        self.assertEqual(self.cli([item(12345,sha='c'*40)]).returncode,2)

    def test_rejects_wrong_event(self):
        self.assertEqual(self.cli([item(12345,event='push')]).returncode,2)

    def test_rejects_ambiguous_runs(self):
        self.assertEqual(self.cli([item(12345),item(67890)]).returncode,3)

    def test_rejects_invalid_id(self):
        self.assertEqual(self.cli([item('12345')]).returncode,4)

    def test_rejects_non_list_response(self):
        self.assertEqual(self.cli({'databaseId':12345}).returncode,4)

    def test_workflow_dispatch_has_correlation_input(self):
        workflow=(ROOT/'.github/workflows/macos-ipa.yml').read_text(encoding='utf-8')
        cloud=(ROOT/'tools/cloud_build.ps1').read_text(encoding='utf-8')
        self.assertIn('run-name: OraNaplo CI ${{ inputs.request_id',workflow)
        self.assertIn('request_id:',workflow)
        self.assertIn('"request_id=$requestID"',cloud)
        self.assertIn('gh run watch $run',cloud)
        self.assertIn('gh run download $run',cloud)
        self.assertIn("$run -notmatch '^[0-9]{5,20}$'",cloud)
        self.assertNotIn('$run = [string]$item.databaseId',cloud)

if __name__=='__main__': unittest.main()
