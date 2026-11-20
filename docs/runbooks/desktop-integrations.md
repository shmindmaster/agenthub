# Desktop agent integrations

The fleet registry records AutoClaw, Grok Bot, and Manus Studio as separate Windows interfaces. AgentHub verifies installation without opening a window. Account configuration lives in each app. Public plugin registration, private skill import, and account OAuth each require separate evidence before promoting a host to managed deployment.

## Native connector setup

| Interface | Setup | Capability check |
| --- | --- | --- |
| AutoClaw Desktop | In Settings, open Tools & connections, then Extension tools. Use the vendor's skill import to add a supported skill package. | Reopen the task, confirm the MCP tools are visible, and run a read-only tool. [AutoClaw MCP](https://autoclaw.z.ai/en/docs/advanced/mcp-connectors/) · [AutoClaw skills](https://autoclaw.z.ai/en/docs/advanced/skill/) |
| Grok Bot Desktop | Under Connect apps, use the vendor catalog when available. Add a custom connector as Remote HTTPS for a public MCP endpoint and use the app's Connect card for account consent when required. Choose the intended team because connectors can be account-wide. | Start a fresh task and verify the connector tools. The Bot browser runs on its own cloud computer. Confirm that environment separately from Grok Build or local Chrome. [Grok Bot apps and computer](https://docs.x.ai/grok-bot/computer-and-apps) |
| Manus Studio | Open Connectors → Create → Add MCP by URL. Use the vendor catalog for supported app accounts. Import supported `SKILL.md` bundles through Agent Skills. | Confirm the tool appears in the intended workspace and run a read-only call from a fresh task. Test the cloud sandbox browser separately. [Manus Connectors](https://www.manus.im/features/connectors) · [Manus Agent Skills](https://www.manus.im/features/agent-skills) |

Use `https://mcp.parallel.ai/mcp?tools=web_search,web_fetch` for the first unauthenticated connector check. Fetch a public example page and verify the tool returned content. A successful hosted endpoint handshake does not prove the app saved or loaded the connector. For account-backed MCPs, verify the selected organization in the provider session and use the app's credential store. [Parallel MCP](https://parallel.ai/mcp)

## Browser verification

Run a synthetic form and extract a known table in the app's own browser environment. Verify that the recorded result matches the page and whether the operator can observe or take control without interrupting their normal Windows browser. Test screenshots, event recording, console and network data, and playable video separately. Use AH Browser and Media Studio on an isolated local test page for the shared Windows workflow. Treat its recording as evidence for that local workflow only.
