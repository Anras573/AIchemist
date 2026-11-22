import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)

import scratchpad as sp  # noqa: E402


class FakeClock(object):
    def __init__(self, now=1000.0):
        self.now = now

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class TempDirCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="scratchpad-test-")
        self.addCleanup(shutil.rmtree, self.root, True)


class RendererTests(unittest.TestCase):
    def test_headings_get_slugs_and_duplicates_are_numbered(self):
        result = sp.render_markdown("# Goals\n\n## Goals\n")
        self.assertEqual([h[2] for h in result.headings], ["goals", "goals-2"])
        self.assertIn('id="goals-2"', result.body)

    def test_text_is_escaped_and_raw_html_is_not_passed_through(self):
        body = sp.render_markdown("<script>alert(1)</script> & **bold**").body
        self.assertNotIn("<script>", body)
        self.assertIn("&lt;script&gt;", body)
        self.assertIn("<strong>bold</strong>", body)

    def test_unsafe_link_scheme_is_dropped(self):
        body = sp.render_markdown("[x](javascript:alert(1)) [ok](https://example.com)").body
        self.assertNotIn("javascript:", body)
        self.assertIn('href="https://example.com"', body)

    def test_inline_code_is_not_formatted_further(self):
        body = sp.render_markdown("use `**not bold**` here").body
        self.assertIn("<code>**not bold**</code>", body)

    def test_fenced_code_block_is_escaped(self):
        body = sp.render_markdown("```\n<b>x</b>\n```").body
        self.assertIn("<pre><code>&lt;b&gt;x&lt;/b&gt;</code></pre>", body)

    def test_nested_lists(self):
        body = sp.render_markdown("- a\n  - b\n- c").body
        self.assertEqual(body, "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>")

    def test_ordered_list(self):
        self.assertIn("<ol><li>one</li><li>two</li></ol>", sp.render_markdown("1. one\n2. two").body)

    def test_list_type_change_at_same_indent_starts_a_new_list(self):
        body = sp.render_markdown("- a\n1. b\n2. c").body
        self.assertEqual(body, "<ul><li>a</li></ul><ol><li>b</li><li>c</li></ol>")

    def test_table(self):
        body = sp.render_markdown("| a | b |\n|---|---|\n| 1 | 2 |").body
        self.assertIn("<th>a</th>", body)
        self.assertIn("<td>2</td>", body)

    def test_paragraph_lines_are_joined(self):
        self.assertEqual(sp.render_markdown("one\ntwo").body, "<p>one two</p>")

    def test_valid_decision(self):
        md = ":::decision retry-limit\nproposal: Cap at 3\nalternative: Unlimited\npick: proposal\n:::"
        result = sp.render_markdown(md)
        self.assertEqual(len(result.decisions), 1)
        decision = result.decisions[0]
        self.assertIsNone(decision["error"])
        self.assertEqual(decision["pick"], "proposal")
        self.assertIn("agent's pick", result.body)

    def test_malformed_decisions_render_an_error_card_and_page_still_renders(self):
        cases = [
            ":::decision\nproposal: a\nalternative: b\n:::",              # no id
            ":::decision x\nproposal: a\n:::",                            # no alternative
            ":::decision x\nproposal: a\nalternative: b\npick: maybe\n:::",  # bad pick
            ":::decision x\nproposal: a\nalternative: b\nbogus line\n:::",   # unknown line
            ":::decision x\nproposal: a\nalternative: b",                 # unterminated
        ]
        for md in cases:
            result = sp.render_markdown(md + "\n\n# After")
            self.assertTrue(result.decisions[0]["error"], md)
            self.assertIn("sp-error", result.body)
            self.assertEqual(result.headings[0][1], "After")

    def test_duplicate_decision_id_is_an_error(self):
        block = ":::decision x\nproposal: a\nalternative: b\n:::\n"
        result = sp.render_markdown(block + block)
        self.assertIsNone(result.decisions[0]["error"])
        self.assertIn("duplicate", result.decisions[1]["error"])

    def test_decision_card_marks_answer_and_resolution(self):
        decision = sp.parse_decision(":::decision x", ["proposal: a", "alternative: b", "pick: proposal"], True)
        answer = {"answer": "alternative"}
        waiting = sp.decision_card(decision, answer, False, "pad", "page")
        self.assertIn("waiting for the agent", waiting)
        self.assertIn("sp-answer", waiting)
        done = sp.decision_card(decision, answer, True, "pad", "page")
        self.assertIn("Resolved: alternative", done)
        self.assertNotIn("sp-answer", done)


class StoreTests(TempDirCase):
    def make_store(self, clock=None):
        return sp.Store(self.root, clock or FakeClock())

    def test_ids_increment_per_prefix(self):
        store = self.make_store()
        self.assertEqual(store.add_comment("p", "a", "A", "one")["id"], "c-1")
        self.assertEqual(store.add_comment("p", "a", "A", "two")["id"], "c-2")
        self.assertEqual(store.add_decision_answer("p", "x", "proposal")["id"], "d-1")

    def test_replay_derives_replies_and_handled(self):
        store = self.make_store()
        store.add_comment("p", "a", "A", "one")
        store.add_comment("p", "a", "A", "two")
        store.add_reply("c-1", "answer")
        store.mark_handled("c-1")
        state = store.state()
        self.assertTrue(state.get("c-1")["handled"])
        self.assertEqual(state.get("c-1")["replies"][0]["text"], "answer")
        self.assertEqual([i["id"] for i in state.unhandled()], ["c-2"])

    def test_latest_decision_answer_wins(self):
        store = self.make_store()
        store.add_decision_answer("p", "x", "proposal")
        store.add_decision_answer("p", "x", "alternative")
        self.assertEqual(store.state().decision_answer("p", "x")["answer"], "alternative")

    def test_corrupt_and_partial_lines_are_skipped(self):
        store = self.make_store()
        store.add_comment("p", "a", "A", "one")
        with open(store.log_path, "ab") as handle:
            handle.write(b"not json\n")
            handle.write(b'{"type": "comment", "id": "c-9", "te')  # partial, no newline
        state = store.state()
        self.assertEqual(state.bad_lines, 1)
        self.assertEqual([i["id"] for i in state.all_items()], ["c-1"])

    def test_reply_to_unknown_item_is_ignored_by_replay(self):
        store = self.make_store()
        store.add_reply("c-99", "orphan")
        self.assertEqual(store.state().all_items(), [])

    def test_concurrent_appends_get_unique_ids(self):
        store = sp.Store(self.root)
        threads = [threading.Thread(target=store.add_comment, args=("p", "a", "A", "t%d" % n))
                   for n in range(20)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        ids = [i["id"] for i in store.state().all_items()]
        self.assertEqual(len(ids), 20)
        self.assertEqual(len(set(ids)), 20)

    def test_detached_comments_are_shown_at_page_bottom(self):
        store = self.make_store()
        store.add_comment("1-a", "old-heading", "Old heading", "orphaned")
        page = sp.render_page("pad", "1-a", "# New heading\n", store.state(), ["1-a"])
        self.assertIn("Detached comments", page)
        self.assertIn("orphaned", page)


class WaitTests(TempDirCase):
    def test_returns_after_quiet_window(self):
        clock = FakeClock()
        store = sp.Store(self.root, clock)
        store.add_comment("p", "a", "A", "hi")      # ts = 1000
        clock.now = 1003
        calls = []

        def sleep(seconds):
            calls.append(seconds)
            clock.now += seconds

        items = sp.wait_for_batch(store, quiet=10, timeout=60, clock=clock, sleep=sleep, poll=1)
        self.assertEqual([i["id"] for i in items], ["c-1"])
        self.assertAlmostEqual(clock.now, 1010, delta=1)
        self.assertTrue(calls)

    def test_new_comment_restarts_the_quiet_window(self):
        clock = FakeClock()
        store = sp.Store(self.root, clock)
        store.add_comment("p", "a", "A", "first")
        state = {"sleeps": 0}

        def sleep(seconds):
            clock.now += seconds
            state["sleeps"] += 1
            if state["sleeps"] == 8:
                store.add_comment("p", "a", "A", "second")

        items = sp.wait_for_batch(store, quiet=10, timeout=120, clock=clock, sleep=sleep, poll=1)
        self.assertEqual(len(items), 2)
        self.assertGreaterEqual(clock.now, 1008 + 10)

    def test_timeout_returns_empty_batch(self):
        clock = FakeClock()
        store = sp.Store(self.root, clock)
        items = sp.wait_for_batch(store, quiet=10, timeout=5, clock=clock, sleep=clock.sleep, poll=1)
        self.assertEqual(items, [])

    def test_handled_items_do_not_trigger(self):
        clock = FakeClock()
        store = sp.Store(self.root, clock)
        store.add_comment("p", "a", "A", "hi")
        store.mark_handled("c-1")
        clock.now += 100
        self.assertEqual(sp.wait_for_batch(store, 1, 3, clock, clock.sleep, 1), [])


class PathTests(TempDirCase):
    def test_missing_pad_reports_not_found_before_resolving(self):
        with self.assertRaises(sp.ScratchpadError) as ctx:
            sp.resolve_pad(self.root, "nope")
        self.assertIn("Pad not found", str(ctx.exception))

    def test_invalid_pad_name_is_rejected(self):
        with self.assertRaises(sp.ScratchpadError):
            sp.resolve_pad(self.root, "../etc")

    def test_default_pad_is_most_recently_modified(self):
        for name in ("2026-01-01-old", "2026-01-02-new"):
            os.makedirs(os.path.join(self.root, name))
        os.utime(os.path.join(self.root, "2026-01-01-old"), (1, 1))
        self.assertEqual(sp.resolve_pad(self.root), "2026-01-02-new")

    def test_symlink_escaping_the_home_is_not_a_pad(self):
        outside = tempfile.mkdtemp(prefix="scratchpad-outside-")
        self.addCleanup(shutil.rmtree, outside, True)
        link = os.path.join(self.root, "2026-01-01-escape")
        try:
            os.symlink(outside, link, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks are not available here")
        os.makedirs(os.path.join(self.root, "2026-01-02-real"))
        self.assertEqual(sp.list_pads(self.root), ["2026-01-02-real"])
        with self.assertRaises(sp.ScratchpadError) as ctx:
            sp.resolve_pad(self.root, "2026-01-01-escape")
        self.assertIn("outside SCRATCHPAD_HOME", str(ctx.exception))

    def test_pad_slug_is_ascii_and_handles_danish_letters(self):
        self.assertEqual(sp.pad_slug(u"Révision"), "revision")
        self.assertEqual(sp.pad_slug(u"Rødgrød på æble"), "roedgroed-paa-aeble")
        self.assertEqual(sp.pad_slug(u"My Topic!"), "my-topic")
        self.assertEqual(sp.pad_slug(u"日本"), "pad")
        for topic in (u"Révision", u"Æble", u"日本"):
            self.assertTrue(sp.NAME_RE.match("2026-11-22-" + sp.pad_slug(topic)), topic)

    def test_log_tail(self):
        path = os.path.join(self.root, "log.txt")
        self.assertEqual(sp.log_tail(path), "(no log)")
        with open(path, "w") as handle:
            handle.write("\n".join("line %d" % n for n in range(20)))
        self.assertEqual(sp.log_tail(path, 2), "line 18\nline 19")

    def test_inside(self):
        child = os.path.join(self.root, "a")
        os.makedirs(child)
        self.assertTrue(sp.inside(self.root, child))
        self.assertFalse(sp.inside(child, self.root))

    def test_natural_page_order(self):
        pad = os.path.join(self.root, "pad")
        os.makedirs(pad)
        for name in ("10-z.md", "2-b.md", "1-a.md", "notes.txt"):
            open(os.path.join(pad, name), "w").close()
        self.assertEqual(sp.list_pages(pad), ["1-a", "2-b", "10-z"])


class ServerIntegrationTests(TempDirCase):
    """Real server on a random port against a temp SCRATCHPAD_HOME."""

    def setUp(self):
        TempDirCase.setUp(self)
        self.pad = "2026-11-22-demo"
        self.pad_dir = os.path.join(self.root, self.pad)
        os.makedirs(self.pad_dir)
        with open(os.path.join(self.pad_dir, "1-overview.md"), "w") as handle:
            handle.write("# Goals\n\nText.\n\n"
                         ":::decision retry-limit\nproposal: Cap at 3\nalternative: Unlimited\npick: proposal\n:::\n")
        self.server = sp.ScratchpadServer(("127.0.0.1", 0), self.root)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.daemon = True
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    def url(self, path):
        return "http://127.0.0.1:%d%s" % (self.port, path)

    def get(self, path, headers=None):
        request = urllib.request.Request(self.url(path), headers=headers or {})
        with urllib.request.urlopen(request) as response:
            return response.status, response.read().decode("utf-8")

    def post(self, path, payload, headers=None):
        merged = {"Content-Type": "application/json"}
        merged.update(headers or {})
        request = urllib.request.Request(self.url(path), json.dumps(payload).encode("utf-8"),
                                         merged, method="POST")
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode("utf-8")

    def test_health(self):
        self.assertEqual(self.get("/health"), (200, "scratchpad-ok pid=%d" % os.getpid()))

    def test_server_identity_helpers(self):
        self.assertEqual(sp.server_pid(self.port), os.getpid())
        self.assertTrue(sp.server_healthy(self.port))
        self.assertTrue(sp.server_healthy(self.port, os.getpid()))
        self.assertFalse(sp.server_healthy(self.port, os.getpid() + 1))
        self.assertIsNone(sp.server_pid(1))  # nothing listens there

    def test_full_comment_and_decision_cycle(self):
        status, body = self.get("/%s/1-overview" % self.pad)
        self.assertEqual(status, 200)
        self.assertIn('id="goals"', body)
        self.assertIn("sp-answer", body)

        status, body = self.post("/api/%s/comments" % self.pad,
                                 {"page": "1-overview", "anchor": "goals", "heading": "Goals",
                                  "text": "Why <b>this</b>?"})
        self.assertEqual((status, json.loads(body)["id"]), (201, "c-1"))
        status, body = self.post("/api/%s/decisions" % self.pad,
                                 {"page": "1-overview", "decision": "retry-limit", "answer": "alternative"})
        self.assertEqual((status, json.loads(body)["id"]), (201, "d-1"))

        store = sp.Store(self.pad_dir)
        self.assertEqual([i["id"] for i in store.state().unhandled()], ["c-1", "d-1"])

        store.add_reply("c-1", "Because.")
        store.mark_handled("c-1")
        store.mark_handled("d-1")
        _, page = self.get("/%s/1-overview" % self.pad)
        self.assertIn("Because.", page)
        self.assertIn("Why &lt;b&gt;this&lt;/b&gt;?", page)   # comment text is escaped
        self.assertIn("Resolved: alternative", page)

    def test_rejects_bad_requests(self):
        base = "/api/%s/comments" % self.pad
        good = {"page": "1-overview", "anchor": "goals", "heading": "Goals", "text": "hi"}
        self.assertEqual(self.post(base, dict(good, text="  "))[0], 400)
        self.assertEqual(self.post(base, dict(good, anchor="bad anchor!"))[0], 400)
        self.assertEqual(self.post(base, dict(good, page="../x"))[0], 404)
        self.assertEqual(self.post(base, dict(good, page="missing"))[0], 404)
        self.assertEqual(self.post("/api/nope/comments", good)[0], 404)
        self.assertEqual(self.post(base, good, {"Origin": "http://evil.example"})[0], 403)
        self.assertEqual(self.post(base, good, {"Host": "evil.example"})[0], 403)
        self.assertEqual(self.post(base, good, {"Origin": "http://localhost:not-a-port"})[0], 403)
        self.assertEqual(self.post(base, good, {"Origin": "http://localhost:99999999"})[0], 403)
        self.assertEqual(self.post("/api/%s/decisions" % self.pad,
                                   {"page": "1-overview", "decision": "nope", "answer": "proposal"})[0], 404)
        self.assertEqual(self.post("/api/%s/decisions" % self.pad,
                                   {"page": "1-overview", "decision": "retry-limit", "answer": "maybe"})[0], 400)

    def test_requires_json_content_type(self):
        request = urllib.request.Request(self.url("/api/%s/comments" % self.pad), b"{}",
                                         {"Content-Type": "text/plain"}, method="POST")
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(request)
        self.assertEqual(ctx.exception.code, 415)

    def test_path_traversal_and_non_markdown_are_not_served(self):
        with open(os.path.join(self.pad_dir, "secret.txt"), "w") as handle:
            handle.write("secret")
        for path in ("/%s/secret.txt" % self.pad, "/%s/..%%2f..%%2fx" % self.pad, "/..", "/%s/nope" % self.pad):
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                self.get(path)
            self.assertEqual(ctx.exception.code, 404, path)

    def test_foreign_host_header_is_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self.get("/health", {"Host": "evil.example"})
        self.assertEqual(ctx.exception.code, 403)

    def test_index_pages_render(self):
        self.assertIn(self.pad, self.get("/")[1])
        self.assertIn("1-overview", self.get("/%s/" % self.pad)[1])


class CliTests(TempDirCase):
    def run_cli(self, *args, **kwargs):
        env = dict(os.environ)
        env["SCRATCHPAD_HOME"] = self.root
        process = subprocess.Popen([sys.executable, os.path.join(TOOLS, "scratchpad.py")] + list(args),
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        out, err = process.communicate(kwargs.get("stdin", "").encode("utf-8"))  # always UTF-8 bytes
        return process.returncode, out.decode("utf-8"), err.decode("utf-8")

    def test_new_inbox_reply_done_flow(self):
        code, out, _ = self.run_cli("new", "My Topic!")
        self.assertEqual(code, 0)
        pad = out.splitlines()[0].split()[1]
        self.assertTrue(pad.endswith("-my-topic"))
        sp.Store(os.path.join(self.root, pad)).add_comment("1-a", "goals", "Goals", "hello")

        code, out, _ = self.run_cli("inbox")
        self.assertIn("c-1", out)
        self.assertIn("hello", out)

        self.assertEqual(self.run_cli("reply", "c-1", "got", "it")[0], 0)
        self.assertEqual(self.run_cli("reply", "c-1", "-", stdin="from stdin")[0], 0)
        self.assertIn("> agent: got it", self.run_cli("inbox")[1])
        self.assertEqual(self.run_cli("done", "c-1")[0], 0)
        self.assertIn("unhandled: 0", self.run_cli("inbox")[1])
        self.assertIn("c-1", self.run_cli("inbox", "--all")[1])

    def test_reply_from_stdin_keeps_utf8(self):
        _, out, _ = self.run_cli("new", "t")
        pad = out.splitlines()[0].split()[1]
        sp.Store(os.path.join(self.root, pad)).add_comment("1-a", "goals", "Goals", "hi")
        self.assertEqual(self.run_cli("reply", "c-1", "-", stdin=u"naïve — ok")[0], 0)
        replies = sp.Store(os.path.join(self.root, pad)).state().get("c-1")["replies"]
        self.assertEqual(replies[0]["text"], u"naïve — ok")

    def test_unknown_item_and_pad_exit_non_zero(self):
        self.run_cli("new", "t")
        code, _, err = self.run_cli("reply", "c-9", "x")
        self.assertEqual(code, 1)
        self.assertIn("Unknown item c-9", err)
        code, _, err = self.run_cli("inbox", "--pad", "missing")
        self.assertEqual(code, 1)
        self.assertIn("Pad not found", err)

    def test_wait_times_out_with_empty_batch(self):
        self.run_cli("new", "t")
        code, out, _ = self.run_cli("wait", "--quiet", "1", "--timeout", "1")
        self.assertEqual(code, 0)
        self.assertIn("no items", out)

    def test_check_reports_malformed_decision(self):
        _, out, _ = self.run_cli("new", "t")
        pad = out.splitlines()[0].split()[1]
        with open(os.path.join(self.root, pad, "1-a.md"), "w") as handle:
            handle.write(":::decision x\nproposal: a\n:::\n")
        code, out, _ = self.run_cli("check")
        self.assertEqual(code, 1)
        self.assertIn("missing alternative", out)

    def test_new_with_non_ascii_topic_creates_a_discoverable_pad(self):
        code, out, _ = self.run_cli("new", u"Révision")
        self.assertEqual(code, 0)
        pad = out.splitlines()[0].split()[1]
        self.assertTrue(pad.endswith("-revision"))
        self.assertIn(pad, self.run_cli("pages")[1])

    def test_stop_never_signals_a_pid_from_a_stale_record(self):
        # Record this very process as the "server" on a port nothing listens on.
        with open(os.path.join(self.root, sp.SERVER_FILE), "w") as handle:
            json.dump({"pid": os.getpid(), "port": 1}, handle)
        code, out, _ = self.run_cli("stop")
        self.assertEqual(code, 0)
        self.assertIn("stale", out)
        self.assertFalse(os.path.exists(os.path.join(self.root, sp.SERVER_FILE)))

    def test_stop_does_not_signal_when_the_server_on_the_port_has_another_pid(self):
        # A scratchpad server is alive on the recorded port, but it is not the recorded PID
        # (PID and port both reused). The recorded process must be left alone.
        bystander = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        self.addCleanup(lambda: (bystander.kill(), bystander.wait()))
        server = sp.ScratchpadServer(("127.0.0.1", 0), self.root)
        thread = threading.Thread(target=server.serve_forever)
        thread.daemon = True
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with open(os.path.join(self.root, sp.SERVER_FILE), "w") as handle:
            json.dump({"pid": bystander.pid, "port": server.server_address[1]}, handle)
        code, out, _ = self.run_cli("stop")
        self.assertEqual(code, 0)
        self.assertIn("stale", out)
        self.assertIsNone(bystander.poll())  # still running

    def test_remove_server_file_only_removes_its_own_record(self):
        path = os.path.join(self.root, sp.SERVER_FILE)
        with open(path, "w") as handle:
            json.dump({"pid": 111, "port": 4747}, handle)
        sp.remove_server_file(self.root, (222, 4747))   # another server shutting down
        self.assertTrue(os.path.exists(path))
        sp.remove_server_file(self.root, (111, 4748))   # right pid, wrong port
        self.assertTrue(os.path.exists(path))
        sp.remove_server_file(self.root, (111, 4747))   # the owner
        self.assertFalse(os.path.exists(path))

    def test_new_refuses_a_pad_symlink_that_points_outside_the_home(self):
        outside = tempfile.mkdtemp(prefix="scratchpad-outside-")
        self.addCleanup(shutil.rmtree, outside, True)
        name = "%s-escape" % sp.datetime.date.today().isoformat()
        try:
            os.symlink(outside, os.path.join(self.root, name), target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks are not available here")
        code, _, err = self.run_cli("new", "escape")
        self.assertEqual(code, 1)
        self.assertIn("outside SCRATCHPAD_HOME", err)

    def test_new_refuses_a_pad_path_that_is_a_file(self):
        name = "%s-clash" % sp.datetime.date.today().isoformat()
        with open(os.path.join(self.root, name), "w") as handle:
            handle.write("not a directory")
        code, _, err = self.run_cli("new", "clash")
        self.assertEqual(code, 1)
        self.assertIn("not a directory", err)

    def test_start_status_stop_round_trip(self):
        env_port = "47%02d" % (os.getpid() % 90 + 10)
        code, out, err = self.run_cli("start", "--port", env_port)
        try:
            self.assertEqual(code, 0, err)
            self.assertIn("http://127.0.0.1:", out)
            code, out, _ = self.run_cli("start", "--port", env_port)
            self.assertIn("running:", out)          # idempotent
            self.assertIn("running", self.run_cli("status")[1])
            self.assertTrue(os.path.isfile(os.path.join(self.root, sp.SERVER_LOG)))
        finally:
            self.run_cli("stop")
        self.assertIn("not running", self.run_cli("status")[1])


if __name__ == "__main__":
    unittest.main()
