"""Request/response DTOs for /v1/auth -- FEAT-001.

Kept separate from app/models/user.py (the ORM model) so wire contracts can
evolve independently of storage per architecture.md's API Contract Stability
note.
"""

from pydantic import BaseModel, EmailStr, Field, model_validator


class FirebaseExchangeRequest(BaseModel):
    """Screen 1 (Sign-Up / Login) -- the single entry point for every
    consumer-role sign-in (Google Sign-In, Firebase email/password, or
    Firebase phone/OTP; the mobile client authenticates against Firebase
    directly and never sends De-Duke a raw password/OTP). `id_token` is the
    Firebase ID token Firebase's own SDK returns after any of those three
    methods succeeds client-side -- see auth_service.exchange_firebase_token
    for the server-side verification/User-resolution logic."""

    id_token: str = Field(min_length=1)


class LoginRequest(BaseModel):
    """Staff/Admin-only (FEAT-033) -- the Admin Web Console's login screen.
    Consumer roles never use this; they authenticate via
    FirebaseExchangeRequest above. Kept email+password-only (no phone/OTP
    branch) since Staff/Admin accounts, created via CLI bootstrap or
    invitation, have never had a phone-based sign-in path."""

    email: EmailStr
    password: str = Field(min_length=1)


class RefreshRequest(BaseModel):
    refresh_token: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    reset_token: str
    new_password: str = Field(min_length=8, max_length=128)


class AcceptInviteRequest(BaseModel):
    """FEAT-033 (Staff/Admin invite) and FEAT-012 (Agency team invite)
    share this one endpoint -- both invite flows produce the same
    `?token=...&uid=...` link shape, see auth_service.accept_invite."""

    user_id: str
    invite_token: str
    new_password: str = Field(min_length=8, max_length=128)


class CurrentUserResponse(BaseModel):
    """GET /v1/auth/me -- resolves the caller's identity from their access
    token. Used by server-side consumers (e.g. the Admin Web Console) that
    need to validate a session and read the current role without holding
    the JWT signing secret themselves."""

    user_id: str
    role: str
    full_name: str
    email: str | None
    phone_number: str | None
    is_verified_host: bool
    is_active: bool


class UserProfileResponse(BaseModel):
    """GET/PATCH /v1/user/profile -- FEAT-041 (Self-Service Profile
    Editing). Distinct from CurrentUserResponse (GET /v1/auth/me, which
    exists for server-side session validation) -- this is the mobile
    Account Settings/Admin Web Console "My Account" screen's own profile
    data source, and additionally surfaces `auth_provider` and whether a
    Firebase identity is linked, which those screens need to decide which
    fields are editable (FEAT-041) and what to show in the Linked
    Sign-In Methods section (FEAT-040)."""

    user_id: str
    full_name: str
    email: str | None
    phone_number: str | None
    auth_provider: str
    is_firebase_linked: bool
    # FEAT-041 -- a personal avatar, every account type, never gated by
    # auth_provider (unlike email) -- distinct from FEAT-042's
    # HostAccount.host_photo_url (the host-verification photo shown on a
    # host's listings). See auth_service.update_profile's docstring.
    profile_photo_url: str | None = None


# PATCH /v1/user/profile is multipart (not JSON) since `profile_photo_url`
# is a file upload -- see app/api/v1/user.py's endpoint, which takes
# full_name/email as plain Form fields and profile_photo as a File,
# validated inline there rather than via a Pydantic request body model
# (same pattern app/api/v1/host_accounts.py's PATCH /me uses).


class LinkFirebaseIdentityRequest(BaseModel):
    """FEAT-040 -- id_token is the Firebase ID token from a live client-side
    Firebase sign-in (same SDK flow as Screen 1), submitted here
    authenticated by the caller's EXISTING De-Duke bearer session, not by
    the Firebase token itself -- proof of control of both sides at once."""

    id_token: str = Field(min_length=1)


class ChangePasswordRequest(BaseModel):
    """FEAT-041 -- Admin Web Console "My Account" screen's logged-in
    password change. Distinct from ForgotPasswordRequest/
    ResetPasswordRequest above (that flow is for a user who is locked out
    and NOT currently authenticated)."""

    current_password: str = Field(min_length=1)
    new_password: str = Field(min_length=8, max_length=128)


class NotificationPreferencesResponse(BaseModel):
    """FEAT-024 AC: "User can manage email notification preferences per
    category in settings, separate from push preferences." One bool per
    category -- see app.models.user.DEFAULT_EMAIL_NOTIFICATION_PREFERENCES
    for the category list and defaults."""

    email_notification_preferences: dict[str, bool]


class UpdateNotificationPreferencesRequest(BaseModel):
    """Partial update -- omitted categories are left unchanged. All-optional
    rather than requiring the full set every time, so the client only
    sends the toggle(s) the user actually changed."""

    account: bool | None = None
    verification: bool | None = None
    payments: bool | None = None


# FEAT-003 (Role Selection) -- the three self-service values a user may set
# on themselves. Deliberately a closed set, NOT the full UserRole enum --
# self-service callers must never be able to set deduke_staff/deduke_admin
# on their own account (those are internal-only, see
# app.core.security.UserRole's docstring and FEAT-033).
SELF_SERVICE_ROLES = ("guest", "host", "agency")


class UpdateRoleRequest(BaseModel):
    """Screen 2 (Role Selection) and its "change role later in Account
    Settings" re-entry point (screens.md Screen 2 Edge Cases). `role` is
    validated against SELF_SERVICE_ROLES, not the full UserRole enum --
    see that constant's comment."""

    role: str

    @model_validator(mode="after")
    def _valid_self_service_role(self) -> "UpdateRoleRequest":
        if self.role not in SELF_SERVICE_ROLES:
            raise ValueError(f"role must be one of {SELF_SERVICE_ROLES}")
        return self


class AuthTokenResponse(BaseModel):
    """Returned on successful firebase-exchange/login/refresh/accept-invite.
    Session persists across app restarts per FEAT-001 -- the mobile client
    stores access_token in session_store.dart's secure storage."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    role: str
    is_verified_host: bool
    # True only for POST /firebase-exchange's first-ever sign-in for a given
    # Firebase identity (see auth_service.exchange_firebase_token's
    # docstring for why the client can't safely infer this from `role`
    # alone -- a returning user can still legitimately be role "guest").
    # Always False for login/refresh/accept-invite, which by construction
    # only ever resolve an existing account. FEAT-001 AC: routes a
    # first-time sign-in to Role Selection, a returning identity to Home
    # Feed/dashboard -- this field is what the mobile client branches on.
    is_new_user: bool = False
