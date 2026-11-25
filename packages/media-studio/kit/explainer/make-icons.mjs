#!/usr/bin/env node
// Rebuild icons.json, the curated icon set diagram nodes name, from an unpacked
// lucide-static package.
//
//   npm pack lucide-static@<version> && tar xzf lucide-static-<version>.tgz
//   node make-icons.mjs <unpacked package directory>
//
// The set is vendored so the builder can check an icon name and the renderer can
// draw it with no install and no network. Lucide is ISC (some icons MIT, from
// Feather); icons-LICENSE.txt is the copy its licence asks for.
import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const NAMES = `
activity alarm-clock archive arrow-right badge-check ban banknote battery bell book book-open bot box boxes brain
briefcase bug building building-complex bus calculator calendar calendar-check camera car chart-bar chart-column
chart-line chart-pie check circle-alert circle-check circle-dollar-sign circle-question-mark circle-x clipboard
clipboard-check clipboard-list clock cloud cloud-rain cloud-sun code coffee cog coins compass construction contact cpu
credit-card croissant database download dollar-sign dumbbell eye eye-off factory file file-check file-text files
fingerprint-pattern flag flame flask-conical folder folder-open gauge gavel gift git-branch git-merge globe
graduation-cap hammer hand handshake hard-hat headphones heart heart-pulse hourglass house image inbox info key
key-round landmark laptop layers leaf library lightbulb link list list-checks list-todo lock lock-open mail map map-pin
megaphone menu message-circle message-square mic microscope minus monitor moon mouse-pointer-click network newspaper
notebook notebook-pen package package-check package-search pause pencil percent phone pill plane play plug plus pointer
power printer puzzle qr-code receipt recycle refresh-cw repeat rocket rotate-ccw route ruler save scale scan school
scissors search send server server-cog settings share-2 shield shield-alert shield-check shopping-bag shopping-cart
signature smartphone snowflake sparkles square-check star stethoscope store sun syringe table tablet tag target
telescope thermometer thumbs-up timer trash trending-down trending-up triangle-alert trophy truck umbrella undo-2 unplug
upload user user-check user-plus user-x users utensils video wallet warehouse waves-horizontal wifi wind workflow wrench
x zap
`.trim().split(/\s+/);

const source = process.argv[2] ? resolve(process.argv[2]) : null;
if (!source) {
  console.error('Usage: node make-icons.mjs <unpacked lucide-static directory>');
  process.exit(1);
}
const here = dirname(fileURLToPath(import.meta.url));
const nodes = JSON.parse(readFileSync(join(source, 'icon-nodes.json'), 'utf8'));
const { version } = JSON.parse(readFileSync(join(source, 'package.json'), 'utf8'));
const missing = NAMES.filter((name) => !nodes[name]);
if (missing.length) {
  console.error(`lucide-static ${version} has no ${missing.join(', ')}`);
  process.exit(1);
}
const lines = [...NAMES].sort().map((name) => `    ${JSON.stringify(name)}: ${JSON.stringify(nodes[name])}`);
writeFileSync(
  join(here, 'icons.json'),
  `{\n  "source": "lucide-static@${version}",\n  "license": "ISC, some icons MIT (Feather); see icons-LICENSE.txt",\n  "icons": {\n${lines.join(',\n')}\n  }\n}\n`,
);
copyFileSync(join(source, 'LICENSE'), join(here, 'icons-LICENSE.txt'));
console.log(`${NAMES.length} icons from lucide-static ${version}`);
