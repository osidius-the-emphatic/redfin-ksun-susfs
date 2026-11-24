#!/usr/bin/env python3
"""Carry relevant AVB footer metadata from stock `avbtool info_image` output."""

import re
import sys


PROPERTY = re.compile(r"^\s*Prop:\s+(\S+)\s+->\s+'(.*)'\s*$")
ROLLBACK_INDEX = re.compile(r"^Rollback Index:\s+(\d+)\s*$")
ROLLBACK_LOCATION = re.compile(r"^Rollback Index Location:\s+(\d+)\s*$")
FLAGS = re.compile(r"^Flags:\s+(\d+)\s*$")


def parse(path):
    properties = []
    rollback_index = None
    rollback_location = None
    flags = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            match = PROPERTY.match(line)
            if match:
                properties.append((match.group(1), match.group(2)))
                continue
            match = ROLLBACK_INDEX.match(line)
            if match and rollback_index is None:
                rollback_index = int(match.group(1))
                continue
            match = ROLLBACK_LOCATION.match(line)
            if match and rollback_location is None:
                rollback_location = int(match.group(1))
                continue
            match = FLAGS.match(line)
            if match and flags is None:
                flags = int(match.group(1))
    return properties, rollback_index, rollback_location, flags


def main(argv) -> int:
    if len(argv) == 3 and argv[1] == "args":
        properties, rollback_index, rollback_location, flags = parse(argv[2])
        arguments = []
        for key, value in properties:
            arguments.extend(("--prop", f"{key}:{value}"))
        if rollback_index is not None:
            arguments.extend(("--rollback_index", str(rollback_index)))
        if rollback_location is not None:
            arguments.extend(("--rollback_index_location", str(rollback_location)))
        if flags is not None:
            arguments.extend(("--flags", str(flags)))
        sys.stdout.buffer.write(b"".join(argument.encode() + b"\0" for argument in arguments))
        print(
            "avb: carrying "
            f"{len(properties)} stock properties, rollback_index={rollback_index}, "
            f"rollback_index_location={rollback_location}, flags={flags}",
            file=sys.stderr,
        )
        return 0
    if len(argv) == 4 and argv[1] == "compare":
        stock = parse(argv[2])
        final = parse(argv[3])
        if sorted(stock[0]) != sorted(final[0]) or stock[1:] != final[1:]:
            print(f"AVB mismatch: stock={stock!r} final={final!r}", file=sys.stderr)
            return 1
        print(
            "OK: AVB properties, rollback index/location, and flags match stock "
            f"({len(stock[0])} properties)"
        )
        return 0
    print(
        "Usage: avb_stock_props.py args STOCK_INFO | "
        "avb_stock_props.py compare STOCK_INFO FINAL_INFO",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
