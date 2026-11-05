# Testing an app as a user

Test through the interface a person uses. Do not call the app's API or edit the DOM to get past a step; if a user could not do it, it is not a pass.

## Procedure

1. **Journeys.** From the app's purpose, list three to five journeys a real user takes (sign up, find, buy, fix a mistake, leave). Write each as numbered steps with an expected result.
2. **Target.** Start the app on `127.0.0.1` and pass `--allowed-domains 127.0.0.1,localhost` so a link cannot take the browser elsewhere.
3. **Run each journey** at three viewports: `set viewport 390 844`, `768 1024`, `1440 900`. Repeat the main journey once with `set media dark` and once with `set media reduced-motion`.
4. **After every step** run `console` and `network requests`, and look for failed or 4xx and 5xx requests. An error nobody sees on screen is still a defect.
5. **Keyboard pass.** Complete the main journey with `press Tab`, `Enter` and `Space` only. Note any control that cannot be reached, has no visible focus, or has no name in the snapshot.
6. **Unhappy states.** Empty data, a rejected form, a slow or offline network (`set offline on`), a long name, a double click on submit, the back button mid-flow.
7. **Evidence.** One screenshot at the end of each journey and one at every failure. Use `record start` only to show a hard-to-describe defect.

## Report

| Journey | 390 | 768 | 1440 | Keyboard | Notes |
|---|---|---|---|---|---|

Mark each cell PASS, FAIL or NOT RUN. For every FAIL give the numbered steps to reproduce, what you expected, what happened, severity (blocks the journey, degrades it, cosmetic) and the evidence path. End with what you did not cover; never imply coverage you did not run.

## Keep the checks

Journeys worth repeating become specs for the project's own test runner. With Playwright: `trace: 'retain-on-failure'`, `video: 'retain-on-failure'`, `screenshot: 'only-on-failure'`, and web-first assertions such as `await expect(page.getByRole('button', { name: 'Save' })).toBeVisible()`. Run `npx playwright test`; read the project's existing config before adding one.
