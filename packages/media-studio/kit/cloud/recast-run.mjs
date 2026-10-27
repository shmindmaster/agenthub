// Cloud entry for Recast finishing: node recast-run.mjs <rawDir> <outFile> [optsJson]
// Runs the kit's own renderRecast so the cloud result matches a local `record-job` finish.
import { renderRecast } from '../screencast/record-lib.mjs';

const [rawDir, outFile, optsJson] = process.argv.slice(2);
if (!rawDir || !outFile) {
  console.error('usage: recast-run.mjs <rawDir> <outFile> [optsJson]');
  process.exit(2);
}
await renderRecast(rawDir, outFile, optsJson ? JSON.parse(optsJson) : {});
console.log(`recast: ${outFile}`);
