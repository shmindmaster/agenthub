# security

Fleet-shared security scanners. Canonical home for `config-payload-scanner`.

## config-payload-scanner

Detects config files (`*.config.{mjs,cjs,js,ts}`, `postcss.*`, `tailwind.*`,
`vite.*`, `next.*`, `eslint.*`, `playwright.*`, `vitest.*`, `jest.*`,
`prisma.*`, and named variants such as `babel.config.mjs`) carrying an
obfuscated-loader malware payload. Signatures covered:

- `global['!']` / `global require alias` -- obfuscated global-scope loader shims.
- `_$_ obfuscated loader table` / `known obfuscated loader symbol` -- named
  symbols observed in a real incident's minified payload.
- `blockchain payload endpoint` -- calls out to known exfiltration endpoints
  (TronGrid, Aptos mainnet).
- `behavioral remote execution loader` -- `Function`/`constructor.constructor`
  combined with `eval` and a network or `child_process` primitive.
- `campaign marker` -- the `global.i="A9-<year>-<sequence>"` tag this campaign
  stamps into every file it touches.
- `overlong config line` -- any line over 4000 characters in a matched config
  file, which is how a minified payload gets appended without disturbing the
  file's normal formatting.
- `createRequire shim in config` -- a `createRequire` import inside a
  postcss/tailwind/babel/eslint config, which is how a payload regains
  `require()` inside an otherwise pure-ESM config format.

### Run ad hoc

```sh
node packages/security/scripts/check-config-payloads.mjs --root <path-to-repo>
```

Exits `1` and prints one `<file>:<line> (<signature>)` line per finding on
stderr if anything is flagged; exits `0` and prints `Config payload scan
passed.` otherwise. `--root` defaults to the current working directory.

### Install the pre-push hook in another repo

Copy or symlink the hook into the target repository's own hooks directory and
make it executable. This preserves any existing hooks and lets you chain them.

```sh
hooks_dir="$(git -C <path-to-repo> rev-parse --git-path hooks)"
cp packages/security/hooks/pre-push "$hooks_dir/pre-push"
chmod +x "$hooks_dir/pre-push"
```

If the repository already has a `pre-push` hook, chain the original logic from
this one. For example, save the existing hook as `pre-push.original` and call
it at the end of the new `pre-push`:

```sh
hooks_dir="$(git -C <path-to-repo> rev-parse --git-path hooks)"
mv "$hooks_dir/pre-push" "$hooks_dir/pre-push.original"
cp packages/security/hooks/pre-push "$hooks_dir/pre-push"
chmod +x "$hooks_dir/pre-push"
# Edit $hooks_dir/pre-push and add the following before the final exit:
# "$hooks_dir/pre-push.original" "$@"
```

`core.hooksPath` is an option only for repositories that have **no other
hooks**, because it replaces the entire `.git/hooks` directory:

```sh
git -C <path-to-repo> config core.hooksPath ../agenthub/packages/security/hooks
```

(adjust the relative path to wherever your `agenthub` checkout actually sits
relative to the target repo).

The hook resolves the scanner relative to the pushing repo's sibling
`agenthub` checkout first, then falls back to `$AGENTHUB_HOME` if set. If
neither location has the scanner, it warns and lets the push through rather
than blocking on a missing capability.

### Test

```sh
node --test packages/security/scripts/*.test.mjs
```
