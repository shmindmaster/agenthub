import { readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

// The native CLI accepts a prompt argument. Supply it after Windows has
// started Node so long task files never go on the OS command line.
process.argv.push(readFileSync(0, 'utf8'));

const runtimeRoot = process.env.AGENTHUB_ZCODE_PLAYWRIGHT_ROOT;
if (runtimeRoot) {
  const { createRequire, registerHooks } = await import('node:module');
  if (typeof registerHooks !== 'function') {
    throw new Error('ZCode Browser Use requires Node with node:module registerHooks support.');
  }
  const require = createRequire(pathToFileURL(join(runtimeRoot, 'package.json')));
  const playwright = pathToFileURL(join(dirname(require.resolve('playwright-core/package.json')), 'index.mjs'));
  const zcode = pathToFileURL(realpathSync(process.argv[1])).href;

  registerHooks({
    resolve(specifier, context, nextResolve) {
      if (specifier === 'playwright-core' && context.parentURL === zcode) {
        try {
          return nextResolve(specifier, context);
        } catch (error) {
          if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error;
          return nextResolve(playwright.href, context);
        }
      }
      return nextResolve(specifier, context);
    },
  });
}
