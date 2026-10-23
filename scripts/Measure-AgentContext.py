"""Read-only fleet skill inventory. Reports metadata, never prompt/config values.

Cached plugin skills are inventory, not evidence of activation or model loading.
Root aliases are resolved before counting physical copies. No host is started.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path
import tomllib

SKIP = {'node_modules', '.git', 'sessions', 'projects', 'logs', 'memories', 'trash', '.trash', 'staging'}
CONFIG_ROOTS = ['.claude', '.codex', '.config/opencode', '.gemini', '.gemini/antigravity-cli',
                'AppData/Roaming/Antigravity', '.copilot', '.grok', '.warp', 'AppData/Roaming/warp',
                '.cline', 'AppData/Roaming/Cursor', '.cursor', '.config/amp', '.devin',
                'AppData/Roaming/devin', '.factory', 'AppData/Roaming/Code - Insiders', '.codeium/windsurf']
CONFIG_FILES = ['settings.json', 'config.json', 'config.toml', 'mcp.json', 'mcp-config.json',
                'mcp_config.json', '.mcp.json', 'cli-config.json', 'opencode.json',
                'User/settings.json', 'User/mcp.json', 'data/settings/globalState.json', 'data/settings/global-settings.json',
                'data/settings/cline_mcp_settings.json']
ADDITIONAL_LOCATIONS = {
    'claude': ['AppData/Roaming/Claude Code', 'AppData/Local/Claude', 'AppData/Local/Claude-Data', 'AppData/Local/Claude-3p'],
    'codex': ['AppData/Local/Codex', 'AppData/Local/OpenAI', 'AppData/Local/Programs/OpenAI', '.codex_work', '.codex-tools', 'codex-github-marketplace'],
    'opencode': ['AppData/Roaming/ai.opencode.desktop', 'AppData/Local/Programs/@opencodedesktop', '.local/share/opencode'],
    'gemini': ['AppData/Local/agy'],
    'antigravity': ['AppData/Local/antigravity', 'AppData/Local/Programs/antigravity'],
    'copilot': ['AppData/Local/copilot'],
    'grok': ['AppData/Local/grok', 'AppData/Roaming/Grok Bot', 'AppData/Local/Programs/Grok Bot', '.grokbot'],
    'warp': ['AppData/Local/warp', 'AppData/Local/Programs/Warp'],
    'cline': ['AppData/Local/Cline', 'AppData/Local/bot.cline.app'],
    'cursor': ['AppData/Local/Cursor', 'AppData/Local/cursor-agent', 'AppData/Local/Programs/cursor'],
    'amp': ['.amp', 'AppData/Local/amp'],
    'devin': ['AppData/Local/devin', 'AppData/Local/Programs/Devin', '.config/devin', '.devin-shared'],
    'factory': ['AppData/Roaming/Factory', 'AppData/Local/Factory'],
    'vscode-insiders': ['.vscode-insiders', '.vscode-insiders-shared'],
}
SKILL_LINK_LOCATIONS = ['.claude/skills', '.cline/skills', '.grok/skills', '.cursor/skills',
                        '.gemini/config/skills', 'AppData/Roaming/devin/skills',
                        '.codex/skills', '.factory/skills', '.config/devin/skills', '.cursor/plugins/local']

def location_metadata(path):
    """Observe a location without traversing caches or shared link targets."""
    linked = path.is_symlink() or path.is_junction()
    return {'path':str(path), 'exists':path.exists(), 'linked':linked,
            'resolved':str(path.resolve()) if path.exists() or linked else None}

def storage_metadata(user):
    locations = [{'host':host, **location_metadata(user/relative)}
                 for host, relatives in ADDITIONAL_LOCATIONS.items() for relative in relatives]
    if os.name == 'nt':
        locations += [{'host':'claude', **location_metadata(Path(os.environ.get('PROGRAMDATA', 'C:/ProgramData'))/name)}
                      for name in ('Claude', 'ClaudeCode')]
    links=[]
    for relative in SKILL_LINK_LOCATIONS:
        path=user/relative
        row=location_metadata(path)
        row['childLinks']=[]
        if path.is_dir() and not row['linked']:
            row['childLinks']=[location_metadata(child) for child in sorted(path.iterdir())
                               if child.is_symlink() or child.is_junction()]
        links.append(row)
    return {'sharedLibrary':location_metadata(user/'.agents/skills'),
            'agentHubRuntime':location_metadata(user/'AppData/Local/AgentHub'),
            'additionalLocations':locations, 'skillLinks':links,
            'scope':'Location and immediate link metadata only; existence does not establish active configuration or context loading.'}

def config_metadata(user):
    """Whitelist output fields. Never serialize config values, env or auth."""
    roots=[]
    for relative in CONFIG_ROOTS:
        root=user/relative
        row={'path':str(root),'exists':root.is_dir(),'configs':[]}
        for filename in CONFIG_FILES:
            path=root/filename
            if not path.is_file():
                continue
            item={'path':str(path),'bytes':path.stat().st_size}
            try:
                document=tomllib.loads(path.read_text(encoding='utf-8-sig')) if path.suffix=='.toml' else read_json(path)
                if isinstance(document,dict):
                    servers=document.get('mcpServers',document.get('mcp_servers',document.get('mcp',document.get('amp.mcpServers', document.get('servers', {})))))
                    if isinstance(servers,dict):
                        item['mcp']=[{'name':name,'explicitlyDisabled':settings.get('disabled') is True or settings.get('enabled') is False}
                                     for name,settings in servers.items() if isinstance(settings,dict)]
                    item['contextSettingKeys']=[name for name in document if any(term in name.lower() for term in ('toolsearch','tool_search','discovery','codemode','context','skill'))]
                item['parsed']=True
            except (ValueError,OSError):
                item['parsed']=False
                item['reason']='unsupported-or-invalid-syntax'  # JSONC is not assumed invalid.
            row['configs'].append(item)
        roots.append(row)
    return roots

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def inventory(repository, user):
    registry = read_json(repository/'registry/agents.json')
    agents = registry['activeAgents'] + registry.get('inactiveAgents', [])
    replacements = {'{userHome}': str(user), '{roamingConfig}': str(user/'AppData/Roaming'), '{localAppData}': str(user/'AppData/Local')}
    roots = defaultdict(list)
    instructions = []
    errors = []
    for agent in agents:
        for key, value in agent.get('nativePaths', {}).items():
            if not isinstance(value, str) or key not in {'skillsDir','sharedSkillsDir','cliSkillsDir','pluginsDir','cliPluginsDir','extensionsDir','instructions','rulesDir'}:
                continue
            for token, replacement in replacements.items():
                value=value.replace(token, replacement)
            if '{' in value:
                errors.append({'host':agent['id'],'field':key,'reason':'unresolved-path-binding'})
                continue
            path=Path(value)
            if key=='instructions':
                instructions.append({'host':agent['id'],'path':str(path),'exists':path.is_file(),'bytes':path.stat().st_size if path.is_file() else None})
            else:
                roots[str(path.resolve())].append({'host':agent['id'],'field':key,'path':str(path)})
    ownership={}
    canonical=[]
    for registry_path in [repository/'registry/capabilities.json',repository/'overlays/personal/capabilities.json']:
        if not registry_path.is_file():
            continue
        for capability in read_json(registry_path)['capabilities']:
            for name in capability.get('managedSkillNames',[]):
                ownership[name]=capability['id']
            package=repository/capability['canonicalSource']
            if package.is_dir():
                for skill in package.rglob('SKILL.md'):
                    canonical.append({'owner':capability['id'],'path':str(skill),'bytes':skill.stat().st_size})
    skills=[]
    scopes=[]
    for resolved, aliases in sorted(roots.items()):
        root=Path(resolved)
        scope={'path':resolved,'aliases':aliases,'exists':root.is_dir(),'files':0}
        if root.is_dir():
            def onerror(error):
                errors.append({'path':str(error.filename),'reason':type(error).__name__})
            for directory, dirs, files in os.walk(root,followlinks=False,onerror=onerror):
                dirs[:]=[d for d in dirs if d not in SKIP and not Path(directory,d).is_symlink() and not Path(directory,d).is_junction()]
                if 'SKILL.md' not in files:
                    continue
                path=Path(directory,'SKILL.md')
                content=path.read_bytes()
                name=path.parent.name
                scope['files']+=1
                skills.append({'name':name,'path':str(path),'root':resolved,'bytes':len(content),'sha256':hashlib.sha256(content.replace(b'\r\n',b'\n')).hexdigest(),'owner':ownership.get(name),'kind':'plugin-cache-or-package' if any('plugin' in a['field'].lower() or 'extension' in a['field'].lower() for a in aliases) else 'loose-discovery'})
        scopes.append(scope)
    groups=defaultdict(list)
    for skill in skills:
        groups[skill['sha256']].append(skill['path'])
    enabled={}
    config_errors=[]
    for host,path in [('claude',user/'.claude/settings.json'),('codex',user/'.codex/config.toml')]:
        if not path.is_file():
            enabled[host]=None
            continue
        try:
            document=tomllib.loads(path.read_text(encoding='utf-8-sig')) if path.suffix=='.toml' else read_json(path)
            entries=document.get('plugins',{}) if host=='codex' else document.get('enabledPlugins',{})
            enabled[host]={key:(value.get('enabled') if isinstance(value,dict) else value) for key,value in entries.items()}
        except (ValueError,OSError) as exc:
            config_errors.append({'host':host,'reason':type(exc).__name__})
    return {'schemaVersion':1,'scope':'Registry-declared global skill/plugin/rule roots, instructions and explicitly listed host config roots. Plugin caches are not active-tool counts; repository-local skills are outside this enumeration.','configRoots':config_metadata(user),'roots':scopes,'skills':skills,'canonical':canonical,'instructions':instructions,'enabledPlugins':enabled,'duplicateContent':[paths for paths in groups.values() if len(paths)>1],'errors':errors+config_errors}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository-root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--user-profile',type=Path,default=Path.home())
    parser.add_argument('--output',type=Path,required=True,help='Private runtime report destination; contains paths, not document/config contents.')
    args=parser.parse_args()
    result=inventory(args.repository_root,args.user_profile)
    result['storage']=storage_metadata(args.user_profile)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'report':str(args.output),'root_count':len(result['roots']),'skill_files':len(result['skills']),'canonical_entries':len(result['canonical']),'duplicate_groups':len(result['duplicateContent']),'errors':result['errors']}))
