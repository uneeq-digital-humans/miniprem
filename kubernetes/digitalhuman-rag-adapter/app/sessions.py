"""Short-term conversational memory backed by Redis.

Keyed by the UneeQ sessionId so a digital human can remember context within a
visit ("my name is Doug" -> later "what's my name?"). If Redis is not
configured or unreachable, the store degrades to a no-op: conversations still
work, they just become stateless.
"""
from __future__ import annotations

import json
import logging
from typing import List, Optional

from .config import settings

log = logging.getLogger("rag-adapter.sessions")

try:  # redis is optional at runtime
    import redis.asyncio as aioredis  # type: ignore
except Exception:  # pragma: no cover - import guard
    aioredis = None  # type: ignore

Message = dict  # {"role": "user"|"assistant", "content": str}


class SessionStore:
    def __init__(self) -> None:
        self._client = None
        if settings.redis_url and aioredis is not None:
            try:
                self._client = aioredis.from_url(
                    settings.redis_url, decode_responses=True
                )
                log.info("Session memory enabled (Redis at %s)", settings.redis_url)
            except Exception as exc:  # pragma: no cover - connection guard
                log.warning("Redis init failed, sessions disabled: %s", exc)
        else:
            log.info("Session memory disabled (no REDIS_URL)")

    @property
    def enabled(self) -> bool:
        return self._client is not None

    @staticmethod
    def _key(session_id: str) -> str:
        return f"rag-adapter:session:{session_id}"

    async def history(self, session_id: Optional[str]) -> List[Message]:
        if not (self.enabled and session_id):
            return []
        try:
            raw = await self._client.lrange(self._key(session_id), 0, -1)
            return [json.loads(item) for item in raw]
        except Exception as exc:  # pragma: no cover - runtime guard
            log.warning("history() failed for %s: %s", session_id, exc)
            return []

    async def append(
        self, session_id: Optional[str], user_text: str, assistant_text: str
    ) -> None:
        if not (self.enabled and session_id):
            return
        try:
            key = self._key(session_id)
            pipe = self._client.pipeline()
            pipe.rpush(key, json.dumps({"role": "user", "content": user_text}))
            pipe.rpush(
                key, json.dumps({"role": "assistant", "content": assistant_text})
            )
            # Keep only the most recent N turns (2 messages per turn).
            pipe.ltrim(key, -2 * settings.max_history_turns, -1)
            pipe.expire(key, settings.session_ttl_s)
            await pipe.execute()
        except Exception as exc:  # pragma: no cover - runtime guard
            log.warning("append() failed for %s: %s", session_id, exc)

    async def ping(self) -> bool:
        if not self.enabled:
            return False
        try:
            return bool(await self._client.ping())
        except Exception:
            return False

    # --- Persona prompt override (kiosk-editable, survives pod restarts) -----
    _PROMPT_KEY = "rag-adapter:persona-prompt"

    async def get_prompt_override(self) -> Optional[str]:
        """Return the kiosk-edited persona prompt, or None to use the default."""
        if not self.enabled:
            return None
        try:
            return await self._client.get(self._PROMPT_KEY)
        except Exception as exc:  # pragma: no cover - runtime guard
            log.warning("get_prompt_override failed: %s", exc)
            return None

    async def set_prompt_override(self, text: str) -> bool:
        """Persist a kiosk-edited persona prompt (no expiry)."""
        if not self.enabled:
            return False
        try:
            await self._client.set(self._PROMPT_KEY, text)
            return True
        except Exception as exc:  # pragma: no cover - runtime guard
            log.warning("set_prompt_override failed: %s", exc)
            return False

    async def clear_prompt_override(self) -> bool:
        """Revert to the ConfigMap default persona prompt."""
        if not self.enabled:
            return False
        try:
            await self._client.delete(self._PROMPT_KEY)
            return True
        except Exception as exc:  # pragma: no cover - runtime guard
            log.warning("clear_prompt_override failed: %s", exc)
            return False


store = SessionStore()
