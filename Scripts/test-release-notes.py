#!/usr/bin/env python3
"""Regression checks for changelog-based release notes."""

from pathlib import Path
import runpy
import unittest


ROOT = Path(__file__).resolve().parent.parent
render = runpy.run_path(str(ROOT / "Scripts/generate-release-notes.py"))["render"]
FIXTURE = """# Changelog
## [Unreleased]
- Future change
## [1.2.3] - 2026-09-16
### 追加
- New feature
```markdown
## [9.9.9]
```
## [1.2.2] - 2026-09-15
- Previous change
[1.2.3]: https://example.com/compare/v1.2.2...v1.2.3
[1.2.2]: https://example.com/previous
"""


class ReleaseNotesTests(unittest.TestCase):
    def test_extracts_only_target_and_preserves_code(self):
        notes = render(FIXTURE, "v1.2.3")
        self.assertIn("### 追加\n- New feature", notes)
        self.assertIn("```markdown\n## [9.9.9]\n```", notes)
        self.assertIn("**Full Changelog**: https://example.com/compare/v1.2.2...v1.2.3", notes)
        self.assertNotIn("Future change", notes)
        self.assertNotIn("Previous change", notes)
        self.assertNotIn("[1.2.2]:", notes)

    def test_prerelease_and_final_section(self):
        source = "## [1.0.0-alpha.1] - 2026-09-16\n- Preview\n\n[1.0.0-alpha.1]: https://example.com/preview\n"
        self.assertEqual(render(source, "v1.0.0-alpha.1"), "- Preview\n\n**Full Changelog**: https://example.com/preview\n")

    def test_missing_empty_duplicate_and_missing_link_fail(self):
        for source, tag in [
            (FIXTURE, "v1.2.30"),
            (FIXTURE.replace("- New feature", "").replace("```markdown\n## [9.9.9]\n```", ""), "v1.2.3"),
            (FIXTURE + "\n## [1.2.3]\n- Duplicate", "v1.2.3"),
            (FIXTURE.replace("[1.2.3]:", "[other]:"), "v1.2.3"),
            (FIXTURE, "1.2.3"),
        ]:
            with self.subTest(tag=tag, source=source):
                with self.assertRaises(ValueError):
                    render(source, tag)

    def test_current_changelog(self):
        source = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        for tag in ["v0.2.4", "v0.2.3", "v0.1.0-alpha.1"]:
            with self.subTest(tag=tag):
                self.assertIn("**Full Changelog**:", render(source, tag))


if __name__ == "__main__":
    unittest.main()
