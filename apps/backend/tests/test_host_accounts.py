"""Tests for FEAT-002 (Become a Host -- Type-Specific Verification) acceptance
criteria, covering the Owner (lightest) and Lawyer (heaviest document set)
host types, plus the staff review flow.
"""

import io
import json

from fastapi.testclient import TestClient

from app.core.security import UserRole, create_access_token


def _register_and_login(client: TestClient, email: str) -> tuple[str, str]:
    response = client.post(
        "/v1/auth/register",
        json={"full_name": "Test User", "email": email, "password": "supersecret1"},
    )
    body = response.json()
    return body["access_token"], body["user_id"]


def _staff_token() -> str:
    return create_access_token(user_id="staff-1", role=UserRole.DEDUKE_STAFF)


def test_owner_submission_requires_only_photo_and_bio(client: TestClient) -> None:
    """AC: Owner type requires no documents beyond photo + bio."""
    token, _ = _register_and_login(client, "owner@example.com")
    submission = {
        "host_type": "owner",
        "bio": "I own two properties in Lekki.",
        "profile_photo_temp_key": "photo.jpg",
        "documents": [],
    }
    response = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[("files", ("photo.jpg", io.BytesIO(b"fake-image-bytes"), "image/jpeg"))],
    )
    assert response.status_code == 201
    assert response.json()["status"] == "in_review"


def test_agent_submission_missing_required_document_is_validation_error(client: TestClient) -> None:
    """AC: user sees a specific missing-field/document error."""
    token, _ = _register_and_login(client, "agent@example.com")
    submission = {
        "host_type": "agent",
        "bio": "Licensed agent.",
        "profile_photo_temp_key": "photo.jpg",
        "documents": [{"field": "cac_cert_doc_url", "temp_key": "cac.jpg"}],
        # Missing proof_of_address_url and rep_id_url documents.
    }
    response = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[
            ("files", ("photo.jpg", io.BytesIO(b"img"), "image/jpeg")),
            ("files", ("cac.jpg", io.BytesIO(b"img"), "image/jpeg")),
        ],
    )
    assert response.status_code == 422


def test_lawyer_submission_with_all_documents_and_fields(client: TestClient) -> None:
    """AC: professional registration numbers entered as text; certs/IDs uploaded as images."""
    token, _ = _register_and_login(client, "lawyer@example.com")
    submission = {
        "host_type": "lawyer",
        "bio": "Practicing lawyer, 10 years call.",
        "profile_photo_temp_key": "photo.jpg",
        "nba_enrol_no": "NBA/12345",
        "ref_phone_no": "+2348099999999",
        "documents": [
            {"field": "valid_practicing_cert_url", "temp_key": "cert.jpg"},
            {"field": "govt_issued_id_url", "temp_key": "id.jpg"},
            {"field": "proof_of_address_url", "temp_key": "addr.jpg"},
        ],
    }
    response = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[
            ("files", ("photo.jpg", io.BytesIO(b"img"), "image/jpeg")),
            ("files", ("cert.jpg", io.BytesIO(b"img"), "image/jpeg")),
            ("files", ("id.jpg", io.BytesIO(b"img"), "image/jpeg")),
            ("files", ("addr.jpg", io.BytesIO(b"img"), "image/jpeg")),
        ],
    )
    assert response.status_code == 201


def test_admin_detail_view_includes_type_specific_fields(client: TestClient) -> None:
    """Screen 27 detail panel AC: every type-specific document/field for
    the submission's host_type is present in the detail response."""
    token, _ = _register_and_login(client, "lawyer-detail@example.com")
    submission = {
        "host_type": "lawyer",
        "bio": "Practicing lawyer, 10 years call.",
        "profile_photo_temp_key": "photo.jpg",
        "nba_enrol_no": "NBA/12345",
        "ref_phone_no": "+2348099999999",
        "documents": [
            {"field": "valid_practicing_cert_url", "temp_key": "cert.jpg"},
            {"field": "govt_issued_id_url", "temp_key": "id.jpg"},
            {"field": "proof_of_address_url", "temp_key": "addr.jpg"},
        ],
    }
    submit_response = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[
            ("files", ("photo.jpg", io.BytesIO(b"img"), "image/jpeg")),
            ("files", ("cert.jpg", io.BytesIO(b"img"), "image/jpeg")),
            ("files", ("id.jpg", io.BytesIO(b"img"), "image/jpeg")),
            ("files", ("addr.jpg", io.BytesIO(b"img"), "image/jpeg")),
        ],
    )
    host_account_id = submit_response.json()["id"]

    staff_token = _staff_token()
    detail_response = client.get(
        f"/v1/host-accounts/admin/{host_account_id}",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert detail_response.status_code == 200
    body = detail_response.json()
    assert body["host_type"] == "lawyer"
    assert body["nba_enrol_no"] == "NBA/12345"
    assert body["ref_phone_no"] == "+2348099999999"
    assert body["valid_practicing_cert_url"] is not None
    assert body["govt_issued_id_url"] is not None
    assert body["proof_of_address_url"] is not None
    # Fields belonging to other host types must not leak in.
    assert body["cac_cert_doc_url"] is None
    assert body["arcon_reg_no"] is None


def test_cannot_submit_second_host_type_while_in_review(client: TestClient) -> None:
    """AC: cannot submit a new host type while one is In Review or Verified."""
    token, _ = _register_and_login(client, "double@example.com")
    submission = {
        "host_type": "owner",
        "bio": "bio",
        "profile_photo_temp_key": "photo.jpg",
        "documents": [],
    }
    files = [("files", ("photo.jpg", io.BytesIO(b"img"), "image/jpeg"))]
    first = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=files,
    )
    assert first.status_code == 201

    second = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[("files", ("photo.jpg", io.BytesIO(b"img"), "image/jpeg"))],
    )
    assert second.status_code == 409


def test_staff_can_verify_and_reject_requires_reason(client: TestClient) -> None:
    """AC: staff can review a submission and change status (Verified/Rejected with reason)."""
    token, user_id = _register_and_login(client, "toverify@example.com")
    submission = {
        "host_type": "owner",
        "bio": "bio",
        "profile_photo_temp_key": "photo.jpg",
        "documents": [],
    }
    submit_response = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[("files", ("photo.jpg", io.BytesIO(b"img"), "image/jpeg"))],
    )
    host_account_id = submit_response.json()["id"]

    staff_token = _staff_token()

    # Reject without a reason is rejected client-side by schema validation (422).
    reject_no_reason = client.patch(
        f"/v1/host-accounts/admin/{host_account_id}/status",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"decision": "rejected"},
    )
    assert reject_no_reason.status_code == 422

    verify_response = client.patch(
        f"/v1/host-accounts/admin/{host_account_id}/status",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"decision": "verified"},
    )
    assert verify_response.status_code == 200
    assert verify_response.json()["status"] == "verified"


def test_non_staff_cannot_access_admin_queue(client: TestClient) -> None:
    """AC: only deduke_staff/deduke_admin can list-for-review/approve/reject."""
    token, _ = _register_and_login(client, "seeker@example.com")
    response = client.get("/v1/host-accounts/admin", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_admin_queue_lists_in_review_submissions(client: TestClient) -> None:
    """AC: staff can see a prioritized queue of listings awaiting review."""
    token, _ = _register_and_login(client, "queued@example.com")
    submission = {
        "host_type": "owner",
        "bio": "bio",
        "profile_photo_temp_key": "photo.jpg",
        "documents": [],
    }
    client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[("files", ("photo.jpg", io.BytesIO(b"img"), "image/jpeg"))],
    )
    staff_token = _staff_token()
    response = client.get(
        "/v1/host-accounts/admin?status_filter=in_review",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 200
    assert len(response.json()["items"]) == 1
