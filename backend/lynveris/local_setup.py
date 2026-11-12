"""Local-only secret update; retains the existing file and its Windows ACL."""

import os
import re
from pathlib import Path


def update_google_key(path, key):
    if not re.fullmatch(r"[A-Za-z0-9_-]{20,200}", key):
        raise ValueError("Invalid key format")
    path = Path(path)
    existing = path.read_text(encoding="utf-8")
    assignment = f"LYNVERIS_GOOGLE_API_KEY='{key}'"
    pattern = r"^LYNVERIS_GOOGLE_API_KEY=.*$"
    updated = (
        re.sub(pattern, assignment, existing, flags=re.MULTILINE)
        if re.search(pattern, existing, re.MULTILINE)
        else existing.rstrip("\n") + "\n" + assignment + "\n"
    )
    # In-place write preserves the already restricted ACL; no secret backup file is created.
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(updated)
        stream.flush()
        os.fsync(stream.fileno())
