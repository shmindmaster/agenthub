function asString(value) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

export function normalizeAuthor(raw = {}) {
  return {
    user_id: asString(raw.user) || asString(raw.user_id),
    display_name: asString(raw.display_name) || asString(raw.username) || asString(raw.user_name),
    bot_id: asString(raw.bot_id),
    app_id: asString(raw.app_id),
  };
}

export function normalizeMessage(raw, extras = {}) {
  if (!raw || typeof raw !== 'object') {
    throw new Error('normalizeMessage requires a Slack message object');
  }
  const channelId = asString(extras.channel_id) || asString(raw.channel) || asString(raw.channel_id);
  const ts = asString(raw.ts);
  if (!channelId || !ts) {
    throw new Error('normalizeMessage requires channel_id and ts');
  }
  const workspaceId = asString(extras.workspace_id) || asString(raw.team) || asString(raw.team_id);
  return {
    workspace_id: workspaceId,
    channel_id: channelId,
    ts,
    thread_ts: asString(raw.thread_ts),
    author: normalizeAuthor(raw),
    text: typeof raw.text === 'string' ? raw.text : '',
    blocks: Array.isArray(raw.blocks) ? raw.blocks : [],
    attachments: Array.isArray(raw.attachments) ? raw.attachments : [],
    files: Array.isArray(raw.files) ? raw.files : [],
    reactions: Array.isArray(raw.reactions) ? raw.reactions : [],
    metadata: raw.metadata && typeof raw.metadata === 'object' ? raw.metadata : {},
    subtype: asString(raw.subtype),
    edited: raw.edited && typeof raw.edited === 'object' ? raw.edited : null,
    permalink: asString(extras.permalink) || asString(raw.permalink),
    raw,
  };
}

export function normalizeChannel(raw, extras = {}) {
  const id = asString(raw && raw.id);
  if (!id) throw new Error('normalizeChannel requires id');
  return {
    channel_id: id,
    workspace_id: asString(extras.workspace_id) || asString(raw.context_team_id) || asString(raw.shared_team_ids && raw.shared_team_ids[0]),
    name: asString(raw.name),
    is_private: Boolean(raw.is_private),
    is_im: Boolean(raw.is_im),
    is_mpim: Boolean(raw.is_mpim),
    is_archived: Boolean(raw.is_archived),
    topic: raw.topic && typeof raw.topic === 'object' ? raw.topic.value || null : asString(raw.topic),
    purpose: raw.purpose && typeof raw.purpose === 'object' ? raw.purpose.value || null : asString(raw.purpose),
    raw,
  };
}

export function normalizeUser(raw, extras = {}) {
  const id = asString(raw && raw.id);
  if (!id) throw new Error('normalizeUser requires id');
  const profile = raw.profile && typeof raw.profile === 'object' ? raw.profile : {};
  return {
    user_id: id,
    workspace_id: asString(extras.workspace_id) || asString(raw.team_id),
    display_name: asString(profile.display_name) || asString(raw.real_name) || asString(raw.name),
    real_name: asString(raw.real_name) || asString(profile.real_name),
    email: asString(profile.email),
    is_bot: Boolean(raw.is_bot),
    deleted: Boolean(raw.deleted),
    raw,
  };
}

export function assertIdsPreserved(canonical) {
  if (!canonical.channel_id || !canonical.ts) {
    throw new Error('canonical message dropped channel_id or ts');
  }
  if (canonical.raw && canonical.raw.user && canonical.author.user_id !== canonical.raw.user) {
    throw new Error('hydration replaced user_id with a name');
  }
}
