from __future__ import annotations

import os

# Root-owned system directories. The user's PATH (~/.local/bin, version-manager shims) is never searched: a binary
# planted there would otherwise run next to the YouTube session cookies.
TRUSTED_DIRS = ("/usr/local/bin", "/usr/bin")
TRUSTED_PATH = ":".join(TRUSTED_DIRS)


def system_tool(name: str) -> str:
    """Absolute path of a system program. A missing one yields a path that fails to spawn rather than a PATH lookup."""
    for directory in TRUSTED_DIRS:
        path = os.path.join(directory, name)
        if os.access(path, os.X_OK): return path
    return os.path.join(TRUSTED_DIRS[-1], name)
