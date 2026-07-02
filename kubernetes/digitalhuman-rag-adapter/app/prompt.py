"""Hot-reloadable digital-human system prompt loader.

The prompt lives in a file mounted from a ConfigMap. The kiosk settings panel
edits that ConfigMap; kubelet propagates the change to the mounted file within
~a minute. We re-read on mtime change so no pod restart is needed.
"""
from __future__ import annotations

import logging
import os
import threading

from .config import settings

log = logging.getLogger("rag-adapter.prompt")

_FALLBACK = (
    "You are a friendly digital human. Speak naturally and concisely. "
    "You are rendered as a CGI face, so express yourself with UneeQ inline "
    "tags such as <uneeq:action_wavehello /> and <uneeq:emotion_joy_normal />."
)


class PromptStore:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._cached = _FALLBACK
        self._mtime = 0.0
        self.reload()

    def reload(self) -> str:
        try:
            mtime = os.path.getmtime(settings.prompt_file)
            if mtime != self._mtime:
                with open(settings.prompt_file, "r", encoding="utf-8") as fh:
                    text = fh.read().strip()
                with self._lock:
                    self._cached = text or _FALLBACK
                    self._mtime = mtime
                log.info("Loaded persona prompt (%d chars)", len(self._cached))
        except FileNotFoundError:
            log.warning("Prompt file %s missing, using fallback", settings.prompt_file)
        except Exception as exc:  # pragma: no cover - runtime guard
            log.warning("Prompt reload failed: %s", exc)
        with self._lock:
            return self._cached

    @property
    def text(self) -> str:
        # Cheap stat-based reload check on every access.
        return self.reload()


prompt_store = PromptStore()
