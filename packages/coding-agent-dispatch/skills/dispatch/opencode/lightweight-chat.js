// OpenCode 2 native plugin hooks. Discovery changes model context only;
// native executors, credentials, permissions and policy stay with OpenCode.
const finder = 'find_tools';
// Remove incompatible host references and nonessential/overlapping utilities
// from OpenCode's registry, not from the shared source library or other hosts.
const excludedSkills = [
  'built-in-browser', 'chrome-browser', 'computer-use', // Claude-only tools
  'google-workspace', 'docs', 'import-memory', 'morning', 'learn', // Cowork surfaces
  'sarosh-voice', 'internal-comms', // canonical communication/writing already own this
  'comedy-writer', 'engaging-exam-coach', 'slack-gif-creator', 'theme-factory'
];
const stop = new Set('a an and are as at be by can do for from get i in is it me my of on or please the to tool tools use using want with'.split(' '));
const words = text => [...new Set(String(text ?? '').toLowerCase().split(/[^a-z0-9]+/)
  .filter(word => word.length > 1 && !stop.has(word)))];
function rank(items, query, limit) {
  const terms = words(query);
  return items.map(item => ({ item, score: terms.reduce((sum, word) => sum +
    (words(item.name).includes(word) ? 12 : words(item.description).includes(word) ? 1 : 0), 0) }))
    .filter(item => item.score > 0).sort((a, b) => b.score - a.score || a.item.name.localeCompare(b.item.name))
    .slice(0, limit).map(({ item }) => item);
}
const skillNotice = '<available_skills>Skill descriptions are available on demand through find_tools. Search by skill name or task before choosing a skill; then use the native skill tool to load its full instructions. Explicitly requested and policy-required skills still apply.</available_skills>';

export default {
  id: 'agenthub.lightweight-chat',
  async setup(ctx) {
    await ctx.skill.transform(editor => {
      for (const id of excludedSkills) editor.remove(id);
    });
    const sessions = new Map();
    const state = id => {
      if (!sessions.has(id)) {
        if (sessions.size >= 256) sessions.delete(sessions.keys().next().value);
        sessions.set(id, { selected: new Set(), selectedServers: new Set(), tools: {}, skills: [], servers: [] });
      }
      return sessions.get(id);
    };
    await ctx.tool.transform(editor => editor.add({
      name: finder,
      description: 'Find and load tools or skills on demand. Search by capability or exact tool name. Capabilities: files, editing, code search, shell/terminal, skills, subagents, web search/fetch, browser automation, Context7, Exa, Firecrawl, Linear, Notion, Railway, Descript and RepoWise. Connected apps use native execute Code Mode and its search function. Search here before claiming a capability is unavailable. Plain chat needs no tools. Loaded tools become callable next model step for this user turn; discovery does not execute them or grant permission.',
      input: { type: 'object', properties: {
        query: { type: 'string', description: 'Capability or skill needed.' },
        names: { type: 'array', items: { type: 'string' }, description: 'Optional exact native tool names.' },
        limit: { type: 'integer', minimum: 1, maximum: 5 }
      }, required: ['query'], additionalProperties: false },
      options: { codemode: false },
      async execute(input, context) {
        const current = state(context.sessionID);
        const limit = Math.max(1, Math.min(5, Number.isFinite(input.limit) ? Math.floor(input.limit) : 3));
        const requested = Array.isArray(input.names) ? input.names.filter(name => typeof name === 'string') : [];
        const candidates = Object.entries(current.tools).filter(([name]) => name !== finder)
          .map(([name, tool]) => ({ name, description: tool.description ?? '' }));
        const exact = candidates.filter(tool => requested.includes(tool.name));
        let loaded = exact.length ? exact.slice(0, limit) : rank(candidates, input.query, limit);
        const terms = words(input.query);
        const servers = current.servers.filter(name => terms.includes(name) || terms.includes(name.replace(/-/g, '')));
        const wantsSkills = terms.some(term => ['skill', 'skills'].includes(term)) ||
          current.skills.some(skill => skill.name.toLowerCase() === String(input.query).trim().toLowerCase());
        const skills = wantsSkills ? rank(current.skills, input.query, limit) : [];
        const add = name => {
          const tool = candidates.find(tool => tool.name === name);
          if (tool && !loaded.some(item => item.name === name)) loaded.push(tool);
        };
        if (servers.length || terms.some(term => ['mcp', 'app', 'apps', 'codemode'].includes(term))) add('execute');
        if (skills.length || terms.includes('skill') || terms.includes('skills')) add('skill');
        for (const tool of loaded) current.selected.add(tool.name);
        for (const server of servers) current.selectedServers.add(server);
        return { content: JSON.stringify({
          loaded: loaded.map(tool => ({ name: tool.name, description: tool.description.slice(0, 240) })),
          skills, servers,
          unavailableNames: requested.filter(name => !current.tools[name]),
          message: 'Use loaded native tools on the next step. Skills must be loaded with skill before applying them. For connected apps use execute with native search to discover exact paths and signatures. Original approvals still apply.'
        }) };
      }
    }));
    await ctx.session.hook('prompt', event => {
      const current = state(event.sessionID);
      current.selected.clear();
      current.selectedServers.clear();
    });
    await ctx.session.hook('context', event => {
      const current = state(event.sessionID);
      current.tools = { ...event.tools };
      const skills = [];
      const servers = new Set();
      for (const part of event.system) {
        if (typeof part.text !== 'string') continue;
        let text = part.text;
        text = text.replace(/<available_skills>[\s\S]*?<\/available_skills>/g, block => {
          for (const match of block.matchAll(/<skill>([\s\S]*?)<\/skill>/g)) {
            const field = name => match[1].match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`))?.[1] ?? '';
            skills.push({ name: field('id') || field('name'), description: field('description') });
          }
          return skillNotice;
        });
        const hasExecute = current.selected.has('execute') && event.tools.execute;
        text = text.replace(/<mcp_instructions>[\s\S]*?<\/mcp_instructions>/g, block => {
          for (const match of block.matchAll(/<server name="([^"]+)"/g)) servers.add(match[1]);
          const selected = [...block.matchAll(/<server name="([^"]+)"[\s\S]*?<\/server>/g)]
            .filter(match => hasExecute && current.selectedServers.has(match[1])).map(match => match[0]);
          return '<mcp_instructions>Before using a connected server, call find_tools with its name to load its instructions.\n' + selected.join('\n') + '\n</mcp_instructions>';
        });
        // Only the native catalog section is deferred. Preserve all subsequent
        // MCP, environment, repository and global instructions byte for byte.
        if (!hasExecute) text = text.replace(/# Code Mode\n[\s\S]*?(?=\n# [^\n]|\n<[^>]+>|$)/g,
          '# Tool discovery\nUse find_tools to load native tools and Code Mode when needed.\n\n');
        part.text = text;
      }
      current.skills = skills;
      current.servers = [...servers];
      for (const name of Object.keys(event.tools)) {
        if (name !== finder && !current.selected.has(name)) delete event.tools[name];
      }
    });
  }
};
