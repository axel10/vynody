#!/usr/bin/env python3
"""Remove specific l10n keys (and their @metadata blocks) from ARB files."""
import glob
import os
import re
import sys

KEYS = [
    "showScanProgressToastSetting",
    "showScanProgressToastSettingDescription",
    "scanToastHiddenHint",
    "filesPreprocessed",
]

L10N_DIR = sys.argv[1]


def strip_key(lines, key):
    """Remove `"key": ...` line and, if present, the following `@key` block."""
    removed = 0
    i = 0
    key_re = re.compile(r'^\s*"%s"\s*:' % re.escape(key))
    meta_re = re.compile(r'^\s*"@%s"\s*:' % re.escape(key))

    while i < len(lines):
        if key_re.match(lines[i]) or meta_re.match(lines[i]):
            is_meta = lines[i].lstrip().startswith('"@')
            # Strip trailing comma so the JSON stays valid when we drop the line.
            lines[i] = re.sub(r',\s*$', '', lines[i])
            del lines[i]
            removed += 1
            if is_meta:
                # The line holding the metadata object's opening `{` is already
                # gone, so start the balance counter at 1 and consume until the
                # matching close brace has been removed too.
                depth = 1
                while i < len(lines) and depth > 0:
                    depth += lines[i].count('{') - lines[i].count('}')
                    del lines[i]
                continue
            continue
        i += 1
    return removed


for path in sorted(glob.glob(os.path.join(L10N_DIR, "*.arb"))):
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()

    before = len(lines)
    total = 0
    for key in KEYS:
        total += strip_key(lines, key)

    if total:
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.writelines(lines)
        print(f"{os.path.basename(path)}: removed {total} block(s), "
              f"{before} -> {len(lines)} lines")