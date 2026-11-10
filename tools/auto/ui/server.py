#!/usr/bin/env python3
"""Fishing AUTO-002: local human-approval web console (Python stdlib only).

Intentionally fail-closed when AUTO-001 file formats cannot be verified.
Does not call LLMs or modify agent code, tasks, or requirements.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hmac
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
import threading
import urllib.parse
import webbrowser

MAX_BODY = 24_000
MAX_EVIDENCE = 150_000
ID_RE = re.compile(r'^[A-Z][A-Z0-9_-]{2,60}$')
SAFE_NAME = {'plan.md', 'report.md', 'BLOCK_REPORT.md', 'human_review.md'}
STATE_ALLOW_APPROVE = {'awaiting_approval'}
SET_STATUS = {'ready', 'awaiting_approval', 'exec_ready', 'held', 'in_review', 'done', 'blocked', 'Blocked'}


def atomic_write(path: Path, content: bytes):
    import tempfile
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name + '.', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, path.stat().st_mode & 0o777 if path.exists() else 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_text(path: Path, cap=MAX_EVIDENCE):
    if not path.is_file():
        return None
    with path.open('rb') as f:
        out = f.read(cap + 1)
    return out[:cap].decode('utf-8', errors='replace') + ('\n[显示已截断]' if len(out) > cap else '')


def queue_list(data):
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for k in ('tasks', 'tickets', 'queue', 'items', 'jobs', 'work_items'):
            if isinstance(data.get(k), list):
                return data[k]
    return None


def task_id(item):
    for k in ('id', 'task_id', 'ticket_id'):
        if isinstance(item.get(k), str) and item[k]:
            return item[k]
    return None


def task_paths(item):
    for k in ('allowed_files', 'allow_files', 'allowed_paths', 'scope'):
        v = item.get(k)
        if isinstance(v, list) and v and all(isinstance(x, str) for x in v):
            return v
        if isinstance(v, str) and v.strip():
            return [v.strip()]
    return None


def safe_test_cmd(cmd: str) -> bool:
    """Conservative syntactic gate, not a shell sandbox. Runner performs tests."""
    if not (1 <= len(cmd) <= 512) or any(x in cmd for x in ('\n', '\r', '\x00', '`', '$', ';', '&', '|', '>', '<')):
        return False
    try:
        argv = shlex.split(cmd)
    except ValueError:
        return False
    if not argv:
        return False
    exe = Path(argv[0]).name
    if exe not in ('python', 'python3', 'godot', 'godot4', 'Godot'):
        return False
    if exe in ('python', 'python3'):
        if '-c' in argv or '-i' in argv:
            return False
        if '-m' in argv and (argv.index('-m') + 1 >= len(argv) or argv[argv.index('-m') + 1] not in ('unittest', 'pytest')):
            return False
    return True


def paths_safe(paths):
    for p in paths:
        if not p or p.startswith('/') or '\\' in p or p.startswith('~') or '..' in Path(p).parts or '\n' in p:
            return False
    return True


class Service:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.queue = self.root / 'tools/auto/queue.json'
        self.ledger = self.root / 'tasks/APPROVALS.md'
        self.runner = self.root / 'tools/auto/runner.py'
        self.token = secrets.token_urlsafe(40)
        self.csrf = secrets.token_urlsafe(32)
        self.lock = threading.Lock()
        self.child = None
        self.child_file = None
        self.http = None

    def actual_queue(self):
        raw = self.queue.read_bytes()
        data = json.loads(raw)
        items = queue_list(data)
        if items is None or any(not isinstance(i, dict) or not task_id(i) for i in items):
            raise ValueError('queue.json 结构与当前适配器不兼容；已禁止审批写入')
        if len({task_id(i) for i in items}) != len(items):
            raise ValueError('工单 ID 重复，已禁止审批写入')
        return data, items, raw

    def info(self):
        try:
            _, items, _ = self.actual_queue()
            out = []
            for t in items:
                tid = task_id(t)
                out.append({'id': tid, 'status': t.get('status', 'unknown'),
                            'allowed_files': task_paths(t) or [], 'test_cmd': t.get('test_cmd') or '',
                            'title': t.get('title') or t.get('name') or tid,
                            'plan_available': (self.root / 'tasks/evidence' / tid / 'plan.md').is_file()})
            return {'ok': True, 'items': out, 'error': None, 'project': str(self.root),
                    'runner_exists': self.runner.is_file(), 'ledger_exists': self.ledger.is_file(),
                    'running': self.child is not None and self.child.poll() is None}
        except Exception as e:
            return {'ok': False, 'error': str(e), 'items': [], 'project': str(self.root),
                    'running': self.child is not None and self.child.poll() is None}

    def evidence(self, tid, name):
        if not ID_RE.fullmatch(tid) or name not in SAFE_NAME:
            raise ValueError('不允许访问的工单或证据文件')
        return read_text(self.root / 'tasks/evidence' / tid / name) or '暂无此文件。'

    def shell(self, *args, timeout=20):
        return subprocess.run(list(args), cwd=str(self.root), capture_output=True,
                              text=True, timeout=timeout, env=os.environ.copy())

    def command(self, mode: str):
        if mode not in ('status', 'pause', 'resume', 'check'):
            raise ValueError('不允许的命令')
        if not self.runner.is_file():
            raise ValueError('找不到 AUTO-001 runner.py')
        if mode in ('pause', 'resume') and self.child is not None and self.child.poll() is None:
            # Can be called; runner controls only next work item.
            pass
        p = self.shell(sys.executable, str(self.runner), mode, timeout=30)
        return {'returncode': p.returncode, 'output': (p.stdout + p.stderr)[-14000:]}

    def logs(self):
        if not self.runner.is_file():
            return '缺少 runner.py'
        try:
            p = self.shell(sys.executable, str(self.runner), 'log', '-n', '80', timeout=20)
            return (p.stdout + p.stderr)[-22000:]
        except Exception as e:
            return f'日志获取失败：{e}'

    def external_runner_alive(self):
        """Best-effort desktop guard; AUTO-001 owns its actual cross-process lock."""
        try:
            p = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True, timeout=5)
            for line in p.stdout.splitlines():
                m = re.match(r"\s*(\d+)\s+(.+)", line)
                if m and int(m.group(1)) != os.getpid():
                    cmd = m.group(2)
                    if "runner.py start" in cmd and "ps -axo" not in cmd:
                        return True
        except Exception:
            return True  # fail closed
        return False

    def approve(self, body):
        tid, who, note, confirm = [str(body.get(k, '')).strip() for k in ('id', 'by', 'notes', 'confirm')]
        cmd = str(body.get('test_cmd', '')).strip()
        if not ID_RE.fullmatch(tid) or confirm != tid:
            raise ValueError('请输入与所选工单完全相同的确认 ID')
        if not re.fullmatch(r'[\w .\-]{2,60}', who, re.UNICODE):
            raise ValueError('审批人名称格式错误')
        if not (1 <= len(note) <= 400) or '\n' in note or '\r' in note:
            raise ValueError('审批备注要求 1–400 字且不能包含换行')
        if not safe_test_cmd(cmd):
            raise ValueError('测试命令不符合安全格式（仅支持 Godot/Python 单条测试命令，无 shell 连接符）')
        with self.lock:
            if (self.child is not None and self.child.poll() is None) or self.external_runner_alive():
                raise ValueError('检测到 Runner 正在运行，请等待其结束后审批')
            if not self.ledger.is_file():
                raise ValueError('找不到人工审批账本')
            oldledger = self.ledger.read_bytes()
            ledger = oldledger.decode('utf-8')
            if 'BEGIN-EXAMPLE-ONLY' not in ledger and 'BEGIN-APPROVAL ' not in ledger:
                raise ValueError('未识别出审批账本标记；必须先核对原有格式')
            if re.search(r'^BEGIN-APPROVAL\s+ID=' + re.escape(tid) + r'\s+PHASE=B\s*$', ledger, re.M):
                raise ValueError('该工单已有批准记录，拒绝重复批准')
            data, items, oldq = self.actual_queue()
            item = next((x for x in items if task_id(x) == tid), None)
            if item is None or item.get('status') not in STATE_ALLOW_APPROVE:
                raise ValueError('工单不在 awaiting_approval 状态')
            paths = task_paths(item)
            if not paths or not paths_safe(paths):
                raise ValueError('工单缺少明确安全的 allowed_files/scope，请手动核对 Runner 格式')
            if not (self.root / 'tasks/evidence' / tid / 'plan.md').is_file():
                raise ValueError('找不到计划文件 plan.md，禁止盲目批准')
            if 'test_cmd' not in item:
                raise ValueError('队列没有 test_cmd 字段，格式未兼容，禁止修改')
            if re.search(r'[\r\n]', tid + who + note):
                raise ValueError('审批内容包含异常字符')
            scope = ', '.join(paths)
            block = (f'\nBEGIN-APPROVAL ID={tid} PHASE=B\nAPPROVED\nby: {who}\n'
                     f'date: {dt.date.today().isoformat()}\nscope: {scope}\nnotes: {note}\nEND-APPROVAL\n')
            item['test_cmd'] = cmd
            item['status'] = 'exec_ready'
            newq = (json.dumps(data, indent=2, ensure_ascii=False) + '\n').encode('utf-8')
            newledger = (ledger.rstrip() + '\n' + block).encode('utf-8')
            # Snapshot/check then write only when expected files remain unchanged.
            if self.queue.read_bytes() != oldq or self.ledger.read_bytes() != oldledger:
                raise ValueError('文件在审批时发生变化，请刷新页面后重试')
            try:
                atomic_write(self.queue, newq)
                atomic_write(self.ledger, newledger)
                p = self.command('check')
                if p['returncode'] != 0:
                    raise RuntimeError('Runner check 拒绝审批：' + p['output'][-1600:])
            except Exception as err:
                if self.queue.read_bytes() == newq:
                    atomic_write(self.queue, oldq)
                if self.ledger.read_bytes() == newledger:
                    atomic_write(self.ledger, oldledger)
                raise ValueError('审批未通过，已尝试回滚：' + str(err)) from err
            # Human approval and queue change are committed atomically in Git history.
            p = self.shell('git', 'commit', '--only', '-m', f'Human approve {tid} Phase B', '--',
                           str(self.queue.relative_to(self.root)), str(self.ledger.relative_to(self.root)), timeout=30)
            if p.returncode != 0:
                raise ValueError('审批文件已写入且检查通过，但 Git 提交失败；请先处理 Git 再启动 Runner：' + p.stderr[-1000:])
            return {'status': 'exec_ready', 'commit': p.stdout[-1000:], 'check': 'PASS'}

    def start(self):
        with self.lock:
            if (self.child is not None and self.child.poll() is None) or self.external_runner_alive():
                raise ValueError('检测到 Runner 正在运行，禁止重复启动')
            info = self.info()
            if not info['ok']:
                raise ValueError(info['error'])
            if not any(t['status'] in ('ready', 'exec_ready') for t in info['items']):
                raise ValueError('没有 ready 或 exec_ready 工单，禁止空跑')
            changes = self.shell('git', 'status', '--porcelain', timeout=10).stdout.splitlines()
            unsafe = [line for line in changes if not (line.startswith('?? tasks/evidence/') or line.startswith('?? tools/auto/ui/'))]
            if unsafe:
                raise ValueError('存在尚未核对的 Git 改动，请先处理：' + '; '.join(unsafe[:6]))
            if not self.runner.is_file():
                raise ValueError('找不到 runner.py')
            # Run log is outside Git-tracked project, no direct shell commands from user input.
            import tempfile
            self.child_file = Path(tempfile.gettempdir()) / f'fishing-auto002-{os.getpid()}-runner.log'
            with self.child_file.open('ab') as f:
                self.child = subprocess.Popen([sys.executable, str(self.runner), 'start'],
                                              cwd=str(self.root), stdin=subprocess.DEVNULL,
                                              stdout=f, stderr=subprocess.STDOUT,
                                              start_new_session=True)
            return {'pid': self.child.pid, 'log': str(self.child_file)}


class Handler(BaseHTTPRequestHandler):
    server_version = 'FishingApproval/0.1'
    def log_message(self, fmt, *args):
        pass

    @property
    def svc(self):
        return self.server.svc

    def respond(self, code, data, content_type='application/json; charset=utf-8', headers=None):
        content = (json.dumps(data, ensure_ascii=False).encode('utf8') if not isinstance(data, bytes) else data)
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', "default-src 'self'; img-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(content)

    def valid_host(self):
        return self.headers.get('Host') == f'127.0.0.1:{self.server.server_port}'

    def is_auth(self):
        cookie = SimpleCookie()
        try:
            cookie.load(self.headers.get('Cookie', ''))
        except Exception:
            return False
        return 'fishing_auth' in cookie and hmac.compare_digest(cookie['fishing_auth'].value, self.svc.token)

    def valid_origin(self):
        return self.headers.get('Origin') == f'http://127.0.0.1:{self.server.server_port}'

    def do_GET(self):
        if not self.valid_host():
            return self.respond(403, {'error': '拒绝非本机 Host'})
        path = urllib.parse.urlsplit(self.path)
        if path.path == '/login':
            token = urllib.parse.parse_qs(path.query).get('token', [''])[0]
            if not hmac.compare_digest(token, self.svc.token):
                return self.respond(403, {'error': '无效登录令牌'})
            self.send_response(303)
            self.send_header('Location', '/')
            self.send_header('Set-Cookie', f'fishing_auth={self.svc.token}; HttpOnly; SameSite=Strict; Path=/')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            return
        if not self.is_auth():
            return self.respond(403, {'error': '请通过启动终端提供的专用 URL 访问'})
        if path.path == '/':
            html = (Path(__file__).parent / 'static/index.html').read_bytes()
            return self.respond(200, html, 'text/html; charset=utf-8')
        if path.path == '/app.js':
            return self.respond(200, (Path(__file__).parent / 'static/app.js').read_bytes(), 'text/javascript; charset=utf-8')
        if path.path == '/api/status':
            obj = self.svc.info()
            obj['csrf'] = self.svc.csrf
            return self.respond(200, obj)
        if path.path == '/api/evidence':
            args = urllib.parse.parse_qs(path.query)
            try:
                return self.respond(200, {'text': self.svc.evidence(args.get('id',[''])[0], args.get('name',[''])[0])})
            except Exception as e:
                return self.respond(400, {'error': str(e)})
        if path.path == '/api/logs':
            return self.respond(200, {'text': self.svc.logs()})
        if path.path == '/api/runner-status':
            return self.respond(200, self.svc.command('status'))
        return self.respond(404, {'error': 'Not found'})

    def do_POST(self):
        if not self.valid_host() or not self.is_auth() or not self.valid_origin():
            return self.respond(403, {'error': '认证或 Origin 检查失败'})
        if not hmac.compare_digest(self.headers.get('X-CSRF-Token',''), self.svc.csrf):
            return self.respond(403, {'error': 'CSRF 检查失败'})
        n = self.headers.get('Content-Length','')
        if not n.isdigit() or int(n) > MAX_BODY:
            return self.respond(413, {'error': '请求过大'})
        try:
            body = json.loads(self.rfile.read(int(n)))
            if not isinstance(body, dict):
                raise ValueError('数据格式错误')
            path = urllib.parse.urlsplit(self.path).path
            if path == '/api/approve':
                r = self.svc.approve(body)
            elif path == '/api/start':
                r = self.svc.start()
            elif path == '/api/pause':
                r = self.svc.command('pause')
            elif path == '/api/resume':
                r = self.svc.command('resume')
            else:
                return self.respond(404, {'error': 'Not found'})
            return self.respond(200, {'ok': True, 'result': r})
        except Exception as e:
            return self.respond(400, {'ok': False, 'error': str(e)})


def main():
    parser = argparse.ArgumentParser(description='Fishing local approval dashboard')
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--no-browser', action='store_true')
    a = parser.parse_args()
    svc = Service(a.project)
    if not svc.queue.is_file() or not svc.runner.is_file():
        parser.error(f'AUTO-001 不在 {svc.root} 下，检查 --project 路径')
    http = ThreadingHTTPServer(('127.0.0.1', a.port), Handler)
    http.svc = svc
    svc.http = http
    url = f'http://127.0.0.1:{http.server_port}/login?token={svc.token}'
    print('Fishing AUTO-002 本地审批面板', flush=True)
    print('项目:', svc.root, flush=True)
    print('浏览器地址:', url, flush=True)
    print('关闭服务: 在这个终端按 Ctrl+C。已启动的 Runner 不会被强制终止。', flush=True)
    if not a.no_browser:
        webbrowser.open(url)
    try:
        http.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        http.server_close()


if __name__ == '__main__':
    main()
