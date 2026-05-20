/**
 * LLM Observability — Node.js instrumentation example.
 *
 * Requires: dd-trace >= 5.20.0, openai >= 4.0.0
 * Install:  npm install dd-trace openai
 *
 * ESM note: this file uses static imports and top-level await, which requires
 * ESM module mode. Add `"type": "module"` to package.json (or rename to .mjs).
 *
 * ESM import ordering: ESM hoists all static imports before module body runs,
 * so `dd-trace` cannot patch OpenAI via a static import. For auto-instrumentation
 * (where dd-trace patches the openai module), use a CJS require() or a separate
 * bootstrap entrypoint. The LLMObs manual span API (llmobs.trace) used here does
 * NOT rely on auto-instrumentation — it works correctly with static ESM imports.
 *
 * Environment variables (set before running):
 *   DD_LLMOBS_ML_APP=orders-assistant
 *   DD_LLMOBS_AGENTLESS_ENABLED=true
 *   DD_API_KEY=<your-api-key>
 *   DD_SITE=datadoghq.eu
 *   DD_ENV=production
 *   DD_SERVICE=orders-assistant
 *   DD_VERSION=1.0.0
 */

import tracer from "dd-trace";
tracer.init({
  service: process.env.DD_SERVICE ?? "orders-assistant",
  env: process.env.DD_ENV ?? "production",
  version: process.env.DD_VERSION,
  llmobs: {
    mlApp: process.env.DD_LLMOBS_ML_APP ?? "orders-assistant",
    agentlessEnabled: process.env.DD_LLMOBS_AGENTLESS_ENABLED !== "false",
  },
});

import OpenAI from "openai";
const llmobs = tracer.llmobs;
const openaiClient = new OpenAI();

/**
 * Calls OpenAI and traces the span as an LLM span.
 */
async function generateOrderSummary(orderId, context) {
  const contextText = context.map((d) => d.text).join("\n");
  const prompt = `Using only the context below, summarise order ${orderId} in one sentence.\n\nContext:\n${contextText}`;

  return llmobs.trace(
    { kind: "llm", name: "generate_order_summary", modelProvider: "openai", modelName: "gpt-4o" },
    async (span) => {
      const response = await openaiClient.chat.completions.create({
        model: "gpt-4o",
        messages: [{ role: "user", content: prompt }],
      });

      const answer = response.choices[0].message.content;

      llmobs.annotate(span, {
        inputData: [{ role: "user", content: prompt }],
        outputData: [{ role: "assistant", content: answer }],
        metrics: {
          inputTokens: response.usage.prompt_tokens,
          outputTokens: response.usage.completion_tokens,
          totalTokens: response.usage.total_tokens,
        },
      });

      return answer;
    }
  );
}

/**
 * End-to-end workflow: simulated retrieval → LLM.
 */
async function orderSummaryWorkflow(orderId) {
  return llmobs.trace({ kind: "workflow", name: "order_summary_workflow" }, async () => {
    const context = [
      { id: "doc-1", text: `Order ${orderId}: 3x Widget, shipped 2026-05-19` },
      { id: "doc-2", text: "Standard shipping: 3-5 business days" },
    ];

    const summary = await generateOrderSummary(orderId, context);
    return { orderId, summary };
  });
}

// Top-level await requires ESM ("type": "module" in package.json or .mjs extension)
const result = await orderSummaryWorkflow("ORD-12345");
console.log(result.summary);
