// Live events of the logged-in user's chats, from the websocket of the Wildix Stream service. Run through
// ../watch.sh, which gives the login token on stdin and the addresses in the environment. Prints one line per
// event: `<event> <json>`. The token is never printed; it goes only into the address of the websocket, as the
// service wants it.
import {readFileSync, writeFileSync} from 'node:fs';

// On macOS a piped stdout or stderr is asynchronous, and process.exit() right after a write cuts the output at
// the pipe buffer (64 KB): an agent reading through a pipe would get broken JSON. Blocking writes keep every byte
// written before an exit.
for (const s of [process.stdout, process.stderr]) s._handle?.setBlocking?.(true);

const out = (event, data) => process.stdout.write(`${event} ${JSON.stringify(data ?? {})}\n`);
const fail = (message, code = 1) => {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(code);
};

const wsUrl = process.env.CHATS_WS_URL;
const apiUrl = process.env.CHATS_API;
const me = process.env.CHATS_ME;
if (!wsUrl || !apiUrl || !me) fail('run this through watch.sh');
const token = readFileSync(0, 'utf8').trim();
if (!token) fail('no login token on stdin: run this through watch.sh', 2);

const GROUPS = {
  messages: ['message.new', 'message.updated', 'message.deleted'],
  reactions: ['reaction.new', 'reaction.updated', 'reaction.deleted'],
  reads: ['read.cursor.updated', 'read.receipt.updated'],
  members: ['member.added', 'member.updated', 'member.removed'],
  channels: [
    'channel.created', 'channel.updated', 'channel.truncated', 'channel.added', 'channel.removed', 'channel.hidden',
    'channel.visible', 'channel.muted', 'channel.unmuted', 'channel.pinned', 'channel.unpinned',
  ],
  typing: ['typing.start', 'typing.stop'],
};
const ALL = new Set(Object.values(GROUPS).flat());

const channels = new Set();
const senders = new Set();
const types = new Set();
let mine = false;
let raw = false;
let left = 0; // 0: no limit
let deadline = 0; // epoch ms, 0: none
let stateFile = '';
let reconnected = false;
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const v = () => argv[++i] ?? fail(`${a} needs a value`);
  if (a === '--channel') channels.add(v());
  else if (a === '--from') senders.add(v());
  else if (a === '--type') {
    const t = v();
    if (GROUPS[t]) GROUPS[t].forEach((x) => types.add(x));
    else if (ALL.has(t)) types.add(t);
    else fail(`unknown event type ${t}`);
  } else if (a === '--mine') mine = true;
  else if (a === '--raw') raw = true;
  else if (a === '--count') left = Number(v());
  else if (a === '--deadline') deadline = Number(v()) * 1000;
  else if (a === '--state') stateFile = v();
  else if (a === '--reconnected') reconnected = true;
  else fail(`unknown option ${a}`);
}

// Names of people, looked up once each through the API (the events carry user ids only).
const names = new Map();
async function nameOf(id) {
  if (!id) return undefined;
  if (names.has(id)) return names.get(id);
  let name;
  try {
    const res = await fetch(`${apiUrl}/users/query`, {
      method: 'POST',
      headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Accept: 'application/json'},
      body: JSON.stringify({query: {ids: [id]}}),
      signal: AbortSignal.timeout(10000),
    });
    if (res.ok) name = (await res.json())?.users?.[0]?.name;
  } catch {
    // a name is a nicety: the id is printed anyway
  }
  names.set(id, name);
  return name;
}
const person = async (id) => (id ? {id, name: await nameOf(id)} : undefined);

const drop = (o) => JSON.parse(JSON.stringify(o)); // removes the undefined fields
const unread = (counters) =>
  counters ? Object.values(counters).reduce((n, c) => n + (c?.unmutedUnreadMessageCount ?? 0), 0) : undefined;

function wanted(e) {
  if (types.size && !types.has(e.eventType)) return false;
  if (channels.size && !channels.has(e.channelId)) return false;
  // Who did it. A reaction event does not say who reacted (its message is someone else's work), so a reaction
  // has no author here: it is never taken for the user's own action, and --from leaves reactions out.
  const isReaction = e.eventType.startsWith('reaction.');
  const author = isReaction ? undefined : e.message?.userId ?? e.readerUserId ?? e.typingUserId;
  if (isReaction && senders.size) return false;
  if (senders.size && !senders.has(author)) return false;
  if (!mine) {
    if (e.eventType === 'read.cursor.updated') return false; // always the user's own reading
    if (author === me) return false;
  }
  return true;
}

async function view(e) {
  if (raw) return e;
  const m = e.message;
  const isReaction = e.eventType.startsWith('reaction.');
  return drop({
    channelId: e.channelId,
    channel: e.inboxChannel?.subject,
    channelType: e.inboxChannel?.channelType,
    messageId: e.messageId,
    seq: e.timelineSeq,
    from: isReaction ? undefined : await person(m?.userId),
    messageAuthor: isReaction ? await person(m?.userId) : undefined,
    text: m?.text,
    attachments: m?.attachments?.length ? m.attachments.map((f) => drop({name: f.name, mime: f.mime})) : undefined,
    mentions: m?.mentions?.length ? m.mentions : undefined,
    system: m?.system || undefined,
    reactions: isReaction ? m?.reactionCounts : undefined,
    reader: await person(e.readerUserId),
    readUpTo: e.lastReadVisibleSeq,
    member: e.member ? {...e.member, name: await nameOf(e.member.userId)} : undefined,
    typing: await person(e.typingUserId),
    unread: unread(e.sectionCounters),
  });
}

let ws;
let stopping = false;
let attempts = 0;
let ready = false;
let keepalive;
const tokenExp = (() => {
  try {
    return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()).exp * 1000;
  } catch {
    return 0;
  }
})();

function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  clearInterval(keepalive);
  out('END', {reason: code === 0 ? 'stopped' : 'error'});
  try {
    ws?.close(1000);
  } catch {
    // closing a socket that is gone
  }
  process.exit(code);
}
process.on('SIGINT', () => stop(0));
process.on('SIGTERM', () => stop(0));
if (deadline) {
  const ms = deadline - Date.now();
  if (ms <= 0) stop(0);
  setTimeout(() => stop(0), ms);
}

// Events are printed in the order they came, also while a name is being looked up.
let queue = Promise.resolve();

function connect() {
  const opened = {value: false};
  ws = new WebSocket(`${wsUrl}/?access_token=${encodeURIComponent(token)}`);
  const subscribe = () => ws.send(JSON.stringify({action: 'subscribe', version: '2', topic: 'chat'}));
  ws.onopen = () => {
    opened.value = true;
    subscribe();
    // The gateway drops a connection that is quiet for 10 minutes; subscribing again is harmless.
    clearInterval(keepalive);
    keepalive = setInterval(subscribe, 4 * 60 * 1000);
  };
  let acked = false;
  ws.onmessage = (m) => {
    let d;
    try {
      d = JSON.parse(m.data);
    } catch {
      return;
    }
    if (d.event === 'subscribed') {
      if (acked) return;
      acked = true;
      attempts = 0;
      const filters = drop({
        channels: channels.size ? [...channels] : undefined,
        from: senders.size ? [...senders] : undefined,
        types: types.size ? [...types] : undefined,
        mine: mine || undefined,
      });
      out(ready || reconnected ? 'RECONNECTED' : 'READY', {user: me, ...filters});
      ready = true;
      return;
    }
    if (d.event !== 'broadcast' || !d.data?.eventType || !wanted(d.data)) return;
    const e = d.data;
    queue = queue.then(async () => {
      if (stopping) return;
      out(e.eventType, await view(e));
      if (left > 0 && --left === 0) stop(0);
    });
  };
  ws.onclose = (ev) => {
    clearInterval(keepalive);
    if (stopping) return;
    // A connection lives at most two hours, and the token is checked only when it opens: with a token close
    // to its end, hand over to watch.sh, which loads a fresh one and starts this again.
    if (tokenExp && tokenExp - Date.now() < 2 * 60 * 1000) {
      if (stateFile) writeFileSync(stateFile, JSON.stringify({left}));
      out('RECONNECTING', {reason: 'token'});
      process.exit(75);
    }
    attempts += 1;
    if (!opened.value && attempts >= 5) fail(`the chat service did not accept the connection (code ${ev.code}): log in again with the wildix-auth skill if this repeats`, 2);
    const wait = Math.min(30, [1, 2, 5, 10][attempts - 1] ?? 30);
    out('RECONNECTING', {code: ev.code, attempt: attempts, inSeconds: wait});
    setTimeout(connect, wait * 1000);
  };
  ws.onerror = () => {
    // onclose follows and decides
  };
}
connect();
