---
name: document
description: Generate, format, and validate code documentation — docstrings, JSDoc, OpenAPI/Swagger specs, documentation sites, and developer guides.
argument-hint: "[docstrings|openapi|site|guide] [language/framework] [path or description]"
---

Generate or improve technical documentation for a codebase or API.

## Mode: docstrings

Add or improve inline documentation for functions, classes, and modules.

Steps:
1. Ask for: language, preferred style (Google / NumPy / Sphinx for Python; JSDoc for TypeScript/JavaScript)
2. Identify all public functions and classes missing documentation
3. For each, document: purpose, all parameters with types, return value, exceptions raised, and at least one example
4. Validate examples compile and run:
   - Python: `python -m doctest file.py` or `pytest --doctest-modules`
   - TypeScript: `tsc --noEmit`
5. Generate coverage report: `interrogate --fail-under=80 src/` (Python) or `npx typedoc-coverage` (TypeScript)

Rules:
- Do NOT document obvious getters/setters verbosely
- Do NOT repeat the function signature in prose
- Do NOT document private/internal methods unless they have complex invariants

Reference: `references/documentation.md` → Python Docstrings, TypeScript JSDoc

## Mode: openapi

Generate or improve an OpenAPI 3.1 specification for a REST API.

Steps:
1. Ask for: framework (FastAPI / Django / NestJS / Express / raw spec), existing routes or codebase to analyse
2. Map all endpoints: method, path, request body schema, response schemas per status code
3. Extract shared schemas into `components/schemas`
4. Extract shared responses (400, 401, 404, 500) into `components/responses`
5. Add `operationId` for every operation
6. Add security scheme and apply globally or per-operation
7. Validate: `npx @redocly/cli lint openapi.yaml`
8. Generate HTML preview: `npx @redocly/cli build-docs openapi.yaml`

For FastAPI: document with Pydantic model `Field(description=...)` and docstrings on route functions — auto-generates `/docs`.
For NestJS: use `@ApiProperty`, `@ApiOperation`, `@ApiResponse` decorators.

Reference: `references/documentation.md` → OpenAPI 3.1, FastAPI, NestJS

## Mode: site

Set up a documentation site for a project.

Steps:
1. Ask for: project type (Python library / TypeScript SDK / REST API / platform runbook)
2. Recommend appropriate generator:
   - Python projects → MkDocs + mkdocstrings + Material theme
   - TypeScript projects → TypeDoc + typedoc-material-theme
   - API portals → Redocly or Stoplight
   - General docs → Docusaurus
3. Generate site configuration file
4. Define nav structure: Getting Started, API Reference, Guides, Changelog
5. Wire docstring auto-generation from source code
6. Add search plugin
7. Provide `serve` and `build` commands

Reference: `references/documentation.md` → Documentation Sites

## Mode: guide

Write a getting started guide or tutorial.

Structure every guide as:
1. **Prerequisites** — exact versions, accounts, or permissions needed
2. **Installation** — copy-paste commands, not prose descriptions
3. **Quick start** — the simplest working example (< 10 lines)
4. **Next steps** — links to deeper topics

Rules:
- All code examples must be tested and runnable
- Use realistic values, not `<YOUR_VALUE>` placeholders where avoidable
- One concept per section — do not combine installation with configuration
- Include expected output for each command

Reference: `references/documentation.md` → Getting Started Guide Structure
