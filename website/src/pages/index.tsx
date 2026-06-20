import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CodeBlock from '@theme/CodeBlock';

function Hero() {
  return (
    <div className="hero-section">
      <div className="hero-section__eyebrow">
        v1.34.0 &mdash;{' '}
        <a href="https://github.com/nitinjain999/platform-skills/blob/main/CHANGELOG.md">
          What&apos;s new
        </a>
      </div>
      <h1 className="hero-section__title">Platform Skills</h1>
      <p className="hero-section__subtitle">
        A production-grade field handbook for platform engineers — Kubernetes, GitOps, Terraform, AWS, and more.
        Blast radius, validation steps, and rollback plan built in.
      </p>
      <div className="hero-section__ctas">
        <Link className="button button--primary button--lg" to="/docs/kubernetes">
          Get Started
        </Link>
        <Link
          className="button button--secondary button--lg"
          to="https://github.com/nitinjain999/platform-skills"
        >
          View on GitHub
        </Link>
      </div>
      <div className="hero-section__badge">
        Works with Claude Code · Cursor · VS Code / Copilot · Codex
      </div>
    </div>
  );
}

function BeforeAfter() {
  const before = `spec:
  containers:
    - name: api-server
      image: mycompany/api-server:latest   # ❌ unpinned
      env:
        - name: DATABASE_URL
          value: "postgres://admin:password@db:5432/prod"  # ❌ hardcoded
      # ❌ no securityContext, no resources, no probes`;

  const after = `spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
    - name: api-server
      image: mycompany/api-server:v1.4.2   # ✅ pinned
      resources:
        requests: { cpu: 100m, memory: 128Mi }
        limits:   { cpu: 500m, memory: 512Mi }
      readinessProbe:
        httpGet: { path: /healthz/ready, port: 8080 }
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef: { name: api-server-secrets, key: database-url }  # ✅`;

  return (
    <section className="before-after">
      <div className="before-after__label">See it in action</div>
      <h2 className="before-after__heading">What platform-skills catches</h2>
      <div className="before-after__grid">
        <div className="before-after__header before-after__header--before">
          Before — what ships without it
        </div>
        <div className="before-after__header before-after__header--after">
          After — what platform-skills flags
        </div>
        <div className="before-after__body">
          <pre><code>{before}</code></pre>
        </div>
        <div className="before-after__body">
          <pre><code>{after}</code></pre>
        </div>
      </div>
    </section>
  );
}

const FEATURES = [
  {
    icon: '⎈',
    title: 'Kubernetes',
    desc: 'Cluster baseline, Helm, KEDA autoscaling, Karpenter node provisioning',
  },
  {
    icon: '🔄',
    title: 'GitOps',
    desc: 'Flux CD, Argo CD, OCI delivery, Flux Operator, gitless clusters',
  },
  {
    icon: '🏗️',
    title: 'Terraform',
    desc: 'Blast radius analysis, IAM least-privilege, SOC 2 controls',
  },
  {
    icon: '☁️',
    title: 'AWS',
    desc: 'CloudFront, WAF, Lambda@Edge, IAM / IRSA, multi-account SSO',
  },
  {
    icon: '🔒',
    title: 'Security',
    desc: 'Supply chain (Cosign, SBOM, SLSA), Falco, OPA, Kyverno, Trivy',
  },
  {
    icon: '📊',
    title: 'Observability',
    desc: 'Datadog, Dynatrace, OpenTelemetry, LLM observability, DORA',
  },
];

function FeatureStrip() {
  return (
    <section className="feature-strip">
      <h2 className="feature-strip__heading">Everything a platform team needs</h2>
      <div className="feature-grid">
        {FEATURES.map((f) => (
          <div className="feature-tile" key={f.title}>
            <div className="feature-tile__icon">{f.icon}</div>
            <div className="feature-tile__title">{f.title}</div>
            <div className="feature-tile__desc">{f.desc}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

function InstallSection() {
  return (
    <section className="install-section">
      <h2 className="install-section__heading">Install in your agent</h2>
      <p className="install-section__sub">One command. Works where you work.</p>
      <Tabs>
        <TabItem value="claude" label="Claude Code" default>
          <CodeBlock language="bash">
            claude plugin install nitinjain999/platform-skills
          </CodeBlock>
        </TabItem>
        <TabItem value="cursor" label="Cursor">
          <p>
            Open Cursor Settings → Rules → search <code>platform-skills</code> in the marketplace.
          </p>
          <p>Fallback (manual install):</p>
          <CodeBlock language="bash">
            ./install.sh --cursor --target .
          </CodeBlock>
        </TabItem>
        <TabItem value="copilot" label="VS Code / Copilot">
          <CodeBlock language="bash">
            ./install.sh --copilot --target .
          </CodeBlock>
          <p>
            Drops <code>.github/copilot-instructions.md</code> into your project.
          </p>
        </TabItem>
        <TabItem value="codex" label="Codex">
          <CodeBlock language="bash">
            codex skill add nitinjain999/platform-skills
          </CodeBlock>
        </TabItem>
      </Tabs>
    </section>
  );
}

const COMMANDS = [
  {
    name: '/platform-skills:triage',
    desc: 'Triages a PR comment from a bot or human reviewer — fetches via gh CLI, classifies it, applies the fix, posts a reply, and resolves the thread.',
  },
  {
    name: '/platform-skills:checkov',
    desc: 'Runs Checkov static and plan-level Terraform scanning with AI-generated fix mode. Supports AWS/Azure/GCP/EKS, private modules, SARIF output.',
  },
  {
    name: '/platform-skills:karpenter',
    desc: 'Diagnoses Karpenter node provisioning failures. Covers NodePool, NodeClaim, EC2NodeClass, spot interruptions — with blast radius and rollback plan.',
  },
];

function CommandShowcase() {
  return (
    <section className="command-section">
      <h2 className="command-section__heading">Slash commands that do real work</h2>
      <div className="command-cards">
        {COMMANDS.map((c) => (
          <div className="command-card" key={c.name}>
            <div className="command-card__name">{c.name}</div>
            <div className="command-card__desc">{c.desc}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline}>
      <main>
        <Hero />
        <BeforeAfter />
        <FeatureStrip />
        <InstallSection />
        <CommandShowcase />
      </main>
    </Layout>
  );
}
