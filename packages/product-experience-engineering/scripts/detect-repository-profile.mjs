#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || process.cwd());
const exists = (relative) => fs.existsSync(path.join(root, relative));
const readJson = (relative) => {
  try {
    return JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
  } catch {
    return null;
  }
};

const packageJson = readJson('package.json');
const dependencies = {
  ...(packageJson?.dependencies || {}),
  ...(packageJson?.devDependencies || {}),
};

const packageManager = exists('pnpm-lock.yaml')
  ? 'pnpm'
  : exists('yarn.lock')
    ? 'yarn'
    : exists('bun.lockb') || exists('bun.lock')
      ? 'bun'
      : exists('package-lock.json')
        ? 'npm'
        : null;

const frameworks = [
  ['next', 'Next.js'],
  ['react', 'React'],
  ['vue', 'Vue'],
  ['nuxt', 'Nuxt'],
  ['@angular/core', 'Angular'],
  ['svelte', 'Svelte'],
  ['@sveltejs/kit', 'SvelteKit'],
  ['astro', 'Astro'],
  ['vite', 'Vite'],
].filter(([dependency]) => dependency in dependencies).map(([, label]) => label);

const testing = [
  ['@playwright/test', 'Playwright'],
  ['cypress', 'Cypress'],
  ['vitest', 'Vitest'],
  ['jest', 'Jest'],
  ['@testing-library/react', 'Testing Library'],
  ['axe-core', 'axe-core'],
].filter(([dependency]) => dependency in dependencies).map(([, label]) => label);

const uiSystems = [
  ['@radix-ui/react-dialog', 'Radix UI'],
  ['@headlessui/react', 'Headless UI'],
  ['@mui/material', 'Material UI'],
  ['@chakra-ui/react', 'Chakra UI'],
  ['antd', 'Ant Design'],
  ['tailwindcss', 'Tailwind CSS'],
].filter(([dependency]) => dependency in dependencies).map(([, label]) => label);

const instructionFiles = ['AGENTS.md', 'CLAUDE.md', 'CONTRIBUTING.md'].filter(exists);
const routeRoots = ['app', 'src/app', 'pages', 'src/pages', 'routes', 'src/routes'].filter(exists);

console.log(JSON.stringify({
  root,
  packageManager,
  frameworks,
  testing,
  uiSystems,
  instructionFiles,
  routeRoots,
  scripts: packageJson?.scripts || {},
}, null, 2));

