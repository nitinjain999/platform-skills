"""
Eval Bootstrap — generate evaluators from production LLMObs traces.

This script demonstrates the pattern that the dd-llmo-eval-bootstrap skill
automates. Run it manually to understand what the skill produces, or as a
starting point when building custom evaluators.

Requires: ddtrace >= 2.10.0, openai (Python SDK) >= 1.0.0
Install:  pip install ddtrace openai

Environment variables:
  DD_API_KEY=<your-api-key>
  DD_APP_KEY=<your-app-key>
  DD_SITE=datadoghq.eu
  DD_LLMOBS_ML_APP=orders-assistant
"""

import os
import json
import openai

DD_API_KEY = os.environ["DD_API_KEY"]
DD_SITE = os.environ.get("DD_SITE", "datadoghq.eu")
ML_APP = os.environ.get("DD_LLMOBS_ML_APP", "orders-assistant")

# The dd-llmo-eval-bootstrap skill fetches traces via:
# pup logs search --query "ml_app:<ML_APP> @ml_obs.span_type:llm" --from now-24h
# The evaluators below mirror what the skill generates from those traces.

openai_client = openai.OpenAI()

FAITHFULNESS_PROMPT = """\
You are evaluating the faithfulness of an AI assistant response.

CONTEXT provided to the assistant:
{context}

ASSISTANT RESPONSE:
{response}

Does the assistant response contain ONLY information that can be verified from the context above?
Answer with a JSON object: {{"score": <float 0.0-1.0>, "reason": "<one sentence>"}}.
Score 1.0 = fully faithful (every claim supported by context).
Score 0.0 = hallucinated (claims not supported by context).
"""


def evaluate_faithfulness(response: str, context: str) -> dict:
    """Returns {score: float, reason: str}."""
    prompt = FAITHFULNESS_PROMPT.format(context=context, response=response)
    result = openai_client.chat.completions.create(
        model="gpt-4o-mini",  # cheap model for evaluation
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
    )
    return json.loads(result.choices[0].message.content)


QUALITY_PROMPT = """\
You are evaluating the quality of an AI assistant response.

QUESTION:
{question}

RESPONSE:
{response}

Rate the quality on these dimensions:
- Grammar and fluency (is it well-written?)
- Completeness (does it answer the question?)
- Clarity (is it easy to understand?)

Answer with a JSON object: {{"score": <float 0.0-1.0>, "reason": "<one sentence>"}}.
Score 1.0 = excellent on all dimensions. Score 0.0 = unintelligible or empty.
"""


def evaluate_quality(question: str, response: str) -> dict:
    """Returns {score: float, reason: str}."""
    prompt = QUALITY_PROMPT.format(question=question, response=response)
    result = openai_client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
    )
    return json.loads(result.choices[0].message.content)


# Run evaluators on a sample span (demo)
sample_span = {
    "question": "Summarise order ORD-12345 in one sentence.",
    "context": "Order ORD-12345: 3x Widget, shipped 2026-05-19. Standard shipping: 3-5 business days.",
    "response": "Order ORD-12345 contains three Widgets and was shipped on 2026-05-19 with standard delivery.",
}

faithfulness = evaluate_faithfulness(sample_span["response"], sample_span["context"])
quality = evaluate_quality(sample_span["question"], sample_span["response"])

print(f"Faithfulness: {faithfulness['score']:.2f} — {faithfulness['reason']}")
print(f"Quality:      {quality['score']:.2f} — {quality['reason']}")

# Attach scores to the originating LLMObs span in production:
# from ddtrace.llmobs import LLMObs
# span_ctx = LLMObs.export_span()
# LLMObs.submit_evaluation(span=span_ctx, label="faithfulness", metric_type="score", value=faithfulness["score"])
# LLMObs.submit_evaluation(span=span_ctx, label="quality",      metric_type="score", value=quality["score"])
