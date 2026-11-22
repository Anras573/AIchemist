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
        self.env["AICHEMIST_GATE"] = "1"
        # Isolate from the developer's own git config (aichemist.gate etc.).
        self.env["GIT_CONFIG_GLOBAL"] = os.devnull
        self.env["GIT_CONFIG_NOSYSTEM"] = "1"

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def gate(self, command, extra_env=None, cwd=None, drop_env=()):
        env = dict(self.env)
        env.update(extra_env or {})
        for k in drop_env:
            env.pop(k, None)
        payload = json.dumps({"cwd": cwd or self.repo, "tool_input": {"command": command}})
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

    # --- review feedback ---------------------------------------------------

    def test_opt_in_required(self):
        self.write("Makefile", "test:\n\tfalse\n")
        r = self.gate("git commit -m x", drop_env=["AICHEMIST_GATE"])
        self.assertEqual(r.returncode, 0, "gate must be off by default")
        run(["git", "config", "aichemist.gate", "true"], self.repo, env=self.env)
        r = self.gate("git commit -m x", drop_env=["AICHEMIST_GATE"])
        self.assertEqual(r.returncode, 2, "git config aichemist.gate enables it")

    def test_repo_marker_file_does_not_enable(self):
        self.write("Makefile", "test:\n\tfalse\n")
        for name in (".aichemist-gate", ".aichemist.json"):
            self.write(name, "true")
        r = self.gate("git commit -m x", drop_env=["AICHEMIST_GATE"])
        self.assertEqual(r.returncode, 0)

    def test_dry_run_only_exempts_its_own_command(self):
        self.write("Makefile", "test:\n\tfalse\n")
        self.assertEqual(self.gate("git commit --dry-run").returncode, 0)
        self.assertEqual(self.gate("git push -n origin main").returncode, 0)
        self.assertEqual(self.gate("npm pack --dry-run && git push").returncode, 2)
        self.assertEqual(self.gate("git push --dry-run; git commit -m x").returncode, 2)

    def test_dash_C_gates_the_target_repo(self):
        other = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, other, True)
        run(["git", "init", "-q"], other)
        # cwd repo is broken, target repo is fine -> allowed.
        self.write("Makefile", "test:\n\tfalse\n")
        with open(os.path.join(other, "Makefile"), "w") as f:
            f.write("test:\n\ttrue\n")
        self.assertEqual(self.gate("git -C %s commit -m x" % other).returncode, 0)
        # target repo is broken, cwd repo is fine -> blocked.
        with open(os.path.join(other, "Makefile"), "w") as f:
            f.write("test:\n\tfalse\n")
        self.write("Makefile", "test:\n\ttrue\n")
        r = self.gate("git -C %s commit -m x" % other)
        self.assertEqual(r.returncode, 2, r.stderr)

    def test_dash_C_relative_path(self):
        sub = os.path.join(self.repo, "sub")
        os.mkdir(sub)
        run(["git", "init", "-q"], sub)
        with open(os.path.join(sub, "Makefile"), "w") as f:
            f.write("test:\n\tfalse\n")
        self.write("Makefile", "test:\n\ttrue\n")
        self.assertEqual(self.gate("git -C sub commit -m x").returncode, 2)

    def test_cache_respects_overrides(self):
        self.write("Makefile", "test:\n\tfalse\n")
        self.assertEqual(self.gate("git commit -m x", {"AICHEMIST_GATE_TEST": ""}).returncode, 0)
        # Same tree, no override: must run the tests (not reuse the cached pass).
        self.assertEqual(self.gate("git commit -m x").returncode, 2)

    def test_python_without_tests_or_config_is_not_blocked(self):
        if not shutil.which("pytest"):
            self.skipTest("pytest not installed")
        self.write("requirements.txt", "requests\n")
        self.write("app.py", "print('hi')\n")
        self.assertEqual(self.gate("git commit -m x").returncode, 0)

    def test_pytest_collecting_nothing_passes(self):
        if not shutil.which("pytest"):
            self.skipTest("pytest not installed")
        self.write("pytest.ini", "[pytest]\n")
        self.write("app.py", "print('hi')\n")
        r = self.gate("git commit -m x", {"AICHEMIST_GATE_FORMAT": ""})
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_pytest_failure_still_blocks(self):
        if not shutil.which("pytest"):
            self.skipTest("pytest not installed")
        self.write("pytest.ini", "[pytest]\n")
        self.write("test_x.py", "def test_x():\n    assert False\n")
        r = self.gate("git commit -m x", {"AICHEMIST_GATE_FORMAT": ""})
        self.assertEqual(r.returncode, 2)

    def test_formatters_only_run_when_configured(self):
        fake = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, fake, True)
        for tool in ("ruff", "black"):
            path = os.path.join(fake, tool)
            with open(path, "w") as f:
                f.write("#!/bin/sh\nexit 1\n")
            os.chmod(path, 0o755)
        env = {"PATH": fake + os.pathsep + os.environ["PATH"]}
        self.write("requirements.txt", "requests\n")
        self.assertEqual(self.gate("git commit -m x", env).returncode, 0)
        self.write("pyproject.toml", "[tool.ruff]\nline-length = 88\n")
        self.assertEqual(self.gate("git commit -m x", env).returncode, 2)


if __name__ == "__main__":
    unittest.main()
