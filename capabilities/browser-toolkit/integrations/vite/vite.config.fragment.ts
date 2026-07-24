import { defineConfig } from "vite";
import devtoolsJson from "vite-plugin-devtools-json";

// Merge into the repository's existing config; do not replace its plugins.
// Keep the repository's established plugin order unless the plugin's official
// release notes require a specific position.
export default defineConfig({
  plugins: [
    devtoolsJson({ uuid: "<STABLE_REPOSITORY_UUID>" }),
    // ...existingPlugins
  ],
});
