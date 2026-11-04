// Discover tools on demand using supported SDK hooks in new Cline sessions.
// Original implementations and approval policies remain owned by Cline.

const discoveryName = "find_tools";
let catalog = new Map();
const selected = new Set();
const stopWords = new Set("a an and are as at be by can do for from get i in is it me my of on or please the to tool tools use using want with".split(" "));
const words = (text) => [...new Set(String(text ?? "").toLowerCase()
  .split(/[^a-z0-9]+/).filter((word) => word.length > 1 && !stopWords.has(word))
  .map((word) => word.length > 4 ? word.replace(/s$/, "") : word))];

// AgentTool is a plain SDK interface; avoid importing the full SDK in the
// compiled Desktop worker, where that import can exceed initialization time.
const discovery = {
  name: discoveryName,
  description: "Find and load tools needed for a task. Other tools are available but their definitions are hidden until requested here. Search by capability or exact tool name. Capabilities include reading/editing files, code search, terminal commands, web search/fetch (Exa, Firecrawl), library docs (Context7), browser automation (agent-browser skill and terminal), skills, tasks, connected apps (Linear, Notion, Railway, Descript). Call this when a task needs tools; do not claim tools are unavailable without searching. Results become callable on your next model step for this user turn. Plain conversation needs no tool call. Loading a tool does not execute it or grant permission for its actions. Search again for additional capabilities as needed.",
  inputSchema: {
    type: "object",
    properties: {
      query: { type: "string", description: "Specific capability needed, e.g. read a local file, search web with Exa, or query Context7 documentation." },
      names: { type: "array", items: { type: "string" }, description: "Optional exact tool names instead of keyword matching." },
      limit: { type: "integer", minimum: 1, maximum: 5, description: "Maximum tools to load this call, default 3." }
    },
    required: ["query"],
    additionalProperties: false
  },
  async execute(input) {
    const limit = Math.min(5, Math.max(1, Number.isFinite(input.limit) ? Math.floor(input.limit) : 3));
    const exact = Array.isArray(input.names) ? [...new Set(input.names.filter((name) => typeof name === "string"))] : [];
    let matches;
    const knownNames = exact.filter((name) => catalog.has(name));
    if (knownNames.length) {
      matches = knownNames.slice(0, limit).map((name) => catalog.get(name));
    } else {
      const queryWords = words(input.query);
      const ranked = [...catalog.values()].map((tool) => {
        const nameWords = words(tool.name);
        const descriptionWords = new Set(words(tool.description));
        let score = queryWords.reduce((sum, word) => sum +
          (nameWords.includes(word) ? 12 : nameWords.some((nameWord) => nameWord.startsWith(word)) ? 6 : descriptionWords.has(word) ? 1 : 0), 0);
        // Local skill discovery is distinct from managing an app's agent skills.
        if (tool.name === "skills" && queryWords.some((word) => word === "skill")) score += 40;
        if (tool.name === "run_commands" && queryWords.some((word) => ["terminal", "shell", "command"].includes(word))) score += 25;
        return { tool, score };
      }).filter(({ score }) => score > 0)
        .sort((a, b) => b.score - a.score || a.tool.name.localeCompare(b.tool.name));
      // Avoid loading weak keyword matches beside a clear capability match.
      const threshold = (ranked[0]?.score ?? 0) * 0.65;
      matches = ranked.filter(({ score }) => score >= threshold).slice(0, limit).map(({ tool }) => tool);
    }
    for (const tool of matches) selected.add(tool.name);
    return {
      loaded: matches.map(({ name, description }) => ({ name, description: description?.slice(0, 240) ?? "" })),
      unavailableNames: exact.filter((name) => !catalog.has(name)),
      message: matches.length ? "Loaded tools are callable on your next step. Use their full schemas then. Existing permissions still apply." : "No matching tools. Try a more specific capability or another search term."
    };
  }
};

export default {
  name: "lightweight-chat",
  manifest: {
    capabilities: ["tools", "hooks"],
    providerIds: ["openai-compatible"],
    modelIds: ["qwen3.8-max"]
  },
  setup(api) {
    api.registerTool(discovery);
  },
  hooks: {
    beforeRun() {
      selected.clear();
    },
    beforeModel({ request }) {
      const tools = request.tools ?? [];
      catalog = new Map(tools.filter((tool) => tool.name !== discoveryName).map((tool) => [tool.name, tool]));
      const visible = tools.filter((tool) => tool.name === discoveryName || selected.has(tool.name));
      const options = { ...request.options };
      // Qwen otherwise defaults to xhigh. Honor an explicit effort/off/budget.
      if (options.reasoningEffort == null && options.thinking !== false && options.thinkingBudgetTokens == null) {
        options.reasoningEffort = "low";
      }
      return { tools: visible, options };
    }
  }
};
