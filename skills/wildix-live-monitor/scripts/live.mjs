// The live stream of Wildix Data Analytics (WDA) for the logged-in user: call queues and their agents, the calls,
// chats and conferences going on in the company, presence of colleagues, and the live transcript of a call.
// Run through ../live.sh, which gives the login token on stdin. Read only: it never changes anything.
// One-shot commands print one JSON object; `watch` and `transcript --follow` print `<EVENT> <json>` lines.
import {readFileSync, writeFileSync} from 'node:fs';

const fail = (message, code = 1) => {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(code);
};
const line = (event, data) => process.stdout.write(`${event} ${JSON.stringify(data ?? {})}\n`);
const print = (data) => process.stdout.write(`${JSON.stringify(data)}\n`);
const drop = (o) => JSON.parse(JSON.stringify(o)); // removes the undefined fields

const wsUrl = process.env.LIVE_WS_URL;
if (!wsUrl) fail('run this through live.sh');
const token = readFileSync(0, 'utf8').trim();
if (!token) fail('no login token on stdin: run this through live.sh', 2);
const claims = (() => {
  try {
    return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
  } catch {
    return fail('the login token could not be read: log in again with the wildix-auth skill', 2);
  }
})();
const company = claims.company;
const myExtension = claims['custom:pbx_user_extension'] ? String(claims['custom:pbx_user_extension']) : undefined;
const license = claims['custom:pbx_license'];

// ── options ──────────────────────────────────────────────────────────────────────────────────────────────────
const [command, ...argv] = process.argv.slice(2);
const opt = {list: {}, flags: new Set()};
const positional = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (['--full', '--busy', '--paused', '--calls', '--chats', '--conferences', '--follow', '--mine', '--queues', '--conversations', '--reconnected'].includes(a)) opt.flags.add(a.slice(2));
  else if (['--name', '--status', '--limit', '--for', '--deadline', '--state', '--presence'].includes(a)) {
    const v = argv[++i];
    if (v === undefined) fail(`${a} needs a value`);
    (opt.list[a.slice(2)] ??= []).push(v);
  } else if (a.startsWith('--')) fail(`unknown option ${a}`);
  else positional.push(a);
}
const one = (k) => opt.list[k]?.at(-1);
const has = (k) => opt.flags.has(k);
const full = has('full');

// ── the connection ───────────────────────────────────────────────────────────────────────────────────────────
// Protocol: {"action":"authorize","token"} -> {"event":"authorized"}; then
// {"action":"subscribe","topic","version","state","filter"} -> the current state as {"event":"broadcast","topic",
// "data":[…]} frames, then {"event":"subscribed","topic"}; afterwards one broadcast per change.
// An error is {"event":"error","message","code","source"}: `source` echoes the request, which for authorize
// holds the token, so it is never printed.
let ws;
let stopping = false;
const listeners = new Set();

function open() {
  return new Promise((resolve, reject) => {
    ws = new WebSocket(`${wsUrl}/`);
    let done = false;
    const timer = setTimeout(() => !done && reject(new Error('the live service did not answer in 20 seconds')), 20000);
    ws.onopen = () => ws.send(JSON.stringify({action: 'authorize', token}));
    ws.onmessage = (m) => {
      let d;
      try {
        d = JSON.parse(m.data);
      } catch {
        return;
      }
      if (!done) {
        if (d.event === 'authorized') {
          done = true;
          clearTimeout(timer);
          resolve();
        } else if (d.event === 'error') {
          done = true;
          clearTimeout(timer);
          reject(Object.assign(new Error(`the live service refused the login: ${d.message}`), {auth: true}));
        }
        return;
      }
      for (const l of listeners) l(d);
    };
    ws.onclose = (ev) => {
      if (!done) {
        done = true;
        clearTimeout(timer);
        reject(new Error(`the live service closed the connection (code ${ev.code})`));
      }
      for (const l of listeners) l({event: '_closed', code: ev.code});
    };
    ws.onerror = () => {};
  });
}

const sub = (topic, extra = {}) => ({action: 'subscribe', topic, version: '2', ...extra});

// Subscribes and collects the current state: every broadcast of the topic until the "subscribed" answer.
function snapshot(topic, extra = {}) {
  return new Promise((resolve, reject) => {
    const items = [];
    const timer = setTimeout(() => finish(new Error(`no answer for ${topic} in 30 seconds`)), 30000);
    const listener = (d) => {
      if (d.event === 'broadcast' && d.topic === topic) items.push(...(Array.isArray(d.data) ? d.data : [d.data]));
      else if (d.event === 'subscribed' && d.topic === topic) finish();
      else if (d.event === 'error') finish(new Error(explain(topic, d)));
      else if (d.event === '_closed') finish(new Error(`the live service closed the connection (code ${d.code})`));
    };
    function finish(err) {
      clearTimeout(timer);
      listeners.delete(listener);
      if (err) reject(err);
      else resolve(items);
    }
    listeners.add(listener);
    ws.send(JSON.stringify(sub(topic, {state: true, ...extra})));
  });
}

function explain(topic, d) {
  if (d.code === 403 && (topic === 'services' || topic === 'conversations')) {
    return `the live service allows ${topic === 'services' ? 'call queues' : 'the conversations of the company'} only to users with a Premium license (this login: ${license ?? 'unknown'})`;
  }
  if (d.code === 401) return 'the live service lost the login: run the command again';
  return `the live service refused the ${topic} subscription (${d.code ?? '?'}): ${d.message}`;
}

async function connectOrFail() {
  try {
    await open();
  } catch (e) {
    fail(e.message, e.auth ? 2 : 1);
  }
}
function close(code = 0) {
  stopping = true;
  try {
    ws?.close(1000);
  } catch {
    // already closed
  }
  process.exit(code);
}

// ── views: short by default, private fields only with --full ──────────────────────────────────────────────────
// Left out unless --full: e-mail, public IP address, geographic location and user agent of people.
function party(p) {
  if (!p) return undefined;
  if (full) return p;
  return drop({
    name: p.name,
    phone: p.phone,
    extension: p.userExtension,
    department: p.userDepartment,
    group: p.groupName,
    type: p.type,
    role: p.role,
    device: p.userDevice,
    sipCallId: p.sipCallId,
  });
}

function flowView(f) {
  return drop({
    flowIndex: f.flowIndex,
    status: f.status,
    direction: f.direction,
    caller: party(f.caller),
    callee: party(f.callee),
    destination: f.destination,
    queue: f.queue ?? f.service,
    start: f.startTime ? new Date(f.startTime).toISOString() : undefined,
    talkSeconds: f.talkTime ? Math.round(f.talkTime / 1000) : undefined,
    waitSeconds: f.waitTime ? Math.round(f.waitTime / 1000) : undefined,
    holdSeconds: f.holdTime ? Math.round(f.holdTime / 1000) : undefined,
    recording: f.recordings?.length ? true : undefined,
    transcription: f.transcriptionStatus,
    tags: f.tags?.length ? f.tags : undefined,
  });
}

function insights(a) {
  if (!a) return undefined;
  const v = (k) => a[`copilot.${k}`]?.payload?.metric?.value;
  return drop({sentiment: v('sentiment'), csat: v('csat'), topics: v('topics'), signals: v('signals')});
}

function conversationView(c) {
  if (full) return c;
  const base = {id: c.id, type: c.event, trigger: c.eventTrigger, start: c.start};
  if (c.event === 'call') return drop({...base, flows: (c.flows ?? []).map(flowView)});
  if (c.event === 'chat') {
    return drop({
      ...base,
      status: c.status,
      subject: c.subject,
      direction: c.direction,
      channelId: c.channelId,
      customers: c.customers?.map((p) => drop({name: p.name, company: p.company})),
      agents: c.agents?.map((p) => drop({name: p.name, bot: p.bot || undefined})),
      tags: c.tags?.length ? c.tags : undefined,
      insights: insights(c.annotationsByKey),
    });
  }
  if (c.event === 'conference') {
    return drop({
      ...base,
      subject: c.subject,
      participants: c.participants?.map((p) => drop({name: p.name, role: p.role, type: p.type})),
      insights: insights(c.annotationsByKey),
    });
  }
  // completions and annotations: say what ended or changed, not more
  return drop({...base, flows: typeof c.flows === 'number' ? c.flows : undefined, key: c.key, insights: insights(c.annotationsByKey)});
}

function agentView(a) {
  if (full) return a;
  return drop({
    name: a.name,
    extension: a.userExtension,
    department: a.department,
    status: a.status,
    paused: a.paused === 'true' || a.paused === true || undefined,
    reason: a.reason || undefined,
    message: a.message || undefined,
  });
}

function queueView(s) {
  if (full) return s;
  return drop({
    id: s.id,
    name: s.name,
    strategy: s.strategy,
    maxCalls: s.maxCalls ? Number(s.maxCalls) : undefined,
    calls: s.calls?.length ?? 0,
    callIds: s.calls?.length ? s.calls : undefined,
    agents: s.agents?.map(agentView),
  });
}

function serviceCallView(c) {
  if (full) return c;
  return drop({
    queueId: c.id,
    trigger: c.eventTrigger,
    callId: c.callId,
    direction: c.direction,
    customer: c.customer?.phone ?? c.customer?.name,
    start: c.startTime ? new Date(c.startTime).toISOString() : undefined,
    agents: c.relatedAgents?.length,
  });
}

function presenceView(p) {
  if (full) return p;
  return drop({
    extension: p.extension,
    company: p.company !== company ? p.company : undefined,
    status: p.status,
    message: p.message || undefined,
    until: p.until || undefined,
    phone: p.telephony,
  });
}

function textView(chunk, call) {
  const flow = call?.flows?.find?.((f) => f.flowIndex === chunk.flowIndex);
  const who = chunk.speaker === 'caller' ? flow?.caller : chunk.speaker === 'callee' ? flow?.callee : undefined;
  return drop({
    flow: chunk.flowIndex,
    speaker: chunk.speaker ?? chunk.participant?.name,
    name: who?.name ?? chunk.participant?.name ?? chunk.name,
    text: chunk.text,
    final: chunk.isFinal,
    at: chunk.start ?? chunk.time,
    language: chunk.language,
    sentiment: chunk.sentiment,
  });
}

// Transcription items: a stored transcript ({flowIndex, chunks: {id: chunk}}), a live line ({chunk}), or a
// conference transcript; each becomes chunks with the flow index kept.
function chunksOf(item) {
  if (item?.chunk) return [{...item.chunk, flowIndex: item.flowIndex, participant: item.participant}];
  if (item?.chunks) return Object.values(item.chunks).map((c) => ({...c, flowIndex: item.flowIndex}));
  return [];
}

const isMineCall = (c) =>
  myExtension && Array.isArray(c.flows) && c.flows.some((f) => f.caller?.userExtension === myExtension || f.callee?.userExtension === myExtension);

// ── commands ─────────────────────────────────────────────────────────────────────────────────────────────────
const lastById = (items) => {
  const m = new Map();
  for (const it of items) if (it?.id) m.set(it.id, it);
  return [...m.values()];
};

async function queues() {
  await connectOrFail();
  let items;
  try {
    items = await snapshot('services');
  } catch (e) {
    fail(e.message);
  }
  let qs = lastById(items.filter((i) => i.event === 'service'));
  const name = one('name')?.toLowerCase();
  if (name) qs = qs.filter((q) => q.name?.toLowerCase().includes(name));
  if (has('busy')) qs = qs.filter((q) => q.calls?.length);
  if (has('paused')) qs = qs.filter((q) => q.agents?.some((a) => a.paused === 'true' || a.paused === true));
  qs.sort((a, b) => (b.calls?.length ?? 0) - (a.calls?.length ?? 0) || String(a.name).localeCompare(String(b.name)));
  print({total: qs.length, callsWaitingOrTalking: qs.reduce((n, q) => n + (q.calls?.length ?? 0), 0), queues: qs.map(queueView)});
  close(0);
}

async function conversations() {
  await connectOrFail();
  let items;
  try {
    items = await snapshot('conversations');
  } catch (e) {
    fail(e.message);
  }
  let cs = lastById(items.filter((i) => ['call', 'chat', 'conference'].includes(i.event)));
  const kinds = ['calls', 'chats', 'conferences'].filter(has).map((k) => k.slice(0, -1));
  const byType = {};
  for (const c of cs) byType[c.event] = (byType[c.event] ?? 0) + 1;
  if (kinds.length) cs = cs.filter((c) => kinds.includes(c.event));
  if (has('mine')) cs = cs.filter(isMineCall);
  const status = one('status')?.toUpperCase();
  if (status) cs = cs.filter((c) => String(c.status ?? c.flows?.at?.(-1)?.status ?? '').toUpperCase() === status);
  cs.sort((a, b) => String(b.start).localeCompare(String(a.start)));
  const limit = Number(one('limit') ?? 50);
  print({total: cs.length, byType, shown: Math.min(limit, cs.length), items: cs.slice(0, limit).map(conversationView)});
  close(0);
}

async function presence() {
  if (!positional.length) fail('name at least one extension');
  if (!company) fail('this login names no company');
  await connectOrFail();
  let items;
  try {
    items = await snapshot('presence', {filter: positional.map((ext) => [null, company, ext])});
  } catch (e) {
    fail(e.message);
  }
  const found = new Map(items.map((p) => [String(p.extension), p]));
  print({presence: positional.map((ext) => (found.has(ext) ? presenceView(found.get(ext)) : {extension: ext, status: 'unknown'}))});
  close(0);
}

// The WDA id of a call from a SIP call id: through the conversations of the company (Premium only).
async function wdaCallId(id) {
  if (company && id.startsWith(`${company}_`)) return id;
  let items;
  try {
    items = await snapshot('conversations', {state: true});
  } catch (e) {
    fail(`${e.message}. Without it, give the WDA id of the call (${company ?? '<company>'}_…)`);
  }
  const call = items.find((c) => c.event === 'call' && c.flows?.some?.((f) => f.caller?.sipCallId === id || f.callee?.sipCallId === id));
  if (!call) fail(`no call going on now has the SIP call id ${id}`);
  return call.id;
}

async function transcript() {
  const [arg] = positional;
  if (!arg) fail('name the call: its WDA id or its SIP call id');
  await connectOrFail();
  const kind = arg.startsWith('conference:') ? 'conference' : 'call';
  const id = kind === 'conference' ? arg.slice('conference:'.length) : await wdaCallId(arg);
  let items;
  try {
    items = await snapshot('transcriptions', {state: true, filter: [[kind, id]]});
  } catch (e) {
    fail(e.message.includes('not found') ? `${kind} ${id} is not going on now (a live transcript exists only while it lasts)` : e.message);
  }
  let call = items.find((i) => i.event === 'call' || i.event === 'conference');
  const lines = items.flatMap(chunksOf).filter((c) => c.text).sort((a, b) => (a.start ?? 0) - (b.start ?? 0));
  const annotations = items.filter((i) => String(i.event).endsWith('_annotation'));
  const snap = drop({
    id,
    type: kind,
    call: call ? conversationView(call) : undefined,
    transcript: lines.filter((c) => c.isFinal !== false).map((c) => textView(c, call)),
    annotations: annotations.length ? annotations.map((a) => drop({key: a.key, payload: a.payload})) : undefined,
  });
  if (!has('follow')) {
    print(snap);
    close(0);
  }
  line('SNAPSHOT', snap);
  listeners.add((d) => {
    if (d.event === '_closed') {
      if (!stopping) fail(`the connection was lost (code ${d.code})`);
      return;
    }
    if (d.event !== 'broadcast' || d.topic !== 'transcriptions') return;
    for (const it of Array.isArray(d.data) ? d.data : [d.data]) {
      if (it.event === 'call' || it.event === 'conference') {
        call = it;
        line('CALL', conversationView(it));
      } else if (/_complete$|_interrupted$/.test(it.event)) {
        line('END', {id, event: it.event});
        close(0);
      } else if (String(it.event).endsWith('_annotation')) line('ANNOTATION', drop({key: it.key, payload: it.payload}));
      else for (const c of chunksOf(it)) if (c.text) line('TEXT', textView(c, call));
    }
  });
  const secs = Number(one('for') ?? 0);
  if (secs > 0) setTimeout(() => close(0), secs * 1000);
}

async function watch() {
  const wantQueues = has('queues');
  const wantConv = has('conversations') || has('calls') || has('mine') || (!wantQueues && !opt.list.presence);
  const presenceExt = opt.list.presence ?? [];
  const deadline = Number(one('deadline') ?? 0) * 1000;
  const stateFile = one('state');
  const mineIds = new Set();
  let ready = has('reconnected');
  let keepalive;
  let attempts = 0;

  const subscriptions = () => [
    ...(wantConv ? [sub('conversations', {state: false})] : []),
    ...(wantQueues ? [sub('services', {state: false})] : []),
    ...(presenceExt.length ? [sub('presence', {state: false, filter: presenceExt.map((e) => [null, company, e])})] : []),
  ];

  const onFrame = (d) => {
    if (d.event === '_closed') {
      clearInterval(keepalive);
      if (stopping) return;
      if (claims.exp * 1000 - Date.now() < 2 * 60 * 1000) {
        if (stateFile) writeFileSync(stateFile, '{}');
        line('RECONNECTING', {reason: 'token'});
        process.exit(75);
      }
      attempts += 1;
      const wait = [1, 2, 5, 10][attempts - 1] ?? 30;
      line('RECONNECTING', {code: d.code, attempt: attempts, inSeconds: wait});
      setTimeout(start, wait * 1000);
      return;
    }
    if (d.event === 'error') {
      line('ERROR', {message: explain(d.source?.topic ?? 'subscription', d), code: d.code});
      if (d.code === 403) close(1);
      return;
    }
    if (d.event !== 'broadcast') return;
    for (const it of Array.isArray(d.data) ? d.data : [d.data]) {
      if (!it) continue;
      if (d.topic === 'presence') line('PRESENCE', presenceView(it));
      else if (d.topic === 'services') {
        // A change names what changed (eventTrigger) and carries only that: usually one agent, no queue name.
        if (it.event === 'service') line('QUEUE', full ? it : drop({trigger: it.eventTrigger, ...queueView(it)}));
        else if (it.event === 'serviceCall' || it.event === 'service_call') line('QUEUE_CALL', serviceCallView(it));
        else line(String(it.event).toUpperCase(), full ? it : drop({id: it.id, trigger: it.eventTrigger}));
      } else if (d.topic === 'conversations') {
        const type = String(it.event);
        if (has('calls') && !type.startsWith('call')) continue;
        if (has('mine')) {
          if (type === 'call' && isMineCall(it)) mineIds.add(it.id);
          if (!mineIds.has(it.id)) continue;
          if (type !== 'call') mineIds.delete(it.id);
        }
        line(type.toUpperCase(), conversationView(it));
      }
    }
  };

  async function start() {
    try {
      await open();
    } catch (e) {
      if (e.auth) fail(e.message, 2);
      attempts += 1;
      if (attempts >= 5) fail(e.message);
      setTimeout(start, ([1, 2, 5, 10][attempts - 1] ?? 30) * 1000);
      return;
    }
    listeners.clear();
    listeners.add(onFrame);
    for (const s of subscriptions()) ws.send(JSON.stringify(s));
    attempts = 0;
    // The gateway drops a connection that is quiet for 10 minutes; subscribing again is harmless.
    clearInterval(keepalive);
    keepalive = setInterval(() => subscriptions().forEach((s) => ws.send(JSON.stringify(s))), 4 * 60 * 1000);
    line(ready ? 'RECONNECTED' : 'READY', drop({
      extension: myExtension,
      license,
      topics: [wantConv && 'conversations', wantQueues && 'queues', presenceExt.length && 'presence'].filter(Boolean),
      calls: has('calls') || undefined,
      mine: has('mine') || undefined,
    }));
    ready = true;
  }

  process.on('SIGINT', () => close(0));
  process.on('SIGTERM', () => close(0));
  if (deadline) {
    if (deadline <= Date.now()) close(0);
    setTimeout(() => close(0), deadline - Date.now());
  }
  await start();
}

switch (command) {
  case 'queues':
    await queues();
    break;
  case 'conversations':
    await conversations();
    break;
  case 'presence':
    await presence();
    break;
  case 'transcript':
    await transcript();
    break;
  case 'watch':
    await watch();
    break;
  default:
    fail(`unknown command ${command}`);
}
