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
        Your AI agent generates config. It doesn&apos;t know what breaks.
        Platform Skills gives it the missing context — blast radius, validation steps, and rollback plan, built in.
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

function ProblemStatement() {
  return (
    <section className="problem-section">
      <div className="problem-section__inner">
        <div className="problem-section__label">The problem</div>
        <h2 className="problem-section__heading">
          AI agents are great at writing YAML.<br />They&apos;re not great at knowing what happens next.
        </h2>
        <div className="problem-grid">
          <div className="problem-item">
            <div className="problem-item__icon">💥</div>
            <div className="problem-item__text">Adds a CPU limit that throttles production at peak load</div>
          </div>
          <div className="problem-item">
            <div className="problem-item__icon">🔓</div>
            <div className="problem-item__text">Writes IAM policies with wildcards because it&apos;s &quot;simpler&quot;</div>
          </div>
          <div className="problem-item">
            <div className="problem-item__icon">🕳️</div>
            <div className="problem-item__text">No mention of what breaks if the change is wrong</div>
          </div>
          <div className="problem-item">
            <div className="problem-item__icon">🤷</div>
            <div className="problem-item__text">No validation steps. No rollback plan. Ships anyway.</div>
          </div>
        </div>
        <p className="problem-section__resolution">
          Platform Skills is a plugin that teaches your agent to think like a senior platform engineer —
          not just generate, but reason.
        </p>
      </div>
    </section>
  );
}

const STAR_SCENARIOS = [
  {
    tag: 'Security',
    situation: 'A pipeline flags a CRITICAL CVE in your base image 30 minutes before a release window.',
    task: 'Scan the image, understand blast radius, decide whether to block or accept risk with a documented exception.',
    command: '/platform-skills:trivy image',
    result: 'Severity-gated scan with exploitability context, a pre-filled .trivyignore entry with expiry date, and a go/no-go recommendation with rollback path if you ship.',
  },
  {
    tag: 'Code Review',
    situation: 'Copilot left 12 unresolved review threads on your PR. Release is blocked until they\'re cleared.',
    task: 'Classify each comment, fix the real issues, reply to every thread, and resolve them — without missing one.',
    command: '/platform-skills:triage --all 100',
    result: 'Every thread triaged: ACTIONABLE ones fixed and committed, INFORMATIONAL ones answered, NOT_APPLICABLE ones closed with a reason. Summary table printed.',
  },
  {
    tag: 'Infrastructure',
    situation: 'Security asks if a Terraform change is safe to apply to production. You have 20 minutes.',
    task: 'Scan against the actual plan (not just source), surface HIGH/CRITICAL findings, map them to SOC 2 controls.',
    command: '/platform-skills:checkov plan',
    result: 'Deep analysis against live state values, findings grouped by control, a .checkov.baseline diff showing what\'s new vs existing, and a one-line verdict: safe / needs fix / block.',
  },
];

function StarScenarios() {
  return (
    <section className="star-section">
      <div className="star-section__label">Real usage, real results</div>
      <h2 className="star-section__heading">See it in a real situation</h2>
      <p className="star-section__sub">
        Every command follows the same pattern: understand the situation, take the right action, show the result.
      </p>
      <div className="star-cards">
        {STAR_SCENARIOS.map((s) => (
          <div className="star-card" key={s.command}>
            <div className="star-card__tag">{s.tag}</div>
            <div className="star-card__row">
              <span className="star-card__letter">S</span>
              <span className="star-card__content">{s.situation}</span>
            </div>
            <div className="star-card__row">
              <span className="star-card__letter">T</span>
              <span className="star-card__content">{s.task}</span>
            </div>
            <div className="star-card__row star-card__row--action">
              <span className="star-card__letter star-card__letter--action">A</span>
              <code className="star-card__command">{s.command}</code>
            </div>
            <div className="star-card__row">
              <span className="star-card__letter star-card__letter--result">R</span>
              <span className="star-card__content">{s.result}</span>
            </div>
          </div>
        ))}
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
      <h2 className="feature-strip__heading">35+ commands. Every domain a platform team touches.</h2>
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
          <div className="install-block__step-label">Add to marketplace</div>
          <CodeBlock language="bash">
            claude plugin marketplace add https://github.com/nitinjain999/platform-skills
          </CodeBlock>
          <div className="install-block__step-label">Install</div>
          <CodeBlock language="bash">
            claude plugin install platform-skills
          </CodeBlock>
          <div className="install-block__step-label">Upgrade to latest</div>
          <CodeBlock language="bash">
            claude plugin update platform-skills
          </CodeBlock>
        </TabItem>
        <TabItem value="cursor" label="Cursor">
          <div className="install-block__step-label">Install from marketplace</div>
          <p>
            Open Cursor Settings → Rules → search <code>platform-skills</code> in the marketplace.
          </p>
          <div className="install-block__step-label">Or install manually</div>
          <CodeBlock language="bash">
            ./install.sh --cursor --target .
          </CodeBlock>
          <div className="install-block__step-label">Upgrade</div>
          <CodeBlock language="bash">
            ./install.sh --cursor --target . --upgrade
          </CodeBlock>
        </TabItem>
        <TabItem value="copilot" label="VS Code / Copilot">
          <div className="install-block__step-label">Add to marketplace</div>
          <CodeBlock language="bash">
            copilot plugin marketplace add nitinjain999/platform-skills
          </CodeBlock>
          <div className="install-block__step-label">Install</div>
          <CodeBlock language="bash">
            copilot plugin install platform-skills@platform-skills
          </CodeBlock>
          <div className="install-block__step-label">Or install manually</div>
          <CodeBlock language="bash">
            ./install.sh --copilot --target .
          </CodeBlock>
        </TabItem>
        <TabItem value="codex" label="Codex">
          <div className="install-block__step-label">Install</div>
          <CodeBlock language="bash">
            codex skill add nitinjain999/platform-skills
          </CodeBlock>
          <div className="install-block__step-label">Upgrade</div>
          <CodeBlock language="bash">
            codex skill update nitinjain999/platform-skills
          </CodeBlock>
        </TabItem>
      </Tabs>
    </section>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline}>
      <main>
        <Hero />
        <ProblemStatement />
        <StarScenarios />
        <FeatureStrip />
        <InstallSection />
      </main>
    </Layout>
  );
}
