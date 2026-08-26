#!/usr/bin/env python3
"""Resolve one GGUF quant (and optional mmproj) from Hugging Face model API JSON.

Output is tab-separated: role, remote_path, size_bytes, lfs_sha256.
The first row is always the model's primary GGUF (or first shard).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Iterable, Sequence


@dataclass(frozen=True)
class FileInfo:
    path: str
    size: int
    sha256: str

    @property
    def name(self) -> str:
        return PurePosixPath(self.path).name


SPLIT_RE = re.compile(r"^(?P<prefix>.*?)-(?P<index>\d{5})-of-(?P<count>\d{5})\.gguf$", re.IGNORECASE)


def fail(message: str) -> "NoReturn":
    print(f"hf-resolve: {message}", file=sys.stderr)
    raise SystemExit(2)


def safe_text(value: object) -> str:
    text = "" if value is None else str(value)
    if any(ch in text for ch in ("\t", "\n", "\r", "\x00")):
        fail("repository metadata contains an unsafe filename or checksum")
    return text


def read_files(path: str) -> list[FileInfo]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot parse Hugging Face API JSON: {exc}")

    if isinstance(payload, dict) and payload.get("error"):
        fail(f"Hugging Face API error: {payload.get('error')}")
    siblings = payload.get("siblings") if isinstance(payload, dict) else None
    if not isinstance(siblings, list):
        fail("API response has no 'siblings' file list")

    result: list[FileInfo] = []
    for item in siblings:
        if not isinstance(item, dict):
            continue
        remote = safe_text(item.get("rfilename"))
        if not remote.lower().endswith(".gguf"):
            continue
        if remote.startswith("/") or ".." in PurePosixPath(remote).parts:
            fail(f"unsafe repository path: {remote}")
        lfs = item.get("lfs") if isinstance(item.get("lfs"), dict) else {}
        raw_size = item.get("size", lfs.get("size", 0))
        try:
            size = int(raw_size or 0)
        except (TypeError, ValueError):
            size = 0
        sha = safe_text(lfs.get("sha256", lfs.get("oid", ""))).lower()
        if sha.startswith("sha256:"):
            sha = sha.removeprefix("sha256:")
        if sha and not re.fullmatch(r"[0-9a-f]{64}", sha):
            sha = ""
        result.append(FileInfo(remote, max(size, 0), sha))

    if not result:
        fail("repository contains no GGUF files")
    return result


def is_mmproj(item: FileInfo) -> bool:
    return "mmproj" in item.name.lower()


def is_auxiliary(item: FileInfo) -> bool:
    lower = item.name.lower()
    return is_mmproj(item) or "imatrix" in lower or lower.endswith(".metadata.gguf")


def matches_pattern(item: FileInfo, pattern: str) -> bool:
    return fnmatch.fnmatchcase(item.path, pattern) or fnmatch.fnmatchcase(item.name, pattern)


def quant_matches(item: FileInfo, quant: str) -> bool:
    # Tokens such as Q4_K_M and MXFP4 must be separated from neighboring letters
    # or digits. A following split suffix is accepted.
    escaped = re.escape(quant.upper())
    return re.search(rf"(?:^|[-_/]){escaped}(?=$|[-_. /])", item.path.upper()) is not None


def rank_candidate(item: FileInfo, quant: str, pattern: str) -> tuple[int, int, int, str]:
    name_upper = item.name.upper()
    quant_upper = quant.upper()
    exact_quant = 0 if name_upper.endswith(f"-{quant_upper}.GGUF") else 1
    exact_pattern = 0 if pattern and item.name == pattern else 1
    split_penalty = 1 if SPLIT_RE.match(item.name) else 0
    return (exact_pattern, exact_quant, split_penalty, len(item.path), item.path)


def expand_split(selected: FileInfo, all_files: Sequence[FileInfo]) -> list[FileInfo]:
    match = SPLIT_RE.match(selected.name)
    if not match:
        return [selected]
    parent = str(PurePosixPath(selected.path).parent)
    if parent == ".":
        parent = ""
    prefix = match.group("prefix")
    count = int(match.group("count"))
    group: list[tuple[int, FileInfo]] = []
    for item in all_files:
        item_parent = str(PurePosixPath(item.path).parent)
        if item_parent == ".":
            item_parent = ""
        candidate = SPLIT_RE.match(item.name)
        if not candidate or item_parent != parent:
            continue
        if candidate.group("prefix") != prefix or int(candidate.group("count")) != count:
            continue
        group.append((int(candidate.group("index")), item))
    group.sort(key=lambda pair: pair[0])
    indices = [index for index, _ in group]
    if indices != list(range(1, count + 1)):
        fail(f"split GGUF is incomplete: expected {count} shards, found indices {indices}")
    return [item for _, item in group]


def pick_primary(files: Sequence[FileInfo], exact_file: str, pattern: str, quant: str) -> list[FileInfo]:
    candidates = [item for item in files if not is_auxiliary(item)]
    if exact_file:
        exact = [item for item in candidates if item.path == exact_file or item.name == exact_file]
        if not exact:
            fail(f"requested GGUF file was not found: {exact_file}")
        selected = sorted(exact, key=lambda item: (len(item.path), item.path))[0]
        return expand_split(selected, files)

    if pattern and pattern != "-":
        patterned = [item for item in candidates if matches_pattern(item, pattern)]
        if patterned:
            candidates = patterned
        elif not quant:
            fail(f"no GGUF matches catalog pattern: {pattern}")

    if quant:
        quanted = [item for item in candidates if quant_matches(item, quant)]
        if not quanted:
            fail(f"no model GGUF matches quant '{quant}'")
        candidates = quanted

    if not candidates:
        fail("no model GGUF matched the requested selection")

    selected = sorted(candidates, key=lambda item: rank_candidate(item, quant, pattern))[0]
    return expand_split(selected, files)


def pick_mmproj(files: Sequence[FileInfo], pattern: str) -> list[FileInfo]:
    candidates = [item for item in files if is_mmproj(item)]
    if pattern and pattern != "-":
        matched = [item for item in candidates if matches_pattern(item, pattern)]
        if matched:
            candidates = matched
    if not candidates:
        return []

    def mmproj_rank(item: FileInfo) -> tuple[int, int, str]:
        upper = item.name.upper()
        if "F16" in upper or "BF16" in upper:
            quality = 0
        elif "Q8_0" in upper:
            quality = 1
        elif "Q5" in upper or "Q6" in upper:
            quality = 2
        else:
            quality = 3
        return (quality, len(item.path), item.path)

    return expand_split(sorted(candidates, key=mmproj_rank)[0], files)


def emit(role: str, items: Iterable[FileInfo]) -> None:
    for item in items:
        print(f"{role}\t{item.path}\t{item.size}\t{item.sha256 or '-'}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", required=True, help="Hugging Face API JSON file")
    parser.add_argument("--file", default="", help="exact GGUF path or basename")
    parser.add_argument("--pattern", default="", help="catalog filename glob")
    parser.add_argument("--quant", default="", help="quant token such as Q4_K_M")
    parser.add_argument("--include-mmproj", action="store_true")
    parser.add_argument("--mmproj-pattern", default="")
    args = parser.parse_args()

    files = read_files(args.json)
    primary = pick_primary(files, args.file, args.pattern, args.quant)
    emit("model", primary)
    if args.include_mmproj:
        emit("mmproj", pick_mmproj(files, args.mmproj_pattern))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
