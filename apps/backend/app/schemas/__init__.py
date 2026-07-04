"""Pydantic request/response schemas -- deliberately separate from app/models
(SQLModel ORM classes). See AGENTS.md ORM layer note: role-based field
visibility and the structured multi-file upload contract require shapes
that differ from the raw DB row, so schemas are never SQLModel-shared here.
"""
