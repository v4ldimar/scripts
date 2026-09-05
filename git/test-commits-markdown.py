#!/usr/bin/env python3
# Description: Render matching Git commits as Markdown links.
# Requirements: Python 3.8+, Git

"""Render matching Git commits as Markdown links."""

import argparse
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Sequence, Tuple


DEFAULT_PATTERN = r"^tests?(\([^)]*\))?:"
TEST_COMMITS_PATTERN = r"^tests?(\([^)]*\))?:?"


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repo_url",
        help="repository web URL, for example https://github.com/org/repo",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path.cwd(),
        help="local Git repository to inspect (default: current directory)",
    )
    parser.add_argument(
        "--revision",
        default="HEAD",
        help="revision passed to git log (default: HEAD)",
    )
    pattern_group = parser.add_mutually_exclusive_group()
    pattern_group.add_argument(
        "--grep",
        dest="pattern",
        help=r"extended regular expression for commit subjects (default: ^tests?(\([^)]*\))?:)",
    )
    pattern_group.add_argument(
        "--test-commits",
        action="store_true",
        help=r"match legacy test(...) commit prefixes, with or without a trailing colon",
    )
    parser.add_argument(
        "--all-parents",
        action="store_true",
        help="include commits from merged branches instead of following only the first parent",
    )
    return parser.parse_args(argv)


def git_commits(args: argparse.Namespace) -> List[Tuple[str, str]]:
    pattern = (
        TEST_COMMITS_PATTERN
        if args.test_commits
        else args.pattern or DEFAULT_PATTERN
    )
    command = [
        "git",
        "-C",
        str(args.repo),
        "log",
        "--extended-regexp",
        f"--grep={pattern}",
        "--format=%H%x00%s",
    ]
    if not args.all_parents:
        command.append("--first-parent")
    command.append(args.revision)

    try:
        result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as error:
        raise RuntimeError("git is not installed or is not on PATH") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or f"git exited with status {error.returncode}"
        raise RuntimeError(detail) from error

    commits: List[Tuple[str, str]] = []
    for line in result.stdout.splitlines():
        commit_hash, separator, subject = line.partition("\0")
        if not separator:
            raise RuntimeError("git returned an unexpected log format")
        commits.append((commit_hash, subject))
    return commits


def markdown_label(text: str) -> str:
    return text.replace("\\", "\\\\").replace("[", r"\[").replace("]", r"\]")


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    base_url = args.repo_url.rstrip("/")
    if not base_url:
        print("error: repository URL must not be empty", file=sys.stderr)
        return 2

    try:
        commits = git_commits(args)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for commit_hash, subject in commits:
        print(f"- [{markdown_label(subject)}]({base_url}/commit/{commit_hash})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
