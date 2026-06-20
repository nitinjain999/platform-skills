// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  // ── References sidebar ────────────────────────────────────────────
  referencesSidebar: [
    {
      type: 'category',
      label: 'Kubernetes',
      items: [
        { type: 'doc', id: 'kubernetes' },
        { type: 'doc', id: 'helm' },
        { type: 'doc', id: 'keda' },
        { type: 'doc', id: 'karpenter' },
        { type: 'doc', id: 'openshift' },
      ],
    },
    {
      type: 'category',
      label: 'GitOps',
      items: [
        { type: 'doc', id: 'fluxcd' },
        { type: 'doc', id: 'fluxcd-helmrelease' },
        { type: 'doc', id: 'fluxcd-kustomization' },
        { type: 'doc', id: 'fluxcd-mcp' },
        { type: 'doc', id: 'fluxcd-migration' },
        { type: 'doc', id: 'fluxcd-notifications' },
        { type: 'doc', id: 'fluxcd-operator' },
        { type: 'doc', id: 'fluxcd-resourcesets' },
        { type: 'doc', id: 'fluxcd-security' },
        { type: 'doc', id: 'fluxcd-sources' },
        { type: 'doc', id: 'fluxcd-terraform' },
        { type: 'doc', id: 'fluxcd-troubleshooting' },
        { type: 'doc', id: 'argocd' },
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
        { type: 'doc', id: 'aws-cloudfront' },
        { type: 'doc', id: 'aws-mcp-profiles' },
        { type: 'doc', id: 'aws-waf' },
        { type: 'doc', id: 'azure' },
      ],
    },
    {
      type: 'category',
      label: 'GitHub Actions & CI',
      items: [
        { type: 'doc', id: 'github-actions' },
        { type: 'doc', id: 'composite-actions' },
        { type: 'doc', id: 'renovate' },
        { type: 'doc', id: 'conventional-commits' },
      ],
    },
    {
      type: 'category',
      label: 'Security',
      items: [
        { type: 'doc', id: 'kyverno' },
        { type: 'doc', id: 'opa' },
        { type: 'doc', id: 'supply-chain' },
        { type: 'doc', id: 'runtime-security' },
        { type: 'doc', id: 'trivy' },
        { type: 'doc', id: 'checkov' },
        { type: 'doc', id: 'linkerd' },
        { type: 'doc', id: 'secrets' },
      ],
    },
    {
      type: 'category',
      label: 'Observability',
      items: [
        { type: 'doc', id: 'observability' },
        { type: 'doc', id: 'datadog' },
        { type: 'doc', id: 'dynatrace' },
        { type: 'doc', id: 'llm-observability' },
      ],
    },
    {
      type: 'category',
      label: 'Linux & Networking',
      items: [
        { type: 'doc', id: 'linux-networking' },
      ],
    },
    {
      type: 'category',
      label: 'Platform Engineering',
      items: [
        { type: 'doc', id: 'platform-operating-model' },
        { type: 'doc', id: 'platform-mindset' },
        { type: 'doc', id: 'dora' },
        { type: 'doc', id: 'chaos' },
        { type: 'doc', id: 'compliance' },
        { type: 'doc', id: 'pr-review' },
        { type: 'doc', id: 'documentation' },
        { type: 'doc', id: 'awesome-docs' },
        { type: 'doc', id: 'mcp' },
      ],
    },
    {
      type: 'category',
      label: 'Agent Setup',
      items: [
        { type: 'doc', id: 'setup-agents' },
        { type: 'doc', id: 'setup-agents-add' },
        { type: 'doc', id: 'setup-agents-build' },
        { type: 'doc', id: 'setup-agents-generate' },
        { type: 'doc', id: 'setup-agents-prompts' },
        { type: 'doc', id: 'setup-agents-review' },
        { type: 'doc', id: 'setup-agents-schemas' },
        { type: 'doc', id: 'setup-agents-template' },
        { type: 'doc', id: 'agent-self-improve' },
      ],
    },
  ],
};

module.exports = sidebars;
