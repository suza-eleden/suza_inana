import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

const jsonParseSoloEnFrontera = {
  selector:
    'CallExpression[callee.object.name="JSON"][callee.property.name="parse"]',
  message:
    "JSON.parse solo vive en src/frontier/json.ts. Usá decodeJson + Zod.",
};

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    ignores: ["src/generated/**", "dist/**", "supabase/**", "node_modules/**"],
  },
  {
    files: ["src/**/*.ts", "tests/**/*.ts"],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unsafe-assignment": "error",
      "@typescript-eslint/no-unsafe-return": "error",
      "@typescript-eslint/no-unsafe-call": "error",
      "@typescript-eslint/no-unsafe-member-access": "error",
      "@typescript-eslint/no-unsafe-argument": "error",
      "@typescript-eslint/consistent-type-assertions": [
        "error",
        { assertionStyle: "never" },
      ],
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports" },
      ],
      "no-restricted-syntax": ["error", jsonParseSoloEnFrontera],
    },
  },
  {
    files: ["src/frontier/json.ts"],
    rules: {
      "@typescript-eslint/no-unsafe-return": "off",
      "@typescript-eslint/consistent-type-assertions": "off",
      "no-restricted-syntax": "off",
    },
  },
);
