"""Offline regression tests; all state is temporary and desktop calls are mocked."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "bin/apod-wallpaper").read_text()
# Load the production helpers without running the CLI dispatch.
HELPERS = SCRIPT.split('cmd=${1:-update}; shift || true', 1)[0]
ENTRY = {"date": "2026-10-01", "title": "Test picture", "media_type": "image"}
APPLY_MOCKS = """
list_outputs() { echo 'DP-1 0 0 1920 1080 1'; }
render() { echo render >>"$CACHE/events"; echo image >"$4"; }
gdbus() { echo desktop >>"$CACHE/events"; }
kwriteconfig6() { echo lockscreen >>"$CACHE/events"; }
"""


class WallpaperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="apod-test-")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.cache = base / "data/apod-wallpaper"
        self.cache.mkdir(parents=True)
        self.env = {
            **os.environ,
            "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_DATA_HOME": str(base / "data"),
            "ENTRY": json.dumps(ENTRY),
        }
        self.orig = self.cache / "orig-2026-10-01.jpg"
        self.orig.write_text("mock image")

    def run_bash(self, code):
        result = subprocess.run(
            ["bash", "-c", HELPERS + "\n" + code],
            env=self.env, text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_apply_failure_keeps_state_and_suppresses_notification(self):
        previous = {"current": "old.jpg", "meta.json": '{"title":"Old"}',
                    "changed": "yesterday", "mode": "random"}
        for name, content in previous.items():
            (self.cache / name).write_text(content)
        self.run_bash('''
cmd_apply() { return 1; }
prune() { echo unexpected >"$CACHE/pruned"; }
notify() { echo unexpected >"$CACHE/notified"; }
if set_entry "$ENTRY" "$CACHE/orig-2026-10-01.jpg"; then exit 9; fi
''')
        for name, content in previous.items():
            self.assertEqual((self.cache / name).read_text(), content)
        self.assertFalse((self.cache / "notified").exists())
        self.assertFalse((self.cache / "pruned").exists())

    def test_success_publishes_state_after_apply_and_notifies_once(self):
        self.run_bash('''
cmd_apply() {
    [[ $1 == "$CACHE/orig-2026-10-01.jpg" ]] || return 1
    [[ ! -f $CACHE/current ]] || return 1
}
prune() { :; }
notify() { echo notified >>"$CACHE/events"; }
set_entry "$ENTRY" "$CACHE/orig-2026-10-01.jpg"
cmd_apply() { :; }
set_entry "$ENTRY" "$CACHE/orig-2026-10-01.jpg"
''')
        self.assertEqual(json.loads((self.cache / "meta.json").read_text()), ENTRY)
        self.assertEqual((self.cache / "current").read_text().strip(), str(self.orig))
        self.assertEqual((self.cache / "events").read_text(), "notified\n")

    def test_hd_upgrade_does_not_notify_again(self):
        (self.cache / "current").write_text(str(self.cache / "orig-2026-10-01-sd.jpg"))
        self.run_bash('''
cmd_apply() { :; }
prune() { :; }
notify() { echo notified >"$CACHE/notified"; }
set_entry "$ENTRY" "$CACHE/orig-2026-10-01.jpg"
''')
        self.assertFalse((self.cache / "notified").exists())

    def test_show_propagates_failure_without_changing_mode(self):
        self.run_bash('''
candidates() { echo "$ENTRY"; }
resolve() { echo "$1"; }
download() { echo "$CACHE/orig-2026-10-01.jpg"; }
set_entry() { return 1; }
if show latest && echo latest >"$CACHE/mode"; then exit 9; fi
''')
        self.assertFalse((self.cache / "mode").exists())

    def test_desktop_and_lockscreen_failures_are_reported(self):
        for command, message in [("gdbus", "desktop wallpaper"),
                                 ("kwriteconfig6", "lock-screen wallpaper"),
                                 ("list_outputs", "monitor information")]:
            with self.subTest(command=command):
                result = self.run_bash(APPLY_MOCKS + f'''
{command}() {{ return 1; }}
if cmd_apply "$CACHE/orig-2026-10-01.jpg"; then exit 9; fi
''')
                self.assertIn(message, result.stderr)
                self.assertNotIn("applied ", result.stderr)

    def test_partial_render_failure_does_not_change_desktop(self):
        self.run_bash(APPLY_MOCKS + '''
list_outputs() { printf 'DP-1 0 0 1920 1080 1\nDP-2 1920 0 1920 1080 2\n'; }
render() { [[ $4 != *DP-2* ]] || return 1; echo image >"$4"; }
if cmd_apply "$CACHE/orig-2026-10-01.jpg"; then exit 9; fi
''')
        self.assertFalse((self.cache / "events").exists())

    def test_fit_change_rerenders_and_status_finds_new_cache_name(self):
        result = self.run_bash(APPLY_MOCKS + '''
cmd_apply "$CACHE/orig-2026-10-01.jpg"
cmd_apply "$CACHE/orig-2026-10-01.jpg"
FIT_THRESHOLD=1.5
cmd_apply "$CACHE/orig-2026-10-01.jpg"
echo "$CACHE/orig-2026-10-01.jpg" >"$CACHE/current"
echo "$ENTRY" >"$CACHE/meta.json"
cmd_status
''')
        events = (self.cache / "events").read_text().splitlines()
        self.assertEqual(events.count("render"), 2)
        self.assertEqual(len(list(self.cache.glob("render-*.jpg"))), 2)
        self.assertTrue(json.loads(result.stdout)["image"].endswith("-fit1.5.jpg"))

    def test_malformed_api_responses_use_date_fallback(self):
        for response in ["broken", "", "null", "{}", "[null]", "{} {}",
                         json.dumps([ENTRY, None])]:
            with self.subTest(response=response):
                self.env["API_RESPONSE"] = response
                result = self.run_bash('''
api() { printf '%s' "$API_RESPONSE"; }
entries date=2026-10-01 2026-10-01
''')
                self.assertEqual(json.loads(result.stdout), {"date": "2026-10-01"})
                self.assertIn("trying the APOD website instead", result.stderr)

    def test_valid_video_and_empty_results_do_not_trigger_fallback(self):
        for response in ["[]", json.dumps({**ENTRY, "media_type": "video"})]:
            with self.subTest(response=response):
                self.env["API_RESPONSE"] = response
                result = self.run_bash('''
api() { printf '%s' "$API_RESPONSE"; }
entries date=2026-10-01 2026-10-01
''')
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "")

    def test_request_limits_reach_all_network_paths(self):
        self.run_bash('''
CONNECT_MAX=5 REQUEST_MAX=15 DOWNLOAD_MAX=30
curl() { printf '%s\n' "$*" >>"$CACHE/requests"; return 1; }
api date=2026-10-01 || true
page_entry 2026-10-01 || true
fetch https://example.invalid/image.jpg "$CACHE/download.jpg" || true
''')
        requests = (self.cache / "requests").read_text().splitlines()
        self.assertEqual(len(requests), 3)
        for request, limit in zip(requests, [15, 15, 30]):
            self.assertIn("--connect-timeout 5", request)
            self.assertIn(f"--max-time {limit} ", request)


if __name__ == "__main__":
    unittest.main()
