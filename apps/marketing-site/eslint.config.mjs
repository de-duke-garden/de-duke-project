// Flat ESLint config -- required as of Next.js 16, which removed the
// `next lint` command (previously auto-generated this on first run) in
// favor of driving the standard ESLint CLI directly. `npm run lint` now
// calls `eslint .` against this config.
//
// eslint-config-next 16.x ships a native flat config array directly
// (dist/index.js) -- imported straight rather than via @eslint/eslintrc's
// FlatCompat, which was translating the *legacy* eslintrc-style preset and
// crashed under ESLint 10 ("Converting circular structure to JSON" inside
// eslint-plugin-react's flat-config shim). The native export sidesteps
// that translation layer entirely.
import nextConfig from "eslint-config-next";

const eslintConfig = [
  ...nextConfig,
  {
    ignores: [".next/**", "out/**", "node_modules/**"],
  },
];

export default eslintConfig;
