# Token Optimizer Benchmark Fixtures

Status: Draft

Twelve fixtures across seven families, four arms, three runs per arm. No results are published — run `/platform-skills:token-optimizer benchmark` to produce your own.

## Workspace isolation is mandatory

For each run the harness builds a scratch directory containing **only**:

```
<scratch>/task.md
<scratch>/evidence/**
```

`criteria.json`, `capability.txt`, `manifest.json`, and every other fixture stay outside it, and the agent is confined to the scratch directory.

Passing only `task.md` as the prompt is **not** isolation. An agent that can read the repository can read `criteria.json` next to it, and a fixture suite that leaks its own answer key measures nothing.

## Cache state

Every record declares `cold`, `warm`, or `unknown`, established by the harness rather than inferred. Cold compares only against cold, warm only against warm, and `unknown` runs are excluded from cache-sensitive comparisons. A cold baseline against a warm optimized arm is an artifact of run order, not a measurement.

## Controls decide whether the feature is worth having

`control-small-file` must **not** delegate. `control-subtle-iam` must read primary evidence rather than trusting a summary — and its summary is deliberately accurate about a statement the diff never touches, which is the realistic failure: a plausible summary about the wrong thing.

## Fixture evidence must never contain provider binaries or other build output

The manifest's isolation rule copies `evidence/**` per run, so `.terraform/`, `node_modules/`, or any other large build artifact would be copied multiple times per arm, wasting disk and time.
