"""Auth primitives: password hashing, JWT session tokens, and role-based
FastAPI dependencies.

Role/permission checks always happen here, server-side -- per AGENTS.md
Behavior Rules, never rely on hiding UI elements client-side.
"""

from datetime import UTC, datetime, timedelta
from enum import StrEnum

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import get_settings

settings = get_settings()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer()
_optional_bearer_scheme = HTTPBearer(auto_error=False)


class UserRole(StrEnum):
    """Mirrors User.role in schema.md. guest/host/agency
    are self-service roles; deduke_staff/deduke_admin are internal-only,
    never available via self-signup (see FEAT-033)."""

    GUEST = "guest"
    HOST = "host"
    AGENCY = "agency"
    DEDUKE_STAFF = "deduke_staff"
    DEDUKE_ADMIN = "deduke_admin"


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(*, user_id: str, role: UserRole) -> str:
    """Issues a signed session token. Stateless validation on every request --
    any backend Fargate task can validate any request without shared
    in-memory session state (architecture.md Cross-Cutting Concerns)."""
    expire = datetime.now(UTC) + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {"sub": user_id, "role": role.value, "exp": expire}
    return jwt.encode(payload, settings.jwt_signing_secret, algorithm=settings.jwt_algorithm)


class CurrentUser:
    """Decoded identity of the authenticated caller, attached to the request
    via the `get_current_user` dependency."""

    def __init__(self, user_id: str, role: UserRole) -> None:
        self.user_id = user_id
        self.role = role


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> CurrentUser:
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_signing_secret,
            algorithms=[settings.jwt_algorithm],
        )
        user_id: str | None = payload.get("sub")
        role_value: str | None = payload.get("role")
        if user_id is None or role_value is None:
            raise ValueError("Missing sub/role claim")
        return CurrentUser(user_id=user_id, role=UserRole(role_value))
    except (JWTError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session token",
        ) from exc


async def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials | None = Depends(_optional_bearer_scheme),
) -> CurrentUser | None:
    """Same decoding as get_current_user, but for public/unauthenticated-
    allowed endpoints (e.g. GET /v1/search/listings, per user_flow.md's
    Flow 0: a guest can search before signing up) that still want to
    attribute an analytics event to a user WHEN one happens to be signed
    in (FEAT-028 AC), without forcing auth on the endpoint itself. Returns
    None for a missing, malformed, or expired token -- never raises."""
    if credentials is None:
        return None
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_signing_secret,
            algorithms=[settings.jwt_algorithm],
        )
        user_id: str | None = payload.get("sub")
        role_value: str | None = payload.get("role")
        if user_id is None or role_value is None:
            return None
        return CurrentUser(user_id=user_id, role=UserRole(role_value))
    except (JWTError, ValueError):
        return None


def require_roles(*allowed_roles: UserRole):
    """FastAPI dependency factory enforcing role-based access server-side.

    Usage: `Depends(require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN))`
    A Staff-level request to an Admin-only endpoint (FEAT-033) must resolve
    to a 403, not a hidden UI element -- this is that enforcement point.
    """

    async def _dependency(current_user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have permission to do this.",
            )
        return current_user

    return _dependency
