// De-Duke design tokens (branding.md), transcribed for the Admin Console.
// Shared visual language with the mobile app, adapted for a web/desktop
// staff/admin surface (branding.md governs both, per its scope note).
import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        // Corrected per branding.md: the previously documented #0F6E5C read
        // as teal against the shipped logo asset; #0D6B2D is the true,
        // warmer forest green the logo actually renders. Deprecated teal
        // value removed everywhere it was transcribed for this app.
        primary: { DEFAULT: "#0D6B2D", hover: "#0A5423", light: "#E2F0E4" },
        accent: { DEFAULT: "#D98E04", light: "#FBEBCC" },
        surface: { DEFAULT: "#FFFFFF", secondary: "#F4F6F5" },
        "text-primary": "#12201C",
        "text-secondary": "#5F6E68",
        border: "#E1E6E3",
        success: "#1FA35B",
        warning: "#E2A230",
        error: "#D9463B",
        info: "#2E7BC4",
        "surface-dark": "#101613",
        "surface-secondary-dark": "#1A211D",
        "text-primary-dark": "#F2F5F3",
        "text-secondary-dark": "#9CAAA3",
        "border-dark": "#2B332E",
        "primary-dark": "#33A652",
        "primary-light-dark": "#153A20",
      },
      spacing: {
        xs: "4px",
        sm: "8px",
        md: "16px",
        lg: "24px",
        xl: "32px",
        "2xl": "48px",
        "3xl": "64px",
      },
      borderRadius: { sm: "4px", md: "8px", lg: "16px", full: "9999px" },
      fontFamily: {
        heading: ["Manrope", "sans-serif"],
        body: ["Inter", "sans-serif"],
        mono: ["JetBrains Mono", "monospace"],
      },
      // branding.md's two-layer elevation technique -- each token is two
      // stacked shadows (a tight contact shadow directly under the surface
      // plus a soft, wide ambient shadow) rather than one flat shadow.
      boxShadow: {
        xs: "0 1px 1px rgba(18,32,28,0.05), 0 1px 2px rgba(18,32,28,0.04)",
        sm: "0 1px 2px rgba(18,32,28,0.07), 0 4px 10px rgba(18,32,28,0.05)",
        md: "0 2px 4px rgba(18,32,28,0.08), 0 8px 20px rgba(18,32,28,0.08)",
        lg: "0 4px 8px rgba(18,32,28,0.1), 0 16px 36px rgba(18,32,28,0.14)",
        xl: "0 8px 16px rgba(18,32,28,0.12), 0 24px 48px rgba(18,32,28,0.16)",
      },
      // branding.md "Admin Web Console -- Interaction & Motion System":
      // deliberate/procedural easing only -- no spring/overshoot tokens on
      // this surface.
      transitionTimingFunction: {
        "out-smooth": "cubic-bezier(0.16, 1, 0.3, 1)",
        "in-out-smooth": "cubic-bezier(0.65, 0, 0.35, 1)",
      },
      keyframes: {
        "modal-enter": {
          from: { opacity: "0", transform: "scale(0.96)" },
          to: { opacity: "1", transform: "scale(1)" },
        },
        "backdrop-enter": {
          from: { opacity: "0" },
          to: { opacity: "1" },
        },
        "row-resolve": {
          "0%": { opacity: "1" },
          "60%": { opacity: "0" },
          "100%": {
            opacity: "0",
            marginTop: "0",
            marginBottom: "0",
            paddingTop: "0",
            paddingBottom: "0",
            height: "0",
          },
        },
        "badge-pop": {
          "0%": { transform: "scale(1)" },
          "30%": { transform: "scale(1.08)" },
          "100%": { transform: "scale(1)" },
        },
        "toast-enter": {
          from: { opacity: "0", transform: "translate(16px, -8px)" },
          to: { opacity: "1", transform: "translate(0, 0)" },
        },
        "stagger-in": {
          from: { opacity: "0", transform: "translateY(8px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
        "grow-in": {
          from: { transform: "scaleX(0)" },
          to: { transform: "scaleX(1)" },
        },
        shimmer: {
          "0%": { backgroundPosition: "-400px 0" },
          "100%": { backgroundPosition: "400px 0" },
        },
      },
      animation: {
        // Token durations/easings per branding.md's Admin Web Console
        // Interaction & Motion System table.
        "modal-enter": "modal-enter 220ms cubic-bezier(0.16,1,0.3,1) both",
        "backdrop-enter": "backdrop-enter 150ms cubic-bezier(0.16,1,0.3,1) both",
        "row-resolve": "row-resolve 260ms cubic-bezier(0.65,0,0.35,1) forwards",
        "badge-pop": "badge-pop 260ms cubic-bezier(0.16,1,0.3,1)",
        "toast-enter": "toast-enter 200ms cubic-bezier(0.16,1,0.3,1) both",
        "stagger-in": "stagger-in 200ms cubic-bezier(0.16,1,0.3,1) both",
        "grow-in": "grow-in 400ms cubic-bezier(0.16,1,0.3,1) both",
        shimmer: "shimmer 1400ms cubic-bezier(0.65,0,0.35,1) infinite",
      },
    },
  },
  darkMode: "media",
  plugins: [],
};

export default config;
