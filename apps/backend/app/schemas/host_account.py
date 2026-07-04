"""Request/response DTOs for /v1/host-accounts -- FEAT-002.

Document upload contract follows architecture.md's structured multi-file
rule: the submission JSON declares a `documents` array of {field, temp_key}
sub-records, matched against multipart file parts named by `temp_key` --
never ad hoc form-field-name encoding like `agent__cac_cert_doc`. This
avoids silently dropping a document if a field name is malformed.
"""

from enum import StrEnum

from pydantic import BaseModel, Field, model_validator

REQUIRED_DOCUMENT_FIELDS: dict[str, list[str]] = {
    "owner": [],
    "agent": [
        "cac_cert_doc_url",
        "proof_of_address_url",
        "rep_id_url",
    ],  # industry_license_url optional
    "company": ["cac_reg_doc_url", "proof_of_address_url", "rep_id_url"],
    "lawyer": ["valid_practicing_cert_url", "govt_issued_id_url", "proof_of_address_url"],
    "architect": ["practice_license_url", "govt_issued_id_url"],
    "surveyor": ["practice_license_url", "govt_issued_id_url"],
}

REQUIRED_TEXT_FIELDS: dict[str, list[str]] = {
    "owner": [],
    "agent": [],
    "company": [],
    "lawyer": ["nba_enrol_no", "ref_phone_no"],
    "architect": ["arcon_reg_no", "ref_phone_no"],
    "surveyor": ["surcon_reg_no", "ref_phone_no"],
}


class HostType(StrEnum):
    OWNER = "owner"
    AGENT = "agent"
    COMPANY = "company"
    LAWYER = "lawyer"
    ARCHITECT = "architect"
    SURVEYOR = "surveyor"


class DocumentRecord(BaseModel):
    """One declared document sub-record. `field` is the subtype table's
    column it fills (e.g. "cac_cert_doc_url"); `temp_key` is the multipart
    form field name carrying the actual file bytes for this submission."""

    field: str
    temp_key: str


class HostAccountSubmitRequest(BaseModel):
    """The `submission` JSON part of the multipart POST /host-accounts request.
    Actual files arrive as separate multipart file parts, each named by a
    `temp_key` referenced here -- explicit id-matching per architecture.md,
    never index-encoded field names."""

    host_type: HostType
    bio: str = Field(min_length=1, max_length=2000)
    profile_photo_temp_key: str = Field(
        description="multipart field name carrying the profile photo file"
    )
    documents: list[DocumentRecord] = Field(default_factory=list)

    # Type-specific text fields (only relevant ones populated per host_type).
    nba_enrol_no: str | None = None
    arcon_reg_no: str | None = None
    surcon_reg_no: str | None = None
    ref_phone_no: str | None = None

    @model_validator(mode="after")
    def _validate_required_for_type(self) -> "HostAccountSubmitRequest":
        required_docs = REQUIRED_DOCUMENT_FIELDS[self.host_type.value]
        provided_fields = {d.field for d in self.documents}
        missing_docs = [f for f in required_docs if f not in provided_fields]
        if missing_docs:
            joined = ", ".join(missing_docs)
            raise ValueError(f"Missing required document(s) for {self.host_type.value}: {joined}")

        required_text = REQUIRED_TEXT_FIELDS[self.host_type.value]
        for text_field in required_text:
            if not getattr(self, text_field, None):
                raise ValueError(f"Missing required field for {self.host_type.value}: {text_field}")
        return self


class HostAccountStatusResponse(BaseModel):
    id: str
    host_type: str
    status: str
    status_reason: str | None
    host_photo_url: str
    bio: str


class HostAccountReviewAction(BaseModel):
    """PATCH /admin/host-accounts/:id/status body -- Screen 27."""

    decision: str = Field(pattern="^(verified|rejected)$")
    reason: str | None = None

    @model_validator(mode="after")
    def _reason_required_on_reject(self) -> "HostAccountReviewAction":
        if self.decision == "rejected" and not self.reason:
            raise ValueError("A reason is required when rejecting a submission.")
        return self


class HostAccountQueueItem(BaseModel):
    id: str
    user_id: str
    host_type: str
    status: str
    created_at: str


class PaginatedHostAccountQueue(BaseModel):
    """Cursor-based (keyset) pagination per architecture.md -- never
    offset/page-number pagination for admin queues."""

    items: list[HostAccountQueueItem]
    next_cursor: str | None
