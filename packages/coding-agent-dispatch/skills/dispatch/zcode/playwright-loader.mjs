import { realpathSync } from 'node:fs';
import { createRequire, registerHooks } from 'node:module';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const runtime = pathToFileURL(join(process.env.AGENTHUB_ZCODE_PLAYWRIGHT_ROOT, 'package.json'));
const require = createRequire(runtime);
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
