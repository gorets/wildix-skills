// The SIP side of the wildix-call-control skill: a headless SIP user of the logged-in extension (no media) that
// watches the user's calls, devices, presence and ringing mode live, and runs the call commands that only SIP has.
// Run through ../sip.sh, which gives the login token on stdin and the PBX in the environment. Prints one line per
// event: `<EVENT> <json>`. The SIP password is fetched from the PBX with the login token and never printed.
import {readFileSync} from 'node:fs';
import {CallControl} from '@gorets/wildix-callcontrol';

const out = (event, data) => process.stdout.write(`${event} ${JSON.stringify(data ?? {})}\n`);
const fail = (message, code = 1) => {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(code);
};

const [command = 'watch', ...args] = process.argv.slice(2);
const pbxBase = process.env.CC_PBX_BASE; // https://host[:port]
const extension = process.env.CC_EXTENSION;
if (!pbxBase || !extension) fail('run this through sip.sh');
const token = readFileSync(0, 'utf8').trim();
if (!token) fail('no login token on stdin: run this through sip.sh', 2);

// The PBX gives the SIP password of the user to the user's own login token.
async function sipPassword() {
  const res = await fetch(`${pbxBase}/api/v1/personal/info?fields=extension%2CsipPassword`, {
    // Without `Connection: close` Node keeps this socket and hands it to the SIP WebSocket to the same host,
    // which then closes with code 1006 within milliseconds.
    headers: {Authorization: `Bearer ${token}`, Accept: 'application/json', Connection: 'close'},
  });
  if (res.status === 401) fail('the PBX rejected the login: log in again with the wildix-auth skill', 2);
  if (!res.ok) fail(`the PBX gave no personal info (HTTP ${res.status})`);
  const body = await res.json();
  const info = body?.result ?? body;
  if (!info?.sipPassword) fail('the PBX did not give the SIP password of this user');
  if (String(info.extension) !== String(extension)) fail(`the PBX answered for extension ${info.extension}, not ${extension}`);
  return info.sipPassword;
}

const host = new URL(pbxBase).hostname;
const cc = new CallControl({
  pbxAddress: host,
  extension,
  sipPassword: await sipPassword(),
  userAgent: 'wildix-agent-skills watcher',
  // A watcher that is killed instead of stopped leaves its registration on the PBX until this runs out.
  expiresSeconds: 120,
  logToConsole: false,
  logger: () => {},
});

let stopping = false;
async function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  await cc.disconnect();
  process.exit(code);
}
process.on('SIGINT', () => stop(0));
process.on('SIGTERM', () => stop(0));

const callView = (c) => ({
  id: c.id,
  direction: c.direction,
  state: c.state,
  remoteNumber: c.remoteNumber,
  remoteName: c.remoteName,
  tags: c.tags,
  recording: c.recording,
  endReason: c.endReason,
});
// The watcher itself is a registered device of the user; it is shown, marked, so nobody picks it to ring.
const deviceView = (d) => ({
  contact: d.uri,
  name: d.deviceName,
  userAgent: d.userAgent,
  ...(d.userAgent === 'wildix-agent-skills watcher' ? {watcher: true} : {}),
});

async function connect() {
  try {
    await cc.connect();
    await cc.waitUntilReady(15000);
  } catch (e) {
    fail(`could not connect to the PBX as extension ${extension}: ${e.message}`);
  }
}

// One-shot commands: connect, check that the call is one of the user's current calls, run it, disconnect.
async function oneShot(run) {
  await connect();
  const [callId] = args;
  if (!cc.getActiveCalls().some((c) => c.id === callId)) {
    await cc.disconnect();
    fail(`no current call of this user has the id ${callId} (see: sip.sh calls or calls.sh list)`);
  }
  try {
    await run(callId);
    out('OK', {command, callId});
    await stop(0);
  } catch (e) {
    await cc.disconnect();
    fail(`${command} failed: ${e.message}`);
  }
}

switch (command) {
  case 'watch': {
    let calls = true;
    let all = true;
    let seconds = 0;
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--calls-only') all = false;
      else if (args[i] === '--for') seconds = Number(args[++i]);
      else fail(`unknown option ${args[i]}`);
    }
    if (!Number.isInteger(seconds) || seconds < 0) fail('--for takes whole seconds');
    cc.on('callStart', (c) => calls && out('CALL_START', callView(c)));
    cc.on('callUpdate', (c) => calls && out('CALL_UPDATE', callView(c)));
    cc.on('callEnd', (c) => calls && out('CALL_END', callView(c)));
    cc.on('reconnecting', (r) => out('RECONNECTING', r));
    cc.on('error', (e) => out('ERROR', {message: e?.message ?? String(e)}));
    let readyOnce = false;
    cc.on('ready', () => {
      out(readyOnce ? 'RECONNECTED' : 'READY', {
        extension,
        calls: cc.getActiveCalls().map(callView),
        ...(all ? {devices: cc.getDevices().map(deviceView), presence: cc.getPresence(), activeDevice: cc.getActiveDevice()} : {}),
      });
      readyOnce = true;
    });
    if (all) {
      cc.on('devicesChanged', (d) => readyOnce && out('DEVICES', d.map(deviceView)));
      cc.on('presenceChanged', (p) => readyOnce && out('PRESENCE', p));
      cc.on('activeDeviceChanged', (a) => readyOnce && out('ACTIVE_DEVICE', a));
    }
    await connect();
    if (seconds > 0) setTimeout(() => stop(0), seconds * 1000);
    break;
  }
  case 'calls': {
    await connect();
    out('CALLS', cc.getActiveCalls().map(callView));
    await stop(0);
    break;
  }
  case 'record': {
    const action = args[1];
    if (!['on', 'off', 'pause', 'unpause'].includes(action)) fail('record takes on, off, pause or unpause');
    await oneShot((id) => cc.record(id, action));
    break;
  }
  case 'conference-transfer': {
    const destination = args[1];
    if (!/^\+?[0-9*#]{1,40}$/.test(destination ?? '')) fail(`not a phone number or extension: ${destination}`);
    await oneShot((id) => cc.conferenceTransfer(id, destination));
    break;
  }
  default:
    fail(`unknown command ${command}`);
}
