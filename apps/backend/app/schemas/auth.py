"""Request/response DTOs for /v1/auth -- FEAT-001.

Kept separate from app/models/user.py (the ORM model) so wire contracts can
evolve independently of storage per architecture.md's API Contract Stability
note.
"""

from pydantic import BaseModel, EmailStr, Field, model_validator


class RegisterEmailRequest(BaseModel):
    """Email + password registration -- Screen 1 'Sign Up' tab, phone toggle off."""

    full_name: str = Field(min_length=1, max_length=200)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class RegisterPhoneRequest(BaseModel):
    """Step 1 of phone registration: request an OTP be sent. No password yet --
    the account is created once the OTP is verified (see VerifyOtpRequest)."""

    full_name: str = Field(min_length=1, max_length=200)
    phone_number: str = Field(min_length=8, max_length=20)


class VerifyOtpRequest(BaseModel):
    """Step 2 of phone registration: verify the code sent to phone_number and
    finalize account creation."""

    phone_number: str = Field(min_length=8, max_length=20)
    otp_code: str = Field(min_length=4, max_length=8)


class LoginRequest(BaseModel):
    """Screen 1 'Log In' tab. Exactly one of email/phone_number must be set,
    matched against the identifier used at registration."""

    email: EmailStr | None = None
    phone_number: str | None = None
    password: str | None = Field(default=None, description="Required for email login")
    otp_code: str | None = Field(default=None, description="Required for phone login")

    @model_validator(mode="after")
    def _one_identifier(self) -> "LoginRequest":
        if bool(self.email) == bool(self.phone_number):
            raise ValueError("Provide exactly one of email or phone_number")
        if self.email and not self.password:
            raise ValueError("password is required for email login")
        if self.phone_number and not self.otp_code:
            raise ValueError("otp_code is required for phone login")
        return self


class RefreshRequest(BaseModel):
    refresh_token: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    reset_token: str
    new_password: str = Field(min_length=8, max_length=128)


class AuthTokenResponse(BaseModel):
    """Returned on successful register/login/refresh. Session persists across
    app restarts per FEAT-001 -- the mobile client stores access_token in
    session_store.dart's secure storage."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    role: str
    is_verified_host: bool
