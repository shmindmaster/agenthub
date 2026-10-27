// AgentHub peer guard for unattended Cline runs.
// Active only when the launcher sets AGENTHUB_PEER_GUARD=1, so interactive
// TUI/Desktop sessions keep their normal approvals. --auto-approve true
// approves every tool call; this hook is the deny list that replaces the
// approvals an attended session would have asked for. It mirrors the
// OpenCode `peer` agent (docs/plans/active/opencode-peer-orchestration.md).
// Shell matching is literal text, so briefs repeat the rules.

const active = () => process.env.AGENTHUB_PEER_GUARD === "1";

const commandRules = [
  [/\bgit((\s+-[cC]\s+\S+)|(\s+--?[\w-]+(=\S+)?))*\s+push\b/i, "git push is reserved for the orchestrator after review"],
  [/\bgit\b[^\n;|&]*\breset\b[^\n;|&]*--hard\b/i, "git reset --hard discards work"],
  [/\bgit\b[^\n;|&]*\bclean\b[^\n;|&]*\s-[a-z]*f/i, "git clean -f deletes untracked work"],
  [/\bgit\b[^\n;|&]*\bbranch\b[^\n;|&]*\s-D\b/, "git branch -D deletes unmerged branches"],
  [/\bgit\b[^\n;|&]*\b(filter-branch|filter-repo)\b|\bgit\b[^\n;|&]*\bupdate-ref\s+-d\b/i, "history and ref rewriting is not allowed"],
  [/\bgit\b[^\n;|&]*\bworktree\s+(remove|prune)\b/i, "worktree removal belongs to the orchestrator"],
  [/\bgh\s+(pr|issue|release|repo|gist|label|workflow|run)\s+(create|merge|close|edit|comment|delete|review|reopen|ready|lock|unlock|archive|rename|fork|sync|upload|transfer|enable|disable|cancel|rerun)\b/i, "outward GitHub actions need owner approval"],
  [/\bgh\s+api\b[^\n;|&]*(\s-X\s*(POST|PATCH|PUT|DELETE)|--method\s*(POST|PATCH|PUT|DELETE)|\s-[fF]\s)/i, "mutating gh api calls need owner approval"],
  [/\bgh\s+(auth|secret|variable|ssh-key|gpg-key)\b/i, "GitHub credentials and secrets are off limits"],
  [/\b(npm|pnpm|yarn|bun)\s+publish\b|\b(twine|cargo)\s+(upload|publish)\b/i, "package publishing needs owner approval"],
  [/(^|[\s;&|(])(railway|az|doctl|vercel|flyctl|fly|aws|gcloud|terraform|pulumi|kubectl|helm)(\.exe|\.cmd)?\s/i, "cloud and infrastructure CLIs need owner approval"],
  [/\bschtasks(\.exe)?\s+\/create\b|\b(Register|New)-ScheduledTask\b|\bNew-Service\b|\bsc(\.exe)?\s+create\b|CurrentVersion\\Run\b|Start Menu\\Programs\\Startup/i, "scheduled tasks, services and Run keys are prohibited"],
  [/\bcline\s+(auth|schedule|connect|hub|doctor|update|plugin|mcp|config)\b|\bopencode\s+auth\b|\bcodex\s+login\b/i, "agent host administration is reserved for the orchestrator"],
  [/\bgh\s+auth\s+token\b|\bprintenv\b|\b(Get-ChildItem|gci|dir|ls)\s+env:|\[Environment\]::GetEnvironmentVariables/i, "environment and credential dumps are prohibited"],
  [/\b(format|diskpart|mkfs)\b(\.com|\.exe)?\s|\bStop-Computer\b|\bRestart-Computer\b|\bshutdown(\.exe)?\s/i, "disk and power operations are prohibited"],
  [/\brm\s+-[a-z]*r[a-z]*f?\s+(\/|~|\$HOME|[a-z]:[\\\/]{1,2}?)(\s|$)/i, "recursive delete of a root or home directory"],
  [/\bRemove-Item\b[^\n;|&]*-Recurse[^\n;|&]*\s['"]?([a-z]:\\{1,2}?|\$env:USERPROFILE|~)['"]?(\s|$)/i, "recursive delete of a root or home directory"],
  [/\b(Set-ExecutionPolicy|Set-MpPreference|netsh\s+advfirewall|bcdedit|reg(\.exe)?\s+(add|delete)\s+HKLM)\b/i, "system and security settings are off limits"],
];

const secretPath = /(^|[\\\/]{1,2})(\.env(?!\.(example|sample|template)$)(\.[^\\\/]*)?|secrets\.json|providers\.json|auth\.json|credentials(\.json)?|[^\\\/]*\.pem|id_(rsa|ed25519)[^\\\/]*)$/i;
const protectedWrite = /^d:[\\\/]{1,2}local-ai(?![\\\/]{1,2}cache[\\\/]{1,2}temp)([\\\/]{1,2}|$)|[\\\/]{1,2}\.cline[\\\/]{1,2}data[\\\/]{1,2}settings|[\\\/]{1,2}\.codex[\\\/]{1,2}auth/i;

const commandText = (input) => {
  const list = Array.isArray(input?.commands) ? input.commands : [input?.command ?? input?.commands];
  return list.filter((c) => c != null).map((c) => (typeof c === "string" ? c : c.command ?? JSON.stringify(c)));
};

const pathsIn = (input) => {
  const found = [];
  const walk = (v, key) => {
    if (typeof v === "string") {
      if (/path|file/i.test(key ?? "")) found.push(v);
      for (const m of v.matchAll(/\*\*\* (?:Add|Update|Delete) File: (.+)/g)) found.push(m[1].trim());
    } else if (Array.isArray(v)) v.forEach((x) => walk(x, key));
    else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) walk(x, k);
  };
  walk(input);
  return found;
};

const deny = (reason) => ({ skip: true, reason: `Blocked by AgentHub peer guard: ${reason}. Do not retry it another way; record the step in your report for the orchestrator.` });

export default {
  name: "agenthub-peer-guard",
  manifest: { capabilities: ["hooks"] },
  setup() {},
  hooks: {
    beforeTool(context) {
      if (!active()) return undefined;
      const name = context?.tool?.name ?? context?.toolCall?.name ?? context?.toolCall?.toolName ?? "";
      const input = context?.input ?? context?.toolCall?.input ?? {};
      if (name === "run_commands" || name === "execute_command") {
        for (const cmd of commandText(input)) {
          for (const [rule, reason] of commandRules) if (rule.test(cmd)) return deny(reason);
          if (secretPath.test(cmd.replace(/["']/g, " ").trim().split(/\s+/).pop() ?? "")) return deny("reading credential files is prohibited");
        }
      }
      if (name === "read_files" || name === "read_file") {
        if (pathsIn(input).some((p) => secretPath.test(p))) return deny("reading credential files is prohibited");
      }
      if (name === "editor" || name === "apply_patch" || name === "write_to_file" || name === "replace_in_file") {
        const paths = pathsIn(input);
        if (paths.some((p) => protectedWrite.test(p))) return deny("D:\\Local-AI is a deployed runtime; patch its source repository instead");
        if (paths.some((p) => secretPath.test(p))) return deny("credential files are off limits");
      }
      return undefined;
    },
  },
};




