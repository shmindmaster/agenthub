import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { packageRoot } from './contract.mjs';
import { normalizeChannel, normalizeMessage, normalizeUser } from './normalize.mjs';

const READ_METHODS = new Set([
  'auth.test',
  'bots.info',
  'bookmarks.list',
  'chat.getPermalink',
  'conversations.history',
  'conversations.info',
  'conversations.list',
  'conversations.members',
  'conversations.replies',
  'emoji.list',
  'files.info',
  'files.list',
  'pins.list',
  'reactions.get',
  'search.files',
  'search.messages',
  'team.info',
  'users.info',
  'users.list',
  'users.lookupByEmail',
  'users.profile.get',
]);

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function permalink(workspace, channelId, ts) {
  const domain = workspace.domain || 'fixture';
  return `https://${domain}.slack.com/archives/${channelId}/p${String(ts).replace('.', '')}`;
}

function nextTs(workspace) {
  workspace._clock = (workspace._clock || 1789052000) + 1;
  return `${workspace._clock}.000001`;
}

export function loadFixtureWorkspace() {
  const path = join(packageRoot(), 'fixtures', 'workspace.json');
  return JSON.parse(readFileSync(path, 'utf8'));
}

export function createFixtureBackend(initial = loadFixtureWorkspace()) {
  const state = clone(initial);
  const workspaceId = state.workspace_id;

  function channel(channelId) {
    const found = state.channels.find((c) => c.id === channelId);
    if (!found) throw new Error(`channel not found: ${channelId}`);
    return found;
  }

  function messagesOf(channelId) {
    if (!state.messages[channelId]) state.messages[channelId] = [];
    return state.messages[channelId];
  }

  function findMessage(channelId, ts) {
    const msg = messagesOf(channelId).find((m) => m.ts === ts);
    if (!msg) throw new Error(`message not found: ${channelId} ${ts}`);
    return msg;
  }

  function tokenFor(actorMode) {
    if (actorMode === 'agent_bot') {
      const bot = state.identity.bot;
      if (!bot) throw new Error('actor_mode=agent_bot is not configured');
      return bot;
    }
    return state.identity.user;
  }

  return {
    mode: 'fixture',
    async whoami(actorMode = 'user') {
      const ident = tokenFor(actorMode);
      return {
        actor_mode: actorMode,
        user_id: ident.user_id || null,
        bot_id: ident.bot_id || null,
        team_id: workspaceId,
        team_name: state.team_name,
        user_name: ident.user_name || null,
        raw: ident,
      };
    },
    async search({ query, count = 20 }) {
      const q = String(query).toLowerCase();
      const hits = [];
      for (const [channelId, list] of Object.entries(state.messages)) {
        for (const raw of list) {
          const hay = `${raw.text || ''} ${JSON.stringify(raw.blocks || [])}`.toLowerCase();
          if (hay.includes(q)) {
            hits.push(normalizeMessage(raw, {
              workspace_id: workspaceId,
              channel_id: channelId,
              permalink: permalink(state, channelId, raw.ts),
            }));
          }
        }
      }
      return { query, matches: hits.slice(0, count), pagination: { count, page: 1 } };
    },
    async channels({ cursor, limit = 100, exclude_archived = true } = {}) {
      let list = state.channels.map((raw) => normalizeChannel(raw, { workspace_id: workspaceId }));
      if (exclude_archived) list = list.filter((c) => !c.is_archived);
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = list.slice(start, start + limit);
      const next = start + limit < list.length ? String(start + limit) : null;
      return { channels: page, next_cursor: next };
    },
    async users({ query, user_id, email, cursor, limit = 100 } = {}) {
      let list = state.users.map((raw) => normalizeUser(raw, { workspace_id: workspaceId }));
      if (user_id) list = list.filter((u) => u.user_id === user_id);
      if (email) list = list.filter((u) => u.email === email);
      if (query) {
        const q = String(query).toLowerCase();
        list = list.filter((u) => `${u.display_name} ${u.real_name} ${u.user_id}`.toLowerCase().includes(q));
      }
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = list.slice(start, start + limit);
      const next = start + limit < list.length ? String(start + limit) : null;
      return { users: page, next_cursor: next };
    },
    async messages({ channel_id, oldest, latest, limit = 100, cursor, inclusive = false } = {}) {
      let list = [...messagesOf(channel_id)];
      if (oldest) list = list.filter((m) => (inclusive ? m.ts >= oldest : m.ts > oldest));
      if (latest) list = list.filter((m) => (inclusive ? m.ts <= latest : m.ts < latest));
      list.sort((a, b) => (a.ts < b.ts ? 1 : -1));
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = list.slice(start, start + limit).map((raw) => normalizeMessage(raw, {
        workspace_id: workspaceId,
        channel_id,
        permalink: permalink(state, channel_id, raw.ts),
      }));
      const next = start + limit < list.length ? String(start + limit) : null;
      return { messages: page, next_cursor: next };
    },
    async thread({ channel_id, ts, limit = 200, cursor } = {}) {
      const parent = findMessage(channel_id, ts);
      const replies = messagesOf(channel_id)
        .filter((m) => m.ts === ts || m.thread_ts === ts)
        .sort((a, b) => (a.ts < b.ts ? -1 : 1));
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = replies.slice(start, start + limit).map((raw) => normalizeMessage(raw, {
        workspace_id: workspaceId,
        channel_id,
        permalink: permalink(state, channel_id, raw.ts),
      }));
      const next = start + limit < replies.length ? String(start + limit) : null;
      return {
        parent: normalizeMessage(parent, {
          workspace_id: workspaceId,
          channel_id,
          permalink: permalink(state, channel_id, parent.ts),
        }),
        messages: page,
        next_cursor: next,
      };
    },
    async post({ channel_id, text, blocks, attachments, metadata, thread_ts, actor_mode = 'user' }) {
      channel(channel_id);
      const ident = tokenFor(actor_mode);
      const ts = nextTs(state);
      const raw = {
        type: 'message',
        user: ident.user_id || null,
        bot_id: ident.bot_id || null,
        app_id: ident.app_id || null,
        text: text || '',
        ts,
        thread_ts: thread_ts || undefined,
        team: workspaceId,
        blocks: blocks || [],
        attachments: attachments || [],
        files: [],
        reactions: [],
        metadata: metadata || {},
      };
      messagesOf(channel_id).push(raw);
      return normalizeMessage(raw, {
        workspace_id: workspaceId,
        channel_id,
        permalink: permalink(state, channel_id, ts),
      });
    },
    async update({ channel_id, ts, text, blocks, actor_mode = 'user' }) {
      const msg = findMessage(channel_id, ts);
      tokenFor(actor_mode);
      msg.text = text;
      if (blocks) msg.blocks = blocks;
      msg.edited = { user: state.identity.user.user_id, ts: nextTs(state) };
      return normalizeMessage(msg, {
        workspace_id: workspaceId,
        channel_id,
        permalink: permalink(state, channel_id, ts),
      });
    },
    async delete({ channel_id, ts }) {
      const list = messagesOf(channel_id);
      const idx = list.findIndex((m) => m.ts === ts);
      if (idx < 0) throw new Error(`message not found: ${channel_id} ${ts}`);
      const removed = list.splice(idx, 1)[0];
      return { ok: true, channel_id, ts, raw: removed };
    },
    async react({ channel_id, ts, name, actor_mode = 'user' }) {
      const msg = findMessage(channel_id, ts);
      const ident = tokenFor(actor_mode);
      if (!Array.isArray(msg.reactions)) msg.reactions = [];
      let entry = msg.reactions.find((r) => r.name === name);
      if (!entry) {
        entry = { name, users: [], count: 0 };
        msg.reactions.push(entry);
      }
      if (!entry.users.includes(ident.user_id)) {
        entry.users.push(ident.user_id);
        entry.count = entry.users.length;
      }
      return normalizeMessage(msg, {
        workspace_id: workspaceId,
        channel_id,
        permalink: permalink(state, channel_id, ts),
      });
    },
    async unreact({ channel_id, ts, name, actor_mode = 'user' }) {
      const msg = findMessage(channel_id, ts);
      const ident = tokenFor(actor_mode);
      const entry = (msg.reactions || []).find((r) => r.name === name);
      if (entry) {
        entry.users = entry.users.filter((id) => id !== ident.user_id);
        entry.count = entry.users.length;
        if (entry.count === 0) {
          msg.reactions = msg.reactions.filter((r) => r.name !== name);
        }
      }
      return normalizeMessage(msg, {
        workspace_id: workspaceId,
        channel_id,
        permalink: permalink(state, channel_id, ts),
      });
    },
    async fileGet({ file_id }) {
      const file = (state.files || []).find((f) => f.id === file_id);
      if (!file) throw new Error(`file not found: ${file_id}`);
      return { file_id: file.id, name: file.name, mimetype: file.mimetype, url_private: file.url_private || null, raw: file };
    },
    async fileUpload({ filename, content_base64, channel_id, thread_ts, title, initial_comment }) {
      const id = `F${String((state.files || []).length + 1).padStart(6, '0')}`;
      const file = {
        id,
        name: filename,
        title: title || filename,
        mimetype: 'application/octet-stream',
        size: Buffer.from(content_base64, 'base64').length,
        channels: channel_id ? [channel_id] : [],
        thread_ts: thread_ts || null,
        initial_comment: initial_comment || null,
      };
      if (!state.files) state.files = [];
      state.files.push(file);
      if (channel_id && initial_comment) {
        await this.post({ channel_id, thread_ts, text: initial_comment });
      }
      return { file_id: id, raw: file };
    },
    async permalink({ channel_id, ts }) {
      findMessage(channel_id, ts);
      return { channel_id, ts, permalink: permalink(state, channel_id, ts) };
    },
    async channelInfo({ channel_id }) {
      return normalizeChannel(channel(channel_id), { workspace_id: workspaceId });
    },
    async userInfo({ user_id }) {
      const raw = state.users.find((u) => u.id === user_id);
      if (!raw) throw new Error(`user not found: ${user_id}`);
      return normalizeUser(raw, { workspace_id: workspaceId });
    },
    async pin({ channel_id, ts }) {
      findMessage(channel_id, ts);
      if (!state.pins[channel_id]) state.pins[channel_id] = [];
      if (!state.pins[channel_id].includes(ts)) state.pins[channel_id].push(ts);
      return { ok: true, channel_id, ts };
    },
    async unpin({ channel_id, ts }) {
      if (state.pins[channel_id]) {
        state.pins[channel_id] = state.pins[channel_id].filter((item) => item !== ts);
      }
      return { ok: true, channel_id, ts };
    },
    async bookmarks({ channel_id, action, bookmark_id, title, link }) {
      if (!state.bookmarks[channel_id]) state.bookmarks[channel_id] = [];
      const list = state.bookmarks[channel_id];
      if (action === 'list') return { bookmarks: list, raw: list };
      if (action === 'add') {
        const id = bookmark_id || `Bk${list.length + 1}`;
        const item = { id, title, link, channel_id };
        list.push(item);
        return { bookmark: item, raw: item };
      }
      if (action === 'remove') {
        state.bookmarks[channel_id] = list.filter((b) => b.id !== bookmark_id);
        return { ok: true, bookmark_id };
      }
      throw new Error(`unknown bookmarks action: ${action}`);
    },
    async canvasGet({ canvas_id }) {
      const canvas = (state.canvases || []).find((c) => c.id === canvas_id);
      if (!canvas) throw new Error(`canvas not found: ${canvas_id}`);
      return { canvas_id: canvas.id, title: canvas.title, document: canvas.document, raw: canvas };
    },
    async listItems({ list_id, cursor, limit = 100 }) {
      const list = (state.lists || []).find((item) => item.id === list_id);
      if (!list) throw new Error(`list not found: ${list_id}`);
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = (list.items || []).slice(start, start + limit);
      const next = start + limit < (list.items || []).length ? String(start + limit) : null;
      return { list_id, items: page, next_cursor: next, raw: list };
    },
    async apiRead({ method, params = {} }) {
      if (!READ_METHODS.has(method)) {
        throw new Error(`slack_api_read refuses '${method}'; use slack_api_write with approval for writes`);
      }
      return { method, params, ok: true, fixture: true, raw: { method, params } };
    },
    async apiWrite({ method, params = {}, approved }) {
      if (!approved) throw new Error('slack_api_write requires approved=true');
      if (process.env.SLACK_BRIDGE_ALLOW_API_WRITE !== 'true') {
        throw new Error('slack_api_write requires SLACK_BRIDGE_ALLOW_API_WRITE=true');
      }
      if (READ_METHODS.has(method)) {
        throw new Error(`'${method}' is a read method; use slack_api_read`);
      }
      return { method, params, ok: true, fixture: true, raw: { method, params, write: true } };
    },
  };
}

async function slackApi(token, method, params = {}) {
  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    body.set(key, typeof value === 'string' ? value : JSON.stringify(value));
  }
  const response = await fetch(`https://slack.com/api/${method}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  const json = await response.json();
  if (!json.ok) {
    throw new Error(`Slack API ${method} failed: ${json.error || response.status}`);
  }
  return json;
}

export function createWebApiBackend() {
  function token(actorMode = 'user') {
    if (actorMode === 'agent_bot') {
      const bot = process.env.SLACK_BOT_TOKEN;
      if (!bot) throw new Error('actor_mode=agent_bot requires SLACK_BOT_TOKEN');
      return bot;
    }
    const user = process.env.SLACK_USER_TOKEN;
    if (!user) throw new Error('actor_mode=user requires SLACK_USER_TOKEN');
    return user;
  }

  return {
    mode: 'webapi',
    async whoami(actorMode = 'user') {
      const raw = await slackApi(token(actorMode), 'auth.test');
      return {
        actor_mode: actorMode,
        user_id: raw.user_id || null,
        bot_id: raw.bot_id || null,
        team_id: raw.team_id || null,
        team_name: raw.team || null,
        user_name: raw.user || null,
        raw,
      };
    },
    async search(args) {
      const raw = await slackApi(token(), 'search.messages', {
        query: args.query,
        count: args.count,
        page: args.page,
        sort: args.sort,
      });
      const matches = ((raw.messages && raw.messages.matches) || []).map((item) =>
        normalizeMessage(item, { channel_id: item.channel && item.channel.id, permalink: item.permalink })
      );
      return { query: args.query, matches, pagination: raw.messages, raw };
    },
    async channels(args = {}) {
      const raw = await slackApi(token(), 'conversations.list', {
        types: args.types || 'public_channel,private_channel,mpim,im',
        limit: args.limit,
        cursor: args.cursor,
        exclude_archived: args.exclude_archived,
      });
      return {
        channels: (raw.channels || []).map((item) => normalizeChannel(item)),
        next_cursor: raw.response_metadata && raw.response_metadata.next_cursor || null,
        raw,
      };
    },
    async users(args = {}) {
      if (args.user_id) {
        const raw = await slackApi(token(), 'users.info', { user: args.user_id });
        return { users: [normalizeUser(raw.user)], next_cursor: null, raw };
      }
      if (args.email) {
        const raw = await slackApi(token(), 'users.lookupByEmail', { email: args.email });
        return { users: [normalizeUser(raw.user)], next_cursor: null, raw };
      }
      const raw = await slackApi(token(), 'users.list', { limit: args.limit, cursor: args.cursor });
      let users = (raw.members || []).map((item) => normalizeUser(item));
      if (args.query) {
        const q = String(args.query).toLowerCase();
        users = users.filter((u) => `${u.display_name} ${u.real_name} ${u.user_id}`.toLowerCase().includes(q));
      }
      return {
        users,
        next_cursor: raw.response_metadata && raw.response_metadata.next_cursor || null,
        raw,
      };
    },
    async messages(args) {
      const raw = await slackApi(token(), 'conversations.history', {
        channel: args.channel_id,
        oldest: args.oldest,
        latest: args.latest,
        limit: args.limit,
        cursor: args.cursor,
        inclusive: args.inclusive,
      });
      return {
        messages: (raw.messages || []).map((item) =>
          normalizeMessage(item, { channel_id: args.channel_id })
        ),
        next_cursor: raw.response_metadata && raw.response_metadata.next_cursor || null,
        raw,
      };
    },
    async thread(args) {
      const raw = await slackApi(token(), 'conversations.replies', {
        channel: args.channel_id,
        ts: args.ts,
        limit: args.limit,
        cursor: args.cursor,
      });
      const messages = (raw.messages || []).map((item) =>
        normalizeMessage(item, { channel_id: args.channel_id })
      );
      return {
        parent: messages[0] || null,
        messages,
        next_cursor: raw.response_metadata && raw.response_metadata.next_cursor || null,
        raw,
      };
    },
    async post(args) {
      const raw = await slackApi(token(args.actor_mode), 'chat.postMessage', {
        channel: args.channel_id,
        text: args.text,
        blocks: args.blocks ? JSON.stringify(args.blocks) : undefined,
        attachments: args.attachments ? JSON.stringify(args.attachments) : undefined,
        metadata: args.metadata ? JSON.stringify(args.metadata) : undefined,
        thread_ts: args.thread_ts,
      });
      return normalizeMessage(raw.message, { channel_id: args.channel_id });
    },
    async update(args) {
      const raw = await slackApi(token(args.actor_mode), 'chat.update', {
        channel: args.channel_id,
        ts: args.ts,
        text: args.text,
        blocks: args.blocks ? JSON.stringify(args.blocks) : undefined,
      });
      return normalizeMessage(raw.message || { ts: args.ts, text: args.text, user: null }, {
        channel_id: args.channel_id,
      });
    },
    async delete(args) {
      const raw = await slackApi(token(args.actor_mode), 'chat.delete', {
        channel: args.channel_id,
        ts: args.ts,
      });
      return { ok: true, channel_id: args.channel_id, ts: args.ts, raw };
    },
    async react(args) {
      const raw = await slackApi(token(args.actor_mode), 'reactions.add', {
        channel: args.channel_id,
        timestamp: args.ts,
        name: args.name,
      });
      return { ok: true, channel_id: args.channel_id, ts: args.ts, name: args.name, raw };
    },
    async unreact(args) {
      const raw = await slackApi(token(args.actor_mode), 'reactions.remove', {
        channel: args.channel_id,
        timestamp: args.ts,
        name: args.name,
      });
      return { ok: true, channel_id: args.channel_id, ts: args.ts, name: args.name, raw };
    },
    async fileGet(args) {
      const raw = await slackApi(token(), 'files.info', { file: args.file_id });
      return { file_id: raw.file.id, name: raw.file.name, mimetype: raw.file.mimetype, url_private: raw.file.url_private || null, raw };
    },
    async fileUpload(args) {
      throw new Error('live slack_file_upload is not enabled in this milestone; use fixture mode or an owner-authorized follow-up');
    },
    async permalink(args) {
      const raw = await slackApi(token(), 'chat.getPermalink', {
        channel: args.channel_id,
        message_ts: args.ts,
      });
      return { channel_id: args.channel_id, ts: args.ts, permalink: raw.permalink, raw };
    },
    async channelInfo(args) {
      const raw = await slackApi(token(), 'conversations.info', { channel: args.channel_id });
      return normalizeChannel(raw.channel);
    },
    async userInfo(args) {
      const raw = await slackApi(token(), 'users.info', { user: args.user_id });
      return normalizeUser(raw.user);
    },
    async pin(args) {
      const raw = await slackApi(token(args.actor_mode), 'pins.add', {
        channel: args.channel_id,
        timestamp: args.ts,
      });
      return { ok: true, channel_id: args.channel_id, ts: args.ts, raw };
    },
    async unpin(args) {
      const raw = await slackApi(token(args.actor_mode), 'pins.remove', {
        channel: args.channel_id,
        timestamp: args.ts,
      });
      return { ok: true, channel_id: args.channel_id, ts: args.ts, raw };
    },
    async bookmarks(args) {
      if (args.action === 'list') {
        const raw = await slackApi(token(), 'bookmarks.list', { channel_id: args.channel_id });
        return { bookmarks: raw.bookmarks || [], raw };
      }
      if (args.action === 'add') {
        const raw = await slackApi(token(args.actor_mode), 'bookmarks.add', {
          channel_id: args.channel_id,
          title: args.title,
          type: 'link',
          link: args.link,
        });
        return { bookmark: raw.bookmark, raw };
      }
      const raw = await slackApi(token(args.actor_mode), 'bookmarks.remove', {
        channel_id: args.channel_id,
        bookmark_id: args.bookmark_id,
      });
      return { ok: true, bookmark_id: args.bookmark_id, raw };
    },
    async canvasGet(args) {
      throw new Error(`live canvas read is not mapped for ${args.canvas_id} in this milestone; use slack_api_read once the owner grants canvases:read`);
    },
    async listItems(args) {
      throw new Error(`live list read is not mapped for ${args.list_id} in this milestone; use slack_api_read once the owner grants lists access`);
    },
    async apiRead({ method, params = {} }) {
      if (!READ_METHODS.has(method)) {
        throw new Error(`slack_api_read refuses '${method}'; use slack_api_write with approval for writes`);
      }
      const raw = await slackApi(token(), method, params);
      return { method, params, ok: true, raw };
    },
    async apiWrite({ method, params = {}, approved, actor_mode = 'user' }) {
      if (!approved) throw new Error('slack_api_write requires approved=true');
      if (process.env.SLACK_BRIDGE_ALLOW_API_WRITE !== 'true') {
        throw new Error('slack_api_write requires SLACK_BRIDGE_ALLOW_API_WRITE=true');
      }
      if (READ_METHODS.has(method)) {
        throw new Error(`'${method}' is a read method; use slack_api_read`);
      }
      const raw = await slackApi(token(actor_mode), method, params);
      return { method, params, ok: true, raw };
    },
  };
}

export function resolveBackend() {
  const mode = (process.env.SLACK_BRIDGE_MODE || '').toLowerCase();
  if (mode === 'fixture') return createFixtureBackend();
  if (process.env.SLACK_USER_TOKEN || process.env.SLACK_BOT_TOKEN) return createWebApiBackend();
  if (mode === 'webapi') {
    throw new Error('SLACK_BRIDGE_MODE=webapi requires SLACK_USER_TOKEN or SLACK_BOT_TOKEN');
  }
  return createFixtureBackend();
}

export { READ_METHODS };
