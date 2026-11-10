import contextlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from server import Service, queue_list, task_paths, safe_test_cmd


class QueueTests(unittest.TestCase):
    def test_queue_shapes(self):
        tasks=[{'id':'SPIKE-001','status':'awaiting_approval'}]
        self.assertEqual(queue_list(tasks), tasks)
        self.assertEqual(queue_list({'tasks': tasks}), tasks)
        self.assertEqual(queue_list({'tickets': tasks}), tasks)
        self.assertIsNone(queue_list({'unknown':tasks}))

    def test_paths(self):
        self.assertEqual(task_paths({'allowed_files':['tests/spike/overlay/**']}),['tests/spike/overlay/**'])
        self.assertIsNone(task_paths({'status':'held'}))

    def test_cmd_gate(self):
        self.assertTrue(safe_test_cmd('godot --headless --path tests/spike/overlay --quit'))
        self.assertTrue(safe_test_cmd('python3 -m unittest discover -s tests'))
        self.assertFalse(safe_test_cmd('python3 -c "print(1)"'))
        self.assertFalse(safe_test_cmd('godot --headless; rm -rf .'))
        self.assertFalse(safe_test_cmd('bash scripts/test.sh'))


class ApprovalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='auto002_test_')
        self.root = Path(self.tmp.name)
        (self.root/'tools/auto').mkdir(parents=True)
        (self.root/'tasks/evidence/SPIKE-001').mkdir(parents=True)
        (self.root/'tools/auto/runner.py').write_text('print("check ok")\n',encoding='utf-8')
        (self.root/'tasks/APPROVALS.md').write_text('# APPROVALS\nBEGIN-EXAMPLE-ONLY ID=<票号> PHASE=B\nEND-EXAMPLE-ONLY\n',encoding='utf-8')
        (self.root/'tasks/evidence/SPIKE-001/plan.md').write_text('# Plan\n',encoding='utf-8')
        self.ticket = {'id':'SPIKE-001','status':'awaiting_approval','allowed_files':['tests/spike/overlay/**'],'test_cmd':''}
        self.save_queue()
        def git(*args):
            return subprocess.run(['git', *args], cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        git('init', '-q')
        git('config', 'user.email', 'test@example.invalid')
        git('config', 'user.name', 'AUTO-002 Test')
        git('add', '.')
        git('commit', '-qm', 'baseline')
        self.svc=Service(self.root)
        self.svc.external_runner_alive=lambda: False

    def tearDown(self):
        self.tmp.cleanup()

    def save_queue(self):
        (self.root/'tools/auto/queue.json').write_text(json.dumps({'tasks':[self.ticket]},indent=2),encoding='utf-8')

    def approve(self):
        return self.svc.approve({'id':'SPIKE-001','confirm':'SPIKE-001', 'by':'rain',
                                'notes':'批准当前 Godot 技术验证计划',
                                'test_cmd':'godot --headless --path tests/spike/overlay --quit'})

    def test_approve_and_commit(self):
        res=self.approve()
        self.assertEqual(res['status'],'exec_ready')
        after=json.loads((self.root/'tools/auto/queue.json').read_text())['tasks'][0]
        self.assertEqual(after['test_cmd'],'godot --headless --path tests/spike/overlay --quit')
        self.assertEqual(after['status'],'exec_ready')
        ledger=(self.root/'tasks/APPROVALS.md').read_text()
        self.assertIn('BEGIN-APPROVAL ID=SPIKE-001 PHASE=B',ledger)
        self.assertIn('by: rain',ledger)
        self.assertEqual(subprocess.check_output(['git','status','--short'],cwd=self.root).strip(),b'')
        with self.assertRaises(ValueError):
            self.approve()

    def test_fail_no_plan(self):
        (self.root/'tasks/evidence/SPIKE-001/plan.md').unlink()
        with self.assertRaisesRegex(ValueError,'plan.md'):
            self.approve()

    def test_fail_wrong_confirm(self):
        with self.assertRaisesRegex(ValueError,'确认 ID'):
            self.svc.approve({'id':'SPIKE-001','confirm':'WRONG','by':'rain','notes':'OK','test_cmd':'godot --headless'})

    def test_fail_unrecognized_schema(self):
        (self.root/'tools/auto/queue.json').write_text('{"other": []}',encoding='utf8')
        with self.assertRaisesRegex(ValueError,'不兼容'):
            self.approve()


if __name__ == '__main__':
    unittest.main()
