#!/usr/bin/env python3
"""Render the output of one stage as a markdown block.

A stage that declares `input: prev_stage` asks for the work of the stage that
ran before it. The runtime calls this helper once per previous stage and
concatenates the blocks, so the chain reads as a chain.

Usage:
    lib-oracfit-stage-input.py --role NAME [--answer-file FILE] [--artifacts-dir DIR]
                                [--title TEXT] [--max-bytes N] [--max-files N]

`--answer-file` and `--artifacts-dir` are optional: a stage that wrote nothing
still deserves an honest line saying so, never a silent empty block.
The output is a markdown block; the caller pastes it into the composed spec.
"""

import argparse
import os
import sys


def looks_text(path):
    """True when the file reads as text: no NUL byte and valid utf-8 head."""
    try:
        with open(path, "rb") as handle:
            chunk = handle.read(4096)
    except OSError:
        return False
    if b"\0" in chunk:
        return False
    try:
        chunk.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def collect(root):
    """Every file under root, as (relative path, absolute path), sorted."""
    files = []
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            full = os.path.join(dirpath, name)
            files.append((os.path.relpath(full, root), full))
    files.sort()
    return files


def read_text(path, budget):
    """Read at most budget bytes of text from path; returns (text, truncated)."""
    with open(path, "rb") as handle:
        data = handle.read(budget + 1)
    truncated = len(data) > budget
    return data[:budget].decode("utf-8", errors="replace"), truncated


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", default="")
    parser.add_argument("--answer-file", default="")
    parser.add_argument("--artifacts-dir", default="")
    parser.add_argument("--title", default="Previous stage output")
    parser.add_argument("--max-bytes", type=int, default=20000)
    parser.add_argument("--max-files", type=int, default=20)
    args = parser.parse_args()

    print(f"### {args.title}")
    print()
    if args.role:
        print(f"- stage role: `{args.role}`")
    if args.answer_file:
        print(f"- answer file: `{args.answer_file}`")
    if args.artifacts_dir:
        print(f"- artifacts_dir: `{args.artifacts_dir}`")

    answer = ""
    if args.answer_file and os.path.isfile(args.answer_file):
        try:
            answer, truncated = read_text(args.answer_file, args.max_bytes)
        except OSError:
            answer = ""
            truncated = False
        if answer.strip():
            print()
            print("#### Answer of this stage")
            print()
            print("```")
            print(answer.rstrip("\n"))
            if truncated:
                print("[truncated]")
            print("```")

    files = []
    if args.artifacts_dir and os.path.isdir(args.artifacts_dir):
        files = collect(args.artifacts_dir)

    if not answer.strip() and not files:
        print()
        print("- (this stage wrote no output)")
        return 0

    if files:
        print()
        print("#### Files written by this stage")
        shown = files[: args.max_files]
        for rel, full in shown:
            try:
                size = os.path.getsize(full)
            except OSError:
                size = 0
            print(f"- `{rel}` ({size} bytes)")
        if len(files) > len(shown):
            print(f"- ... and {len(files) - len(shown)} more file(s)")

        budget = args.max_bytes
        for rel, full in shown:
            if budget <= 0:
                print()
                print(f"#### {rel}")
                print("- (skipped: the inline budget is exhausted)")
                continue
            if not looks_text(full):
                print()
                print(f"#### {rel}")
                print("- (binary file: not inlined; read it from the artifacts_dir above)")
                continue
            try:
                text, truncated = read_text(full, budget)
            except OSError:
                continue
            budget -= len(text)
            print()
            print(f"#### {rel}")
            print()
            print("```")
            print(text.rstrip("\n"))
            if truncated:
                print("[truncated]")
            print("```")
    return 0


if __name__ == "__main__":
    sys.exit(main())
