// @ts-check
const { themes: prismThemes } = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Platform Skills',
  tagline: 'A production-grade field handbook for platform engineers',
  favicon: 'img/favicon.ico',

  url: 'https://nitinjain999.github.io',
  baseUrl: '/platform-skills/',

  organizationName: 'nitinjain999',
  projectName: 'platform-skills',
  trailingSlash: false,

  // Cross-plugin refs (commands/ → references/) and examples/ paths are intentional
  // agent-skill cross-references for the CLI — not web links. Ignore at build time.
  onBrokenLinks: 'ignore',

  markdown: {
    // Process .md files as CommonMark (not MDX) — tolerates raw HTML tags and
    // angle-bracket constructs present in the existing references/ and commands/ files.
    format: 'detect',
    hooks: {
      // Cross-plugin refs (commands/ → references/) and examples/ links are
      // agent-skill cross-references, not web links — suppress broken-link noise.
      onBrokenMarkdownLinks: 'ignore',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: false, // disabled — we use standalone plugin instances below
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  plugins: [
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'references',
        path: '../references',
        routeBasePath: 'docs',
        sidebarPath: require.resolve('./sidebars-references.js'),
        sidebarCollapsible: true,
        sidebarCollapsed: false,
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'commands',
        path: '../commands',
        routeBasePath: 'commands',
        sidebarPath: require.resolve('./sidebars-commands.js'),
        sidebarCollapsible: true,
        sidebarCollapsed: false,
      },
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      colorMode: {
        defaultMode: 'dark',
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'Platform Skills',
        logo: {
          alt: 'Platform Skills',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'referencesSidebar',
            docsPluginId: 'references',
            position: 'left',
            label: 'References',
          },
          {
            type: 'docSidebar',
            sidebarId: 'commandsSidebar',
            docsPluginId: 'commands',
            position: 'left',
            label: 'Commands',
          },
          {
            href: 'https://github.com/nitinjain999/platform-skills',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              { label: 'Kubernetes', to: '/docs/kubernetes' },
              { label: 'GitOps', to: '/docs/fluxcd' },
              { label: 'Terraform', to: '/docs/terraform' },
            ],
          },
          {
            title: 'More',
            items: [
              { label: 'GitHub', href: 'https://github.com/nitinjain999/platform-skills' },
              { label: 'Changelog', href: 'https://github.com/nitinjain999/platform-skills/blob/main/CHANGELOG.md' },
            ],
          },
        ],
        copyright: `Apache 2.0 — Platform Skills`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['bash', 'yaml', 'hcl', 'typescript'],
      },
    }),
};

module.exports = config;
