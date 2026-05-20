"""
LLM Observability — Python instrumentation example.

Requires: ddtrace >= 2.10.0
Install:  pip install ddtrace openai

Environment variables (set before running):
  DD_LLMOBS_ML_APP=orders-assistant
  DD_LLMOBS_AGENTLESS_ENABLED=true
  DD_API_KEY=<your-api-key>
  DD_SITE=datadoghq.eu
  DD_ENV=production
  DD_SERVICE=orders-assistant
  DD_VERSION=1.0.0
"""

import os
import openai
from ddtrace.llmobs import LLMObs
from ddtrace.llmobs.decorators import llm, workflow, retrieval

LLMObs.enable(
    ml_app=os.environ["DD_LLMOBS_ML_APP"],
    agentless_enabled=os.environ.get("DD_LLMOBS_AGENTLESS_ENABLED", "true").lower() == "true",
    api_key=os.environ["DD_API_KEY"],
    site=os.environ.get("DD_SITE", "datadoghq.eu"),
)

openai_client = openai.OpenAI()


@retrieval(name="fetch_order_context")
def fetch_order_context(order_id: str) -> list[dict]:
    """Simulates a vector DB retrieval step."""
    docs = [
        {"id": "doc-1", "score": 0.92, "text": f"Order {order_id}: 3x Widget, shipped 2026-05-19"},
        {"id": "doc-2", "score": 0.87, "text": "Standard shipping: 3-5 business days"},
    ]
    LLMObs.annotate(
        input_data=order_id,
        output_data=[{"id": d["id"], "score": d["score"], "text": d["text"]} for d in docs],
    )
    return docs


@llm(model_provider="openai", model_name="gpt-4o", name="generate_order_summary")
def generate_order_summary(order_id: str, context: list[dict]) -> str:
    """Calls OpenAI and traces the LLM span."""
    context_text = "\n".join(d["text"] for d in context)
    prompt = f"Using only the context below, summarise order {order_id} in one sentence.\n\nContext:\n{context_text}"

    response = openai_client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}],
    )
    answer = response.choices[0].message.content

    LLMObs.annotate(
        input_data=[{"role": "user", "content": prompt}],
        output_data=[{"role": "assistant", "content": answer}],
        metrics={
            "input_tokens": response.usage.prompt_tokens,
            "output_tokens": response.usage.completion_tokens,
            "total_tokens": response.usage.total_tokens,
        },
    )

    span_ctx = LLMObs.export_span()
    LLMObs.submit_evaluation(
        span=span_ctx,
        label="faithfulness",
        metric_type="score",
        value=1.0,  # Replace with a real evaluator function in production
    )

    return answer


@workflow(name="order_summary_workflow")
def order_summary_workflow(order_id: str) -> dict:
    """End-to-end workflow: retrieval → LLM → return."""
    context = fetch_order_context(order_id)
    summary = generate_order_summary(order_id, context)
    return {"order_id": order_id, "summary": summary}


if __name__ == "__main__":
    result = order_summary_workflow("ORD-12345")
    print(result["summary"])
