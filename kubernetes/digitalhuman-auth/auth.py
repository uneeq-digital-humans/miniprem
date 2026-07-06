"""MiniPrem kiosk settings auth — a small black-box JWT issuer.

Runs ON the kiosk server (localhost only). The kiosk's Settings gear calls
/authenticate with the admin password; on success it gets a signed JWT it stores
in localStorage and presents to /verify each time Settings is opened. No password
ever lives in the kiosk bundle or localStorage — only the short-lived token.

Endpoints (reached by the kiosk via the nginx /auth/ proxy):
  POST /authenticate  {password}            -> {token, expiresInHours}  | 401
  POST /verify        Authorization: Bearer -> {ok:true}                | 401
  GET  /health                              -> {ok, configured}

Config (env, set at deploy):
  KIOSK_ADMIN_PASSWORD   the admin password (required to enable auth)
  JWT_SECRET             HMAC secret (optional; a random one is generated if unset,
                         which invalidates tokens on restart — fine, just re-login)
  TOKEN_TTL_HOURS        token lifetime (default 12)
"""
import hmac
import os
import secrets
import time

import jwt
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

ADMIN_PASSWORD = os.environ.get("KIOSK_ADMIN_PASSWORD", "")
JWT_SECRET = os.environ.get("JWT_SECRET") or secrets.token_urlsafe(48)
TTL_HOURS = float(os.environ.get("TOKEN_TTL_HOURS", "12"))
ALGO = "HS256"

app = FastAPI(title="kiosk-auth")


class AuthReq(BaseModel):
    password: str


@app.get("/health")
def health():
    # `configured` tells the kiosk whether a password is set (auth is enforceable).
    return {"ok": True, "configured": bool(ADMIN_PASSWORD)}


@app.post("/authenticate")
def authenticate(body: AuthReq):
    if not ADMIN_PASSWORD:
        # No password configured → auth can't be enforced. Fail safe (closed).
        raise HTTPException(503, "auth not configured")
    # Constant-time compare; small delay to blunt brute force.
    if not hmac.compare_digest(body.password or "", ADMIN_PASSWORD):
        time.sleep(0.5)
        raise HTTPException(401, "invalid password")
    now = int(time.time())
    token = jwt.encode(
        {"sub": "kiosk-admin", "iat": now, "exp": now + int(TTL_HOURS * 3600)},
        JWT_SECRET, algorithm=ALGO,
    )
    return {"token": token, "expiresInHours": TTL_HOURS}


@app.post("/verify")
def verify(authorization: str | None = Header(default=None)):
    token = ""
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    if not token:
        raise HTTPException(401, "missing token")
    try:
        jwt.decode(token, JWT_SECRET, algorithms=[ALGO])
    except Exception:
        raise HTTPException(401, "invalid or expired token")
    return {"ok": True}
