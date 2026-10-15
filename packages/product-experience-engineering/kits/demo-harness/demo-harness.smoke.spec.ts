// demo-harness/v1 smoke spec template. Copy into the product's e2e folder
// (the path named by `smokeSpec` in demo/harness.json), then add one test per
// "Demonstrate now" fact the film depends on. Run it after every reset.
//
// This is an engineering test owned by the product. Media capture code
// (scenes, Recast) lives in the media-studio job workspace, not here.

import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const harness = JSON.parse(readFileSync(resolve(process.env.DEMO_HARNESS_FILE ?? "demo/harness.json"), "utf8"));
const expectedSha = process.env.DEMO_EXPECTED_SHA; // optional: the SHA the take must be shot against

test.describe("demo harness", () => {
  for (const endpoint of harness.versionEndpoints) {
    test(`version endpoint answers with a real SHA: ${endpoint.service}`, async ({ request }) => {
      const response = await request.get(endpoint.url);
      expect(response.ok()).toBeTruthy();
      const body = await response.json();
      expect(body.schema).toBe("deployed-version/v1");
      expect(body.gitSha).toMatch(/^[0-9a-f]{40}$/);
      if (expectedSha) expect(body.gitSha).toBe(expectedSha);
    });
  }

  test("synthetic-data label is visible on the first screen", async ({ page }) => {
    // Sign in as the demo tenant's first role here (product-specific).
    await page.goto(harness.baseUrl);
    const label = page.getByTestId(harness.syntheticLabel.testId);
    await expect(label).toBeVisible();
    await expect(label).toContainText("Synthetic");
  });

  // test("<Demonstrate-now fact>", async ({ page }) => { ... });
});
