// Builds throwaway home directories laid out the way each coding agent
// stores its config, so doctor can be tested without touching a real home.
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const platform = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'darwin' : 'linux';

/** Root of {roamingConfig} for a fixture home on this platform. */
export function roamingRoot(home) {
  if (platform === 'windows') return join(home, 'AppData', 'Roaming');
  if (platform === 'darwin') return join(home, 'Library', 'Application Support');
  return join(home, '.config');
}

/** Fake credentials assembled at runtime so the repository holds no token-shaped strings. */
export const fake = {
  github: 'gh' + 'p_' + 'A1b2C3d4E5'.repeat(4),
  openai: 's' + 'k-' + 'proj-' + 'x9Y8z7W6v5'.repeat(3),
  literal: 'Q7r' + 'Lm2' + 'Zp9' + 'Wx4' + 'Kc8Vb',
};

export function makeHome() {
  const home = mkdtempSync(join(tmpdir(), 'agenthub-doctor-'));
  const bin = join(home, 'fixture-bin');
  mkdirSync(bin, { recursive: true });
  return {
    home,
    bin,
    write(rel, content) {
      const full = join(home, ...rel.split('/'));
      mkdirSync(join(full, '..'), { recursive: true });
      writeFileSync(full, typeof content === 'string' ? content : JSON.stringify(content, null, 2));
      return full;
    },
    writeAbs(full, content) {
      mkdirSync(join(full, '..'), { recursive: true });
      writeFileSync(full, typeof content === 'string' ? content : JSON.stringify(content, null, 2));
      return full;
    },
    /** Puts a no-op command on the fixture PATH. */
    command(name) {
      const file = join(bin, platform === 'windows' ? `${name}.cmd` : name);
      writeFileSync(file, platform === 'windows' ? '@echo off\r\n' : '#!/bin/sh\n', { mode: 0o755 });
      return file;
    },
    env(extra = {}) {
      return { PATH: bin, PATHEXT: process.env.PATHEXT ?? '.COM;.EXE;.BAT;.CMD', ...extra };
    },
    skill(dir, name, frontmatter = { name, description: `Use when testing ${name}.` }, body = 'Body.') {
      const fm = frontmatter
        ? `---\n${Object.entries(frontmatter).map(([k, v]) => `${k}: ${v}`).join('\n')}\n---\n\n`
        : '';
      return this.write(`${dir}/${name}/SKILL.md`, `${fm}# ${name}\n\n${body}\n`);
    },
    cleanup() {
      rmSync(home, { recursive: true, force: true });
    },
  };
}

/** Every file under root with its bytes and mtime, to prove nothing was written. */
export function snapshot(root) {
  const out = {};
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) {
        out[full + '/'] = st.mtimeMs;
        walk(full);
      } else {
        out[full] = `${st.mtimeMs}:${readFileSync(full).toString('base64')}`;
      }
    }
  };
  walk(root);
  return out;
}
