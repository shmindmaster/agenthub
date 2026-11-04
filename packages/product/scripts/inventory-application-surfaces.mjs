#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || process.cwd());
const ignored = new Set(['.git', '.next', '.nuxt', '.svelte-kit', 'node_modules', 'dist', 'build', 'coverage', 'vendor']);
const routeExtensions = new Set(['.js', '.jsx', '.ts', '.tsx', '.mjs', '.mts', '.mdx', '.vue', '.svelte']);
const routeFiles = [];

function walk(directory) {
  if (!fs.existsSync(directory)) return;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && ignored.has(entry.name)) continue;
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (routeExtensions.has(path.extname(entry.name).toLowerCase()) && isRouteFile(full)) routeFiles.push(full);
  }
}

function isRouteFile(file) {
  const relative = normalize(path.relative(root, file));
  const base = path.basename(file, path.extname(file));
  if (/^(src\/)?app\//.test(relative)) return base === 'page' || base === 'route';
  if (/^(src\/)?pages\//.test(relative)) return !/^_(app|document)$/.test(base);
  if (/^(src\/)?routes\//.test(relative)) return true;
  return false;
}

function normalize(value) {
  return value.replaceAll('\\', '/');
}

function routeFromFile(file) {
  let relative = normalize(path.relative(root, file));
  relative = relative.replace(/^(src\/)?(app|pages|routes)\//, '');
  relative = relative.replace(/\/(page|route)\.[^.]+$/, '');
  relative = relative.replace(/\.[^.]+$/, '');
  relative = relative.replace(/(^|\/)index$/, '');
  relative = relative.replace(/(^|\/)\([^/]+\)/g, '$1');
  relative = relative.replace(/(^|\/)@[^/]+/g, '$1');
  relative = relative.replace(/\[\.\.\.(\w+)\]/g, ':$1*').replace(/\[(\w+)\]/g, ':$1');
  return '/' + relative.replace(/^\/+|\/+$/g, '');
}

function classify(route) {
  const value = route.toLowerCase();
  if (/(^|\/)(internal|ops|operations|staff|backoffice|back-office|support-console|moderation)(\/|$)/.test(value)) return 'internal-operations';
  if (/(^|\/)(admin|organization|organisation|members|roles|permissions|tenant)(\/|$)/.test(value)) return 'customer-administration';
  if (/(^|\/)(billing|pricing|checkout|invoice|subscription|plan|usage|payment)(\/|$)/.test(value) && value !== '/pricing') return 'billing-commerce';
  if (/(^|\/)(auth|login|log-in|sign-in|signin|signup|sign-up|register|invite|verify|onboarding|forgot|reset-password)(\/|$)/.test(value)) return 'authentication-onboarding';
  if (/(^|\/)(help|support|docs|documentation|feedback|status|release-notes)(\/|$)/.test(value)) return 'help-support';
  if (/(^|\/)(api|developer|developers|webhook|integrations|credentials|keys)(\/|$)/.test(value)) return 'developer-platform';
  if (/(^|\/)(settings|profile|account|security|sessions|preferences)(\/|$)/.test(value)) return 'account-security';
  if (value === '/' || /(^|\/)(pricing|features|solutions|about|contact|blog|legal|privacy|terms|security|trust)(\/|$)/.test(value)) return 'public-marketing';
  return 'core-application';
}

walk(root);

const routes = routeFiles
  .map((file) => {
    const route = routeFromFile(file);
    return { route, classification: classify(route), file: normalize(path.relative(root, file)) };
  })
  .sort((a, b) => a.route.localeCompare(b.route) || a.file.localeCompare(b.file));

const summary = Object.fromEntries(
  [...new Set(routes.map((item) => item.classification))]
    .sort()
    .map((classification) => [classification, routes.filter((item) => item.classification === classification).length]),
);

console.log(JSON.stringify({
  root,
  routes,
  summary,
  warnings: [
    'Route classification is heuristic and must be reconciled with runtime navigation, permissions, external channels, and repository documentation.',
    'Absence from this list does not prove a surface is absent.',
  ],
}, null, 2));
