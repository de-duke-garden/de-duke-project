"use client";

import { useState } from "react";
import type { HostAccountDetail } from "./types";

interface DocSpec {
  field: keyof HostAccountDetail;
  label: string;
}

interface TextSpec {
  field: keyof HostAccountDetail;
  label: string;
}

/** Mirrors REQUIRED_DOCUMENT_FIELDS / REQUIRED_TEXT_FIELDS in
 * apps/backend/app/schemas/host_account.py exactly -- only fields relevant
 * to the submission's host_type are rendered. */
const DOC_SPECS: Record<string, DocSpec[]> = {
  owner: [],
  agent: [
    { field: "cac_cert_doc_url", label: "CAC Certificate" },
    { field: "industry_license_url", label: "Industry License (optional)" },
    { field: "proof_of_address_url", label: "Proof of Address" },
    { field: "rep_id_url", label: "Representative ID" },
  ],
  company: [
    { field: "cac_reg_doc_url", label: "CAC Registration Document" },
    { field: "proof_of_address_url", label: "Proof of Address" },
    { field: "rep_id_url", label: "Director/Representative ID" },
  ],
  lawyer: [
    { field: "valid_practicing_cert_url", label: "Valid Practicing Certificate" },
    { field: "govt_issued_id_url", label: "Government-Issued ID" },
    { field: "proof_of_address_url", label: "Proof of Address" },
  ],
  architect: [
    { field: "practice_license_url", label: "Practice License" },
    { field: "govt_issued_id_url", label: "Government-Issued ID" },
  ],
  surveyor: [
    { field: "practice_license_url", label: "Practice License" },
    { field: "govt_issued_id_url", label: "Government-Issued ID" },
  ],
};

const TEXT_SPECS: Record<string, TextSpec[]> = {
  owner: [],
  agent: [],
  company: [],
  lawyer: [
    { field: "nba_enrol_no", label: "NBA Enrollment Number" },
    { field: "ref_phone_no", label: "Reference Phone Number" },
  ],
  architect: [
    { field: "arcon_reg_no", label: "ARCON Registration Number" },
    { field: "ref_phone_no", label: "Reference Phone Number" },
  ],
  surveyor: [
    { field: "surcon_reg_no", label: "SURCON Registration Number" },
    { field: "ref_phone_no", label: "Reference Phone Number" },
  ],
};

export function SubmissionDetailPanel({ detail }: { detail: HostAccountDetail }) {
  const docSpecs = DOC_SPECS[detail.host_type] ?? [];
  const textSpecs = TEXT_SPECS[detail.host_type] ?? [];
  // branding.md Screen 27 Modernization Notes: the document image viewer's
  // zoom interaction uses a simple scale transition at `duration-fast`
  // (150ms, per branding.md's Reduced Motion & Performance section) rather
  // than an abrupt jump -- click to zoom in/out on a document image.
  const [zoomedField, setZoomedField] = useState<string | null>(null);

  return (
    <div className="space-y-md">
      <div>
        <h3 className="text-sm font-medium text-text-secondary">Profile photo</h3>
        {/* eslint-disable-next-line @next/next/no-img-element -- File Storage URLs, not a Next.js-optimizable local asset set */}
        <img
          src={detail.host_photo_url}
          alt="Profile"
          className="mt-xs h-32 w-32 rounded-md object-cover"
        />
      </div>

      <div>
        <h3 className="text-sm font-medium text-text-secondary">Bio</h3>
        <p className="mt-xs text-sm">{detail.bio}</p>
      </div>

      {textSpecs.map((spec) => (
        <div key={spec.field}>
          <h3 className="text-sm font-medium text-text-secondary">{spec.label}</h3>
          <p className="mt-xs text-sm">{(detail[spec.field] as string) ?? "--"}</p>
        </div>
      ))}

      {docSpecs.map((spec) => {
        const url = detail[spec.field] as string | null;
        return (
          <div key={spec.field}>
            <h3 className="text-sm font-medium text-text-secondary">{spec.label}</h3>
            {url ? (
              <div className="mt-xs overflow-hidden rounded-md border border-border">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={url}
                  alt={spec.label}
                  onClick={() =>
                    setZoomedField((prev) => (prev === spec.field ? null : (spec.field as string)))
                  }
                  className={`max-h-64 w-full origin-center cursor-zoom-in object-contain transition-transform duration-150 ease-out-smooth ${
                    zoomedField === spec.field ? "scale-150 cursor-zoom-out" : "scale-100"
                  }`}
                />
              </div>
            ) : (
              <p className="mt-xs text-sm text-text-secondary">Not provided</p>
            )}
          </div>
        );
      })}

      {detail.status === "rejected" && detail.status_reason && (
        <div className="rounded-md border border-error bg-error/10 p-sm">
          <h3 className="text-sm font-medium text-error">Prior rejection reason</h3>
          <p className="mt-xs text-sm">{detail.status_reason}</p>
        </div>
      )}
    </div>
  );
}
