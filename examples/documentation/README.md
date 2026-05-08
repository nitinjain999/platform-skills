Status: Stable

# Documentation Examples

Reference implementations for docstrings, OpenAPI specs, and documentation sites.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [python-docstrings/](python-docstrings/) | Python | Google-style docstrings with coverage check |
| [openapi-spec/](openapi-spec/) | OpenAPI 3.1 | Orders API spec with shared components |
| [mkdocs-site/](mkdocs-site/) | MkDocs | Material theme site with auto-generated API reference |

## Usage

```bash
# Validate OpenAPI spec
npx @redocly/cli lint openapi-spec/openapi.yaml

# Check Python docstring coverage
cd python-docstrings
pip install interrogate
interrogate --fail-under=80 src/

# Preview MkDocs site
cd mkdocs-site
pip install mkdocs-material mkdocstrings[python]
mkdocs serve
```

## See Also

- [references/documentation.md](../../references/documentation.md) — docstring styles, OpenAPI 3.1, doc sites, guides
- `/platform-skills:document` — generate docstrings, OpenAPI spec, doc site, or getting started guide
