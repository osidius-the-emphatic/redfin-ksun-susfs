#!/usr/bin/env python3
"""Validate owner metadata in a newc cpio stream from standard input."""

import argparse
import sys


HEADER_SIZE = 110
CPIO_MAGICS = (b"070701", b"070702")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="require every non-trailer newc cpio entry to have one UID:GID"
    )
    parser.add_argument("--expect", default="0:0", metavar="UID:GID")
    args = parser.parse_args()
    try:
        expected_uid, expected_gid = (int(value) for value in args.expect.split(":", 1))
    except ValueError:
        parser.error("--expect must use decimal UID:GID")

    data = sys.stdin.buffer.read()
    offset = 0
    total = 0
    mismatches = []
    while True:
        if offset + HEADER_SIZE > len(data):
            print("cpio stream ended without TRAILER!!!", file=sys.stderr)
            return 2
        header = data[offset:offset + HEADER_SIZE]
        if header[:6] not in CPIO_MAGICS:
            print(f"bad cpio magic at offset {offset}: {header[:6]!r}", file=sys.stderr)
            return 2
        try:
            fields = [int(header[6 + 8 * index:14 + 8 * index], 16) for index in range(13)]
        except ValueError:
            print(f"bad cpio header at offset {offset}", file=sys.stderr)
            return 2
        mode, uid, gid, size, name_size = fields[1], fields[2], fields[3], fields[6], fields[11]
        name_end = offset + HEADER_SIZE + name_size
        if name_size < 1 or name_end > len(data):
            print(f"bad cpio name size at offset {offset}", file=sys.stderr)
            return 2
        name = data[offset + HEADER_SIZE:name_end - 1].decode("utf-8", "replace")
        if name == "TRAILER!!!":
            break
        total += 1
        if (uid, gid) != (expected_uid, expected_gid):
            mismatches.append((name, uid, gid, mode))
        data_start = (name_end + 3) & ~3
        offset = (data_start + size + 3) & ~3

    if mismatches:
        print(
            f"{len(mismatches)} of {total} entries are not owned by "
            f"{expected_uid}:{expected_gid}:",
            file=sys.stderr,
        )
        for name, uid, gid, mode in mismatches[:20]:
            print(f"  {name}: {uid}:{gid} mode={mode:o}", file=sys.stderr)
        return 1
    print(f"OK: all {total} cpio entries are owned by {expected_uid}:{expected_gid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
