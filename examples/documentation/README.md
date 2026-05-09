Status: Stable

# Documentation Examples

Reference implementations for OpenAPI 3.1 specifications with shared components, security schemes, and response definitions.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [openapi-spec/openapi.yaml](openapi-spec/) | OpenAPI 3.1 | Orders API — create, read, list orders with auth, pagination, error schemas |

## Quick Start

```bash
# Validate the spec with Redocly (recommended)
npx @redocly/cli lint openapi-spec/openapi.yaml

# Preview rendered documentation in browser
npx @redocly/cli preview-docs openapi-spec/openapi.yaml

# Generate HTML docs
npx @redocly/cli build-docs openapi-spec/openapi.yaml -o docs/

# Validate with Spectral (alternative linter)
npx @stoplight/spectral-cli lint openapi-spec/openapi.yaml
```

## What the Orders API Spec Covers

| Section | What it shows |
|---------|--------------|
| `info` | Version, contact, license metadata |
| `servers` | Environment URLs (production, staging) |
| `security` | Bearer token and API key schemes |
| `paths` | `POST /orders`, `GET /orders/{id}`, `GET /orders` with pagination |
| `components/schemas` | `Order`, `CreateOrderRequest`, `ErrorResponse`, `PaginatedResponse` — reused across paths |
| `components/responses` | Shared `400`, `401`, `404`, `500` responses referenced by `$ref` |
| `components/parameters` | Shared `page`, `limit`, `sort` pagination parameters |

## Key Patterns

### Shared error responses (avoid duplication)

```yaml
# Define once in components
components:
  responses:
    NotFound:
      description: Resource not found
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"

# Reference everywhere
paths:
  /orders/{id}:
    get:
      responses:
        "404":
          $ref: "#/components/responses/NotFound"
```

### Pagination schema

```yaml
components:
  schemas:
    PaginatedOrders:
      type: object
      required: [data, total, page, limit]
      properties:
        data:
          type: array
          items:
            $ref: "#/components/schemas/Order"
        total:
          type: integer
        page:
          type: integer
        limit:
          type: integer
```

### Security scheme

```yaml
components:
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```

## Validate in CI

```yaml
# .github/workflows/docs.yml
- name: Lint OpenAPI spec
  run: npx @redocly/cli lint openapi-spec/openapi.yaml --fail-on-warnings
```

## Checklist

- [ ] All paths have `operationId`, `summary`, and `tags`
- [ ] All schemas use `$ref` for reusable types — no inline duplication
- [ ] All error responses reference shared `components/responses`
- [ ] Security schemes declared in `components/securitySchemes` and referenced in `security`
- [ ] `required` fields listed explicitly on all request body schemas
- [ ] Examples provided for request and response bodies
- [ ] Spec passes `@redocly/cli lint` with zero errors

## See Also

- [references/documentation.md](../../references/documentation.md) — docstring styles (Google/NumPy/JSDoc), OpenAPI 3.1, doc sites (MkDocs/TypeDoc), developer guides
- `/platform-skills:document` — generate docstrings, OpenAPI spec, doc site, or getting started guide
