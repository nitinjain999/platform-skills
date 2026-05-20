# LLM Observability Reference

Covers Datadog LLM Observability (LLMObs): tracing LLM calls, evaluating outputs, running experiments, and root-causing failures in production AI applications.

---

## What is LLMObs?

Datadog LLMObs instruments your AI application at the span level — each LLM call, embedding, retrieval, tool call, and workflow step becomes a traced span. Unlike traditional APM, LLMObs captures:

- **Input/output content** — the prompt sent and the response received
- **Token counts** — input tokens, output tokens, total tokens per call
- **Model metadata** — provider, model name, temperature
- **Evaluation scores** — quality, faithfulness, relevance attached to spans
- **Custom tags** — `session_id`, `user_id`, `feature_flag` for filtering

### Decision: LLMObs vs traditional APM tracing

| Signal | Use LLMObs | Use traditional APM |
|--------|-----------|---------------------|
| LLM call latency and token cost | ✅ | — |
| Prompt/response content capture | ✅ | — |
| Evaluation scores (quality gates) | ✅ | — |
| HTTP handler latency | — | ✅ |
| Database query performance | — | ✅ |
| Full distributed trace with LLM spans | ✅ (combined) | ✅ (combined) |

LLMObs spans nest inside regular APM traces — one `dd-trace` init handles both.

---

## Instrumentation

### Python

```python
# requirements: ddtrace>=2.10.0
from ddtrace.llmobs import LLMObs
from ddtrace.llmobs.decorators import llm, workflow, task, tool, retrieval

LLMObs.enable(
    ml_app="orders-assistant",       # groups all spans in the LLMObs UI
    agentless_enabled=True,          # set False if running the Datadog Agent
    api_key=os.environ["DD_API_KEY"],
    site=os.environ.get("DD_SITE", "datadoghq.eu"),
)

# Trace an OpenAI call with the @llm decorator
@llm(model_provider="openai", model_name="gpt-4o", name="generate_order_summary")
def generate_order_summary(order: dict) -> str:
    response = openai_client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": f"Summarise this order: {order}"}],
    )
    # Annotate input/output so Datadog captures prompt and response
    LLMObs.annotate(
        input_data=[{"role": "user", "content": f"Summarise this order: {order}"}],
        output_data=[{"role": "assistant", "content": response.choices[0].message.content}],
    )
    return response.choices[0].message.content

# Trace a multi-step workflow
@workflow(name="order_processing_workflow")
def process_order(order_id: str) -> dict:
    order = fetch_order(order_id)          # retrieval step
    summary = generate_order_summary(order) # LLM step
    return {"order_id": order_id, "summary": summary}

# Trace a retrieval step (RAG)
@retrieval(name="fetch_product_docs")
def fetch_product_docs(query: str) -> list[dict]:
    results = vector_db.search(query, top_k=5)
    LLMObs.annotate(
        input_data=query,
        output_data=[{"id": r.id, "score": r.score, "text": r.text} for r in results],
    )
    return results
```

### Node.js

```javascript
// requires: dd-trace >= 5.20.0
import tracer from "dd-trace";

// DD_API_KEY, DD_SITE, DD_ENV, DD_SERVICE, DD_VERSION set via environment variables
tracer.init({
  service: "orders-assistant",
  env: process.env.DD_ENV ?? "production",
  version: process.env.DD_VERSION,
  llmobs: {
    mlApp: "orders-assistant",
    agentlessEnabled: true,  // set false if running the Datadog Agent
  },
});

const llmobs = tracer.llmobs;

// Trace an LLM call using tracer.llmobs.trace()
async function generateOrderSummary(order) {
  return llmobs.trace(
    { kind: "llm", name: "generate_order_summary", modelProvider: "openai", modelName: "gpt-4o" },
    async (span) => {
      const response = await openaiClient.chat.completions.create({
        model: "gpt-4o",
        messages: [{ role: "user", content: `Summarise this order: ${JSON.stringify(order)}` }],
      });

      llmobs.annotate(span, {
        inputData: [{ role: "user", content: `Summarise this order: ${JSON.stringify(order)}` }],
        outputData: [{ role: "assistant", content: response.choices[0].message.content }],
        metrics: {
          inputTokens: response.usage.prompt_tokens,
          outputTokens: response.usage.completion_tokens,
          totalTokens: response.usage.total_tokens,
        },
      });

      return response.choices[0].message.content;
    }
  );
}
```

### Environment variables

```bash
DD_LLMOBS_ML_APP=orders-assistant        # required: groups traces in LLMObs UI
DD_LLMOBS_AGENTLESS_ENABLED=true         # true if no Agent sidecar; false with Agent
DD_API_KEY=<your-api-key>
DD_SITE=datadoghq.eu
DD_ENV=production
DD_SERVICE=orders-assistant
DD_VERSION=1.2.3
```

---

## Eval Bootstrap

The `dd-llmo-eval-bootstrap` skill analyzes production LLM traces and generates evaluators — Python functions that score span outputs for quality, faithfulness, or relevance.

### Workflow

1. **Pull production traces** — the skill queries recent LLMObs spans for your `ml_app`
2. **Cluster by input shape** — groups spans with similar prompt structure
3. **Generate evaluator stubs** — produces scored Python functions with examples drawn from real production data
4. **Review and approve** — you inspect the generated evaluators before attaching them to your CI pipeline

### Attach evaluators to spans (Python)

```python
# After a generation span, score the output and submit
from ddtrace.llmobs import LLMObs

@llm(model_provider="openai", model_name="gpt-4o", name="answer_question")
def answer_question(question: str, context: str) -> str:
    answer = call_llm(question, context)

    # Faithfulness: does the answer only use information from context?
    faithfulness_score = evaluate_faithfulness(answer, context)  # your evaluator
    # Quality: is the answer grammatically correct and complete?
    quality_score = evaluate_quality(answer)

    span_ctx = LLMObs.export_span()
    LLMObs.submit_evaluation(
        span=span_ctx,
        label="faithfulness",
        metric_type="score",
        value=faithfulness_score,            # float 0.0–1.0
    )
    LLMObs.submit_evaluation(
        span=span_ctx,
        label="quality",
        metric_type="score",
        value=quality_score,
    )
    return answer
```

### CI quality gate

```bash
# Fail CI if average faithfulness drops below 0.8 over the last 100 traces
pup metrics query \
  --query "avg:ml_obs.evaluations.faithfulness{ml_app:orders-assistant,env:production}" \
  --from "now-24h" --to "now" \
  --format json | jq '.series[0].pointlist[-1][1] // 0 < 0.8' | grep -q true \
  && { echo "❌ Faithfulness below threshold"; exit 1; } \
  || echo "✅ Faithfulness OK"
```

---

## Trace RCA

The `dd-llmo-eval-trace-rca` skill root-causes LLM app failures by finding the span where quality degraded.

### Workflow

```
Invoke: /dd-llmo-eval-trace-rca

1. Provide the trace ID of a failing conversation (from LLMObs UI or pup logs search)
2. Skill fetches all spans in the trace
3. Skill identifies the first span where evaluation score drops below threshold
4. Skill surfaces the exact input/output at the failure point with a hypothesis
```

### Manual trace fetch with pup

```bash
# Find traces with low faithfulness scores in the last hour
pup logs search \
  --query "ml_app:orders-assistant @ml_obs.evaluations.faithfulness:<0.5" \
  --from "now-1h" --to "now" \
  --format json | jq '.[].trace_id' | sort -u

# Inspect all spans for a specific trace
pup apm traces get --trace-id <trace_id>
```

---

## Experiment Analysis

The `dd-llmo-experiment-analyzer` skill compares model versions, prompt variants, or retrieval configurations by analyzing evaluation scores across experiment cohorts.

### Tag spans with experiment metadata

```python
# Mark spans with experiment cohort for A/B analysis
LLMObs.annotate(
    tags={
        "experiment.name": "gpt4o-vs-gpt4o-mini",
        "experiment.variant": "gpt-4o-mini",   # or "gpt-4o"
        "experiment.cohort": "20pct-traffic",
    }
)
```

### Run analysis

```
Invoke: /dd-llmo-experiment-analyzer

1. Provide experiment name and date range
2. Skill queries evaluation scores grouped by experiment.variant
3. Skill computes mean, p10, p90 scores per cohort
4. Skill reports statistical significance and recommends winner
```

### Manual comparison with pup

```bash
# Compare average faithfulness between two model variants
for variant in "gpt-4o" "gpt-4o-mini"; do
  echo "=== $variant ==="
  pup metrics query \
    --query "avg:ml_obs.evaluations.faithfulness{ml_app:orders-assistant,experiment.variant:${variant}}" \
    --from "now-7d" --to "now" \
    --format json | jq '.series[0].pointlist[-1][1] // "no data"'
done
```

---

## Troubleshooting

| Symptom | Evidence | Fix |
|---------|----------|-----|
| Spans not appearing in LLMObs UI | Check `DD_LLMOBS_ML_APP` is set | Without `ml_app`, spans are discarded by LLMObs ingest |
| `agentless_enabled=True` but no data | Verify `DD_API_KEY` and `DD_SITE` are set | Agentless mode sends directly to Datadog intake — no Agent needed |
| Token counts missing | `annotate()` metrics block absent | Python: pass `input_tokens`, `output_tokens`, `total_tokens`; Node.js: `inputTokens`, `outputTokens`, `totalTokens` |
| Evaluations not linked to spans | Wrong `span` argument | Use `span=LLMObs.export_span()` inside the decorated function, not outside |
| `dd-llmo-eval-bootstrap` returns empty | No recent traces with `ml_app` tag | Ensure `DD_LLMOBS_ML_APP` was set when generating the traces |
| Experiment analysis shows no difference | Cohort tags not applied | Verify `experiment.variant` tag is set on LLM spans before calling `annotate()` |

---

## Security

- Never pass raw PII in prompt or completion content — use a `span_processor` callback in `LLMObs.enable()` to redact content before it leaves the process, or omit the `LLMObs.annotate()` call for high-sensitivity inputs
- Scope the API key used by agentless mode to `LLM Observability Write` only — it does not need Monitors Write or Logs Write
- Store the API key in a Kubernetes Secret or AWS Secrets Manager, referenced via `DD_API_KEY` from `secretKeyRef`

---
