// @ts-check

// Every file in ../commands must appear here. tests/website-coverage.sh fails the
// build if one is missing: the last three releases each shipped a command that
// never reached the site (kingfisher in 1.39.0, ai-governance in 1.40.0,
// token-optimizer in 1.41.0), because these sidebars are hand-enumerated and
// nothing compared them against the directory.

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  // ── Commands sidebar ───────────────────────────────────────────────
  commandsSidebar: [
    {
      // Featured first: these two govern what an AI agent may do and what it
      // costs to let it work. They are the newest capabilities and the reason
      // most people arrive at this handbook.
      type: 'category',
      label: 'AI Agent Governance & Cost',
      items: [
        { type: 'doc', id: 'ai-governance' },
        { type: 'doc', id: 'token-optimizer' },
      ],
    },
    {
      type: 'category',
      label: 'Kubernetes',
      items: [
        { type: 'doc', id: 'kubernetes' },
        { type: 'doc', id: 'openshift' },
        { type: 'doc', id: 'helmchart' },
        { type: 'doc', id: 'keda' },
        { type: 'doc', id: 'karpenter' },
      ],
    },
    {
      type: 'category',
      label: 'GitOps',
      items: [
        { type: 'doc', id: 'fluxcd' },
        { type: 'doc', id: 'gitops' },
      ],
    },
    {
      type: 'category',
      label: 'Terraform',
      items: [
        { type: 'doc', id: 'terraform' },
      ],
    },
    {
      type: 'category',
      label: 'AWS & Azure',
      items: [
        { type: 'doc', id: 'aws' },
        { type: 'doc', id: 'aws-profile' },
        { type: 'doc', id: 'azure' },
      ],
    },
    {
      type: 'category',
      label: 'GitHub Actions & CI',
      items: [
        { type: 'doc', id: 'github-actions' },
        { type: 'doc', id: 'composite-actions' },
        { type: 'doc', id: 'commit' },
        { type: 'doc', id: 'renovate' },
      ],
    },
    {
      type: 'category',
      label: 'Security',
      items: [
        { type: 'doc', id: 'secrets' },
        { type: 'doc', id: 'kingfisher' },
        { type: 'doc', id: 'kyverno' },
        { type: 'doc', id: 'opa' },
        { type: 'doc', id: 'supply-chain' },
        { type: 'doc', id: 'runtime-security' },
        { type: 'doc', id: 'trivy' },
        { type: 'doc', id: 'checkov' },
        { type: 'doc', id: 'zizmor' },
        { type: 'doc', id: 'linkerd' },
      ],
    },
    {
      type: 'category',
      label: 'Observability',
      items: [
        { type: 'doc', id: 'observability' },
        { type: 'doc', id: 'datadog' },
        { type: 'doc', id: 'dynatrace' },
      ],
    },
    {
      type: 'category',
      label: 'Linux & Networking',
      items: [
        { type: 'doc', id: 'linux' },
      ],
    },
    {
      type: 'category',
      label: 'Platform Engineering',
      items: [
        { type: 'doc', id: 'debug' },
        { type: 'doc', id: 'preflight' },
        { type: 'doc', id: 'product' },
        { type: 'doc', id: 'dora' },
        { type: 'doc', id: 'chaos' },
        { type: 'doc', id: 'compliance' },
        { type: 'doc', id: 'pr-review' },
        { type: 'doc', id: 'document' },
        { type: 'doc', id: 'awesome-docs' },
        { type: 'doc', id: 'mcp' },
        { type: 'doc', id: 'triage' },
        { type: 'doc', id: 'self-improve' },
      ],
    },
    {
      type: 'category',
      label: 'Agent Setup',
      items: [
        { type: 'doc', id: 'setup-agents' },
      ],
    },
  ],
};

module.exports = sidebars;
