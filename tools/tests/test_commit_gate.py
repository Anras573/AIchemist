import json
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(os.path.dirname(HERE), "commit-gate.sh")


def run(cmd, cwd, **kw):
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, universal_newlines=True, **kw)


class CommitGateTest(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp()
        run(["git", "init", "-q"], self.repo)
        run(["git", "config", "user.email", "t@example.com"], self.repo)
        run(["git", "config", "user.name", "t"], self.repo)
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith("AICHEMIST_GATE")}

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def gate(self, command, extra_env=None):
        env = dict(self.env)
        env.update(extra_env or {})
        payload = json.dumps({"cwd": self.repo, "tool_input": {"command": command}})
        return subprocess.run(["bash", GATE], input=payload, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True, env=env)

    def write(self, name, text):
        with open(os.path.join(self.repo, name), "w") as f:
            f.write(text)

    def test_ignores_unrelated_commands(self):
        self.write("Makefile", "test:\n\tfalse\n")
        self.assertEqual(self.gate("ls -la").returncode, 0)
        self.assertEqual(self.gate("git status").returncode, 0)

    def test_blocks_commit_when_makefile_test_fails(self):
        self.write("Makefile", "build:\n\ttrue\ntest:\n\techo boom; false\n")
        r = self.gate('git commit -m "x"')
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("test", r.stderr)
        self.assertIn("boom", r.stderr)

    def test_blocks_push_and_chained_commands(self):
        self.write("Makefile", "build:\n\tfalse\n")
        self.assertEqual(self.gate("git push origin main").returncode, 2)
        self.assertEqual(self.gate("git add -A && git -C . commit -m x").returncode, 2)

    def test_passes_when_all_green_and_caches(self):
        marker = self.repo + ".ran"
        self.addCleanup(lambda: os.path.exists(marker) and os.remove(marker))
        self.write("Makefile",
                   "build:\n\ttrue\ntest:\n\techo x >> %s\nformat-check:\n\ttrue\n" % marker)
        self.assertEqual(self.gate("git commit -m x").returncode, 0)
        self.assertEqual(self.gate("git push").returncode, 0)
        with open(marker) as f:
            self.assertEqual(len(f.read().splitlines()), 1)

    def test_format_failure_blocks(self):
        self.write("Makefile", "format-check:\n\tfalse\n")
        r = self.gate("git commit -m x")
        self.assertEqual(r.returncode, 2)
        self.assertIn("format", r.stderr)

    def test_env_overrides_and_skip(self):
        self.write("Makefile", "test:\n\tfalse\n")
        self.assertEqual(self.gate("git commit -m x", {"AICHEMIST_GATE_TEST": ""}).returncode, 0)
        self.assertEqual(self.gate("git commit -m x", {"AICHEMIST_GATE_SKIP": "1"}).returncode, 0)
        r = self.gate("git commit -m x", {"AICHEMIST_GATE_BUILD": "exit 3"})
        self.assertEqual(r.returncode, 2)

    def test_go_project_detected(self):
        if not shutil.which("go"):
            self.skipTest("go not installed")
        self.write("go.mod", "module x\n\ngo 1.20\n")
        self.write("main.go", "package main\nfunc main() {  }\n")
        r = self.gate("git commit -m x")
        self.assertEqual(r.returncode, 2)
        self.assertIn("gofmt", r.stderr)

    def test_node_project_detected(self):
        if not shutil.which("npm"):
            self.skipTest("npm not installed")
        self.write("package.json", json.dumps({"scripts": {"test": "exit 1"}}))
        os.mkdir(os.path.join(self.repo, "node_modules"))
        r = self.gate("git commit -m x")
        self.assertEqual(r.returncode, 2)
        self.assertIn("node test", r.stderr)

    def test_unknown_project_and_non_git_fail_open(self):
        self.assertEqual(self.gate("git commit -m x").returncode, 0)
        d = tempfile.mkdtemp()
        try:
            payload = json.dumps({"cwd": d, "tool_input": {"command": "git commit"}})
            r = subprocess.run(["bash", GATE], input=payload, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, universal_newlines=True, env=self.env)
            self.assertEqual(r.returncode, 0)
        finally:
            shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
