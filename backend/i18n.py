"""Language selection for texts the backend itself shows outside the QML UI (MPRIS, notifications)."""
from __future__ import annotations

import os
from typing import Mapping

SUPPORTED = ("en", "ru")
DEFAULT = "en"

TEXT: dict[str, dict[str, str]] = {
    "unknown_author": {"en": "Unknown author", "ru": "Автор неизвестен"},
}


def system_language(env: Mapping[str, str] | None = None) -> str:
    """First supported language from LC_ALL / LC_MESSAGES / LANGUAGE / LANG, otherwise English."""
    env = os.environ if env is None else env
    for name in ("LC_ALL", "LC_MESSAGES", "LANGUAGE", "LANG"):
        for part in str(env.get(name) or "").split(":"):
            code = part.replace("-", "_").split(".")[0].split("@")[0].split("_")[0].lower()
            if code in SUPPORTED: return code
    return DEFAULT


def resolve(preference: object, env: Mapping[str, str] | None = None) -> str:
    return preference if preference in SUPPORTED else system_language(env)


def text(key: str, preference: object = "auto", env: Mapping[str, str] | None = None) -> str:
    return TEXT[key][resolve(preference, env)]
