# Awesome Docs Examples
Status: Stable

Reusable animated SVG templates for the four `platform-skills:awesome-docs` diagram patterns.
Copy and adapt these files — substitute box labels, path coordinates, and field names for your specific technology.

## Templates

| File | Pattern | Use for |
|------|---------|---------|
| `arch-flow.svg` | Architecture flow | Any system with multiple components and data flow |
| `lifecycle-loop.svg` | Decision/lifecycle loop | Any repeating control loop with a threshold gate |
| `field-carousel.svg` | Field explainer carousel | Any resource with a YAML/config spec |
| `timeline-phases.svg` | Timeline phases | Any workload with distinct load phases |

## How to adapt

1. Open the SVG in a text editor
2. Replace `Box Label` text with your component names
3. Update `offset-path` coordinates to match your box positions
4. For `field-carousel.svg`: replace the YAML field names and tooltip text
5. Adjust timing values (`animation:` duration) if needed
6. Verify `N × slot = T` holds for field-carousel timing

## Validation

```bash
# Check SVG file sizes (must be under 50KB for GitHub inline rendering)
ls -lh examples/awesome-docs/*.svg

# Check SVGs have no external hrefs
grep -l "http" examples/awesome-docs/*.svg && echo "WARNING: external refs found" || echo "OK"
```
