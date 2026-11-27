import { spawnSync } from 'node:child_process';

const profile = process.env.AGENTHUB_BROWSER_PROFILE?.trim() || 'Edge Automation';
const engine = process.env.AGENTHUB_BROWSER_ENGINE?.trim() || 'edge';

function browserSkill(args) {
  const result = spawnSync('bsk', args, {
    encoding: 'utf8',
    timeout: 30_000,
    windowsHide: true,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `BrowserSkill exited with status ${result.status}`);
  }
  return JSON.parse(result.stdout);
}

try {
  const matches = browserSkill(['browsers', '--json']).filter(browser =>
    browser.label === profile && browser.browser_name === engine &&
    !browser.unresponsive && !browser.version_skew);
  if (matches.length !== 1 || !matches[0].instance_id) {
    throw new Error(`Expected exactly one responsive ${engine} automation profile named ${profile}.`);
  }

  const result = browserSkill([
    'session', 'start', '--browser', matches[0].instance_id, '--no-focus', '--json',
  ]);
  process.stdout.write(`${JSON.stringify(result)}\n`);
} catch (error) {
  console.error(`AgentHub browser session: ${error.message}`);
  process.exitCode = 1;
}
