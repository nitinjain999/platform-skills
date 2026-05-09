export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // Restrict scopes to known modules — add your own service/module names
    "scope-enum": [
      2,
      "always",
      [
        "api",
        "auth",
        "billing",
        "ci",
        "config",
        "db",
        "deps",
        "docs",
        "helm",
        "infra",
        "orders",
        "terraform",
        "ui",
      ],
    ],
    "subject-max-length": [2, "always", 72],
    "body-max-line-length": [2, "always", 72],
    "subject-case": [2, "always", "lower-case"],
    "subject-full-stop": [2, "never", "."],
    "type-enum": [
      2,
      "always",
      ["build", "chore", "ci", "docs", "feat", "fix", "perf", "refactor", "revert", "style", "test"],
    ],
  },
};
