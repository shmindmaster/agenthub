"""Which workspace entries a refresh must visit, against real synthetic Git."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from changed_repos import classify, survey, workspace_members

WORKSPACE_FILE = """default_repo: one
repos:
- alias: one
  path: one
- alias: mono-api
  path: mono/services/api
- alias: mono-web
  path: 'mono/apps/web'
- alias: gone
  path: gone
- alias: bare
  path: bare
"""


def git(cwd, *args):
    return subprocess.run(["git", "-c", "user.email=t@example.invalid", "-c", "user.name=t",
                           "-c", "core.autocrlf=false", *args], cwd=cwd, check=True,
                          capture_output=True, text=True).stdout.strip()


def commit(repo, name, text="x\n"):
    path = Path(repo) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", name)
    return git(repo, "rev-parse", "HEAD")


def synced(repo, commit_id):
    index = Path(repo) / ".repowise"
    index.mkdir(parents=True, exist_ok=True)
    (index / "state.json").write_text(json.dumps({"last_sync_commit": commit_id}), encoding="utf-8")


class ChangedRepos(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="changed-repos-")
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name).resolve()
        (self.root / ".repowise-workspace.yaml").write_text(WORKSPACE_FILE, encoding="utf-8")
        self.one = self.root / "one"
        self.mono = self.root / "mono"
        for repo in (self.one, self.mono):
            repo.mkdir()
            git(repo, "init", "-q")
            (repo / ".gitignore").write_text(".repowise/\n", encoding="utf-8")
        self.first = commit(self.one, "a.py")
        commit(self.mono, "services/api/a.py")
        self.mono_first = commit(self.mono, "apps/web/a.py")
        synced(self.one, self.first)
        synced(self.mono / "services/api", self.mono_first)
        synced(self.mono / "apps/web", self.mono_first)
        (self.root / "bare").mkdir()

    def test_members_read_quoted_and_nested_paths(self):
        names = [path.relative_to(self.root).as_posix() for path in workspace_members(self.root)]
        self.assertEqual(names, ["one", "mono/services/api", "mono/apps/web", "gone", "bare"])

    def test_unmoved_entry_is_unchanged(self):
        self.assertEqual(classify(self.one)["status"], "unchanged")

    def test_commit_outside_a_monorepo_entry_leaves_it_unchanged(self):
        commit(self.mono, "apps/web/b.py")
        self.assertEqual(classify(self.mono / "services/api")["status"], "unchanged")
        changed = classify(self.mono / "apps/web")
        self.assertEqual((changed["status"], changed["files"]), ("changed", 1))

    def test_entries_without_work_to_do_are_named(self):
        self.assertEqual(classify(self.root / "gone")["status"], "missing")
        self.assertEqual(classify(self.root / "bare")["status"], "not-indexed")

    def test_vanished_sync_commit_needs_attention_not_a_silent_skip(self):
        synced(self.one, "0" * 40)
        self.assertEqual(classify(self.one)["status"], "attention")

    def test_survey_counts_every_entry_and_lists_smallest_first(self):
        commit(self.one, "b.py")
        commit(self.mono, "apps/web/b.py")
        commit(self.mono, "apps/web/c.py")
        report = survey(self.root)
        self.assertEqual(report["entries"], 5)
        self.assertEqual(report["counts"],
                         {"changed": 2, "unchanged": 1, "missing": 1, "not-indexed": 1})
        self.assertEqual([item["path"] for item in report["changed"]],
                         [str(self.one), str(self.mono / "apps/web")])


class UnreadableStateTest(unittest.TestCase):
    def test_corrupt_state_needs_attention_and_does_not_raise(self):
        for content in ("", "[]", "{broken"):
            with tempfile.TemporaryDirectory() as folder:
                repo = Path(folder) / "one"
                (repo / ".repowise").mkdir(parents=True)
                (repo / ".repowise" / "state.json").write_text(content, encoding="utf-8")
                self.assertEqual(classify(repo)["status"], "attention")


if __name__ == "__main__":
    unittest.main()
