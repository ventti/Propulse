#!/usr/bin/env python3
"""
Validate data/help.txt formatting rules.

Run:
  python3 tools/scripts/validate_help_txt.py
"""

from __future__ import annotations

import datetime as _dt
import os
import re
import unittest
from pathlib import Path


_TAG_RE = re.compile(r"<([^>\n]+)>")
_LAST_MODIFIED_RE = re.compile(r"Last modified:\s*(\d{4}-\d{2}-\d{2})")


def _repo_root() -> Path:
    # tools/scripts/validate_help_txt.py -> repo root is two parents up
    return Path(__file__).resolve().parents[2]


def _help_txt_path() -> Path:
    return _repo_root() / "data" / "help.txt"


def _is_comment_line(line: str) -> bool:
    return line.lstrip().startswith(";")


def _iter_non_comment_lines(path: Path) -> list[tuple[int, str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [(idx + 1, line) for idx, line in enumerate(lines) if not _is_comment_line(line)]


def _strip_tags(line: str) -> str:
    return _TAG_RE.sub("", line)


def _collect_anchors(lines: list[tuple[int, str]]) -> set[str]:
    anchors: set[str] = set()
    for _line_no, line in lines:
        for tag in _TAG_RE.findall(line):
            if tag.startswith("#"):
                anchors.add(tag[1:])
    return anchors


def _validate_tag_syntax(tag: str) -> bool:
    if tag in {"c", "hr", "h1", "h2", "h3"}:
        return True
    if re.fullmatch(r"[fb][0-9A-Fa-f]", tag):
        return True
    if tag.startswith("#"):
        return True
    if tag.startswith("@"):
        return len(tag) > 1
    return False


def _parse_link_target(tag: str) -> str:
    # tag is e.g. "@Main=Global Keys" or "@https://example.com"
    assert tag.startswith("@")
    content = tag[1:]
    if "=" in content:
        target, _label = content.split("=", 1)
    else:
        target = content
    return target


class TestHelpTxt(unittest.TestCase):
    def test_tag_validity(self) -> None:
        """
        All tags in visible (non-comment) lines must be known/valid.
        """
        path = _help_txt_path()
        lines = _iter_non_comment_lines(path)

        invalid: list[str] = []

        for line_no, line in lines:
            for tag in _TAG_RE.findall(line):
                if not _validate_tag_syntax(tag):
                    invalid.append(f"L{line_no}: <{tag}> Line: {line}")

        if invalid:
            msg_lines = []
            msg_lines.append("Invalid tags:")
            msg_lines.extend(f"  - {x}" for x in invalid)
            self.fail("\n".join(msg_lines))

    def test_visible_line_max_length(self) -> None:
        """Visible line content must not exceed 77 characters (tags excluded)."""
        path = _help_txt_path()
        lines = _iter_non_comment_lines(path)

        too_long: list[str] = []
        for line_no, line in lines:
            visible = _strip_tags(line)
            if len(visible) > 77:
                too_long.append(f"L{line_no:4d}: {len(visible)} chars, Line: {line}")

        if too_long:
            self.fail("Visible lines exceeding 77 characters:\n" + "\n".join(too_long))

    def test_last_modified_date_matches_file_mtime_date(self) -> None:
        """The 'Last modified' date must match help.txt's filesystem mtime date."""
        path = _help_txt_path()

        last_modified_dates: list[tuple[int, str]] = []
        for line_no, line in _iter_non_comment_lines(path):
            m = _LAST_MODIFIED_RE.search(line)
            if m:
                last_modified_dates.append((line_no, m.group(1)))

        self.assertEqual(
            len(last_modified_dates),
            1,
            f"Expected exactly one 'Last modified' line, found {len(last_modified_dates)}.",
        )

        _line_no, date_str = last_modified_dates[0]
        try:
            help_txt_date = _dt.date.fromisoformat(date_str)
        except ValueError as e:
            self.fail(f"Invalid date format on 'Last modified' line: {date_str} ({e})")

        mtime = os.stat(path).st_mtime
        mtime_date = _dt.datetime.fromtimestamp(mtime).date()
        self.assertEqual(help_txt_date, mtime_date)


if __name__ == "__main__":
    unittest.main()


