// Local dry-run only. No implicit GitHub namespace discovery and no credentials here.
const manifest = require('../portfolio.json');
const presets = require('./default.json');
const eligible = new Set(manifest.repos.filter(r => r.dependencyAutomation === 'renovate-candidate' && r.remote).map(r => r.remote));
const selected = (process.env.PORTFOLIO_RENOVATE_REPOS || '').split(',').map(s => s.trim()).filter(Boolean);
if (!selected.length || selected.some(repo => !eligible.has(repo))) throw new Error('Select explicitly allowlisted Renovate candidates using PORTFOLIO_RENOVATE_REPOS');
module.exports = {
  platform: 'github',
  autodiscover: false,
  repositories: [...new Set(selected)],
  dryRun: 'full',
  requireConfig: 'optional',
  onboarding: false,
  dependencyDashboard: false,
  allowedCommands: [],
  allowScripts: false,
  onboardingConfig: presets,
  force: {...presets, extends: presets.extends, automerge: false, dependencyDashboard: false}
};
