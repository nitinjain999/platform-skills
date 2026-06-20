// @ts-check
// This file is kept for reference. The actual sidebars are split into:
//   sidebars-references.js  — consumed by the 'references' plugin (sidebarId: 'referencesSidebar')
//   sidebars-commands.js    — consumed by the 'commands' plugin   (sidebarId: 'commandsSidebar')
//
// Docusaurus validates every sidebar ID against only the plugin that loads it.
// Sharing a single file across two plugins with disjoint doc sets causes ID-not-found
// errors, so each plugin gets its own file in docusaurus.config.js.

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  referencesSidebar: require('./sidebars-references').referencesSidebar,
  commandsSidebar: require('./sidebars-commands').commandsSidebar,
};

module.exports = sidebars;
