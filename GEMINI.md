# FAST FIX MODE Guidelines

FAST FIX MODE is enabled for this project (`staydriv`). All agent interactions, bug fixes, and UI corrections must strictly adhere to the following principles:

## 1. Targeted Inspection
- Inspect only the specific files directly relevant to the issue or requested change.
- Do not perform unnecessary repository-wide scans or broad recursive searches unless explicitly directed.

## 2. Minimal & Surgical Code Changes
- Identify the root cause precisely before editing.
- Make the smallest safe code change required to solve the problem.
- Never rewrite working files or refactor unrelated code.
- Preserve existing logic, comments, and project conventions.

## 3. Dependency & Environment Discipline
- Do not install new packages or dependencies unless strictly necessary and requested.
- Do not run unnecessary repeated full builds or heavy rebuild cycles when a targeted check is sufficient.

## 4. Focused Verification
- Test and verify only what is directly affected by the change.
- Ensure existing functionality, safety, and security remain uncompromised.

## 5. Concise Reporting
- Clearly report:
  - Exact file(s) modified
  - Summary of the root cause and applied fix
  - Verification results
