"use client";

import type { ReactNode } from "react";

interface ModalProps {
  children: ReactNode;
  onClose?: () => void;
  labelledBy?: string;
  size?: "sm" | "md" | "lg";
  className?: string;
}

const SIZE_CLASSES: Record<NonNullable<ModalProps["size"]>, string> = {
  sm: "max-w-sm",
  md: "max-w-md",
  lg: "max-w-lg",
};

/**
 * Shared confirmation/edit/reason modal shell used across every Admin Web
 * Console screen (Ban reason, Refund amount, Invite Staff, Edit Commission
 * Rate, ...). Implements branding.md's `modal-enter` token: the panel
 * scales up from 96% + fades in over 220ms (`ease-out-smooth`), while the
 * backdrop fades in slightly faster (150ms) so the backdrop feels
 * immediate and the panel feels considered.
 *
 * `size` controls max-width only -- content composition and any internal
 * scrolling stays caller-owned (some panels, e.g. Submission Detail, need
 * `max-h-[90vh] overflow-y-auto` on their own inner wrapper).
 */
export function Modal({ children, onClose, labelledBy, size = "md", className = "" }: ModalProps) {
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={labelledBy}
      className="animate-backdrop-enter fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose?.();
      }}
    >
      <div
        className={`animate-modal-enter w-full ${SIZE_CLASSES[size]} rounded-lg bg-surface p-lg shadow-xl dark:bg-surface-secondary-dark ${className}`}
      >
        {children}
      </div>
    </div>
  );
}
