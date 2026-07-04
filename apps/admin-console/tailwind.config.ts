// De-Duke design tokens (branding.md), transcribed for the Admin Console.
// Shared visual language with the mobile app, adapted for a web/desktop
// staff/admin surface (branding.md governs both, per its scope note).
import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        primary: { DEFAULT: "#0F6E5C", hover: "#0B5647", light: "#E1F2EE" },
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
        "primary-dark": "#2C9C82",
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
    },
  },
  darkMode: "media",
  plugins: [],
};

export default config;
