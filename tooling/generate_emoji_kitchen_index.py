#!/usr/bin/env python3
"""Generate sharded Google Emoji Kitchen lookup assets.

The output is a set of gzip-compressed JSON files grouped by the first four
hex digits of the base emoji codepoint. Each shard maps:

  baseCodepoint -> otherCodepoint -> gstaticUrl

This keeps runtime lookup fast and avoids any 404 probing.
"""

from __future__ import annotations

import argparse
import gzip
import json
from collections import defaultdict
from pathlib import Path


def _base_prefix(codepoint: str) -> str:
    return codepoint.split("-")[0].lower().rjust(4, "0")[:4]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("metadata", type=Path)
    parser.add_argument("outdir", type=Path)
    args = parser.parse_args()

    with args.metadata.open("r", encoding="utf-8") as fh:
        metadata = json.load(fh)

    shards: dict[str, dict[str, dict[str, str]]] = defaultdict(dict)

    for base_emoji in metadata["knownSupportedEmoji"]:
        item = metadata["data"][base_emoji]
        base_codepoint = item["emojiCodepoint"]
        prefix = _base_prefix(base_codepoint)
        shard = shards[prefix]
        base_entry: dict[str, str] = {}
        for other_codepoint, combinations in item["combinations"].items():
            latest = next(
                (combo for combo in combinations if combo.get("isLatest")),
                max(combinations, key=lambda combo: combo["date"]),
            )
            base_entry[other_codepoint] = latest["gStaticUrl"]
        shard[base_codepoint] = base_entry

    args.outdir.mkdir(parents=True, exist_ok=True)
    for prefix, payload in sorted(shards.items()):
        output = args.outdir / f"{prefix}.json.gz"
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode(
            "utf-8"
        )
        with gzip.open(output, "wb", compresslevel=9) as fh:
            fh.write(raw)


if __name__ == "__main__":
    main()
