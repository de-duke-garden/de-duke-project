"use client";

import { useCallback, useEffect, useState } from "react";

import { ConfirmModal } from "./ConfirmModal";
import { InviteStaffModal } from "./InviteStaffModal";
import type { StaffAccount } from "./types";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000/v1";

// TODO(auth wiring): there is no shared "get the current admin session''s
// bearer token" helper yet (app/lib/auth.ts''s getAdminSession() is still a
// Foundation stub that always returns null -- see that file''s own
// docstring). Once the real session mechanism lands, replace this with
// whatever the Admin Web Console''s session layer exposes. Until then this
// reads a token a developer can set manually in devtools for local testing.
function getAuthToken(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem("deduke_admin_token");
}