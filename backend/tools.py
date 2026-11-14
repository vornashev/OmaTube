from __future__ import annotations

import ctypes
import os
import signal
import sys

# Root-owned system directories. The user's PATH (~/.local/bin, version-manager shims) is never searched: a binary
# planted there would otherwise run next to the YouTube session cookies.
TRUSTED_DIRS = ("/usr/local/bin", "/usr/bin")
TRUSTED_PATH = ":".join(TRUSTED_DIRS)
PR_SET_PDEATHSIG = 1


def system_tool(name: str) -> str:
    """Absolute path of a system program. A missing one yields a path that fails to spawn rather than a PATH lookup."""
    for directory in TRUSTED_DIRS:
        path = os.path.join(directory, name)
        if os.access(path, os.X_OK): return path
    return os.path.join(TRUSTED_DIRS[-1], name)


def venv_tool(name: str) -> str:
    """A program installed by a pinned wheel next to the running interpreter (the backend's own venv).

    Falls back to the system copy so the backend still runs from a source checkout without a venv."""
    path = os.path.join(os.path.dirname(sys.executable), name)
    return path if os.access(path, os.X_OK) else system_tool(name)


def deno() -> str:
    return venv_tool("deno")


def die_with_parent() -> None:
    """preexec_fn for long-lived children: the kernel sends SIGTERM when the backend exits, however it exits.

    The backend runs outside a service manager, so nothing else would reap mpv or yt-dlp after a crash or SIGKILL."""
    try: ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM, 0, 0, 0)
    except (OSError, AttributeError): pass
