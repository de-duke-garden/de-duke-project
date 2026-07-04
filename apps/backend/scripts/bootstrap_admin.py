#!/usr/bin/env python
"""One-time CLI bootstrap for the FIRST De-Duke Admin account (FEAT-033).

This is the ONLY way to create a `deduke_admin` account with no inviter --
there is deliberately no HTTP endpoint anywhere in the API that can do
this (see app/api/v1/staff_accounts.py's module docstring). Run this once,
by hand, against the target environment's database, from an operator's
machine or a one-off deploy job -- never expose it over the network.

Usage (from apps/backend, with the venv active):

    python scripts/bootstrap_admin.py

Then follow the prompts for full name, email, and password.
"""

from __future__ import annotations

import asyncio
import getpass
import sys
from pathlib import Path

# Allow running as `python scripts/bootstrap_admin.py` without installing the
# package -- add the backend project root (parent of this scripts/ dir) to
# sys.path so `import app...` resolves.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.core.db import async_session_factory  # noqa: E402
from app.core.security import UserRole, hash_password  # noqa: E402
from app.models.user import User  # noqa: E402


def _prompt_non_empty(label: str) -> str:
    while True:
        value = input(f"{label}: ").strip()
        if value:
            return value
        print(f"{label} cannot be empty.")


def _prompt_password() -> str:
    while True:
        password = getpass.getpass("Password (min 12 chars): ")
        if len(password) < 12:
            print("Password must be at least 12 characters.")
            continue
        confirm = getpass.getpass("Confirm password: ")
        if password != confirm:
            print("Passwords do not match.")
            continue
        return password


async def bootstrap_admin(full_name: str, email: str, password: str) -> None:
    async with async_session_factory() as session:
        existing = await session.execute(select(User).where(User.email == email))
        if existing.scalars().first() is not None:
            raise SystemExit(f"Aborting: an account with email {email!r} already exists.")

        user = User(
            full_name=full_name,
            email=email,
            role=UserRole.DEDUKE_ADMIN.value,
            is_active=True,
            invited_by_id=None,  # CLI-bootstrapped -- never invited by anyone (schema.md)
            password_hash=hash_password(password),
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        print(f"Created deduke_admin account: id={user.id} email={user.email}")


def main() -> None:
    print("De-Duke Admin bootstrap -- creates the FIRST deduke_admin account.")
    print("This should only be run once per environment, from a trusted operator machine.\n")
    full_name = _prompt_non_empty("Full name")
    email = _prompt_non_empty("Email")
    password = _prompt_password()
    asyncio.run(bootstrap_admin(full_name, email, password))


if __name__ == "__main__":
    main()
