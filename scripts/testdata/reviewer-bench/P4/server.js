const http = require('http');
const crypto = require('crypto');

const users = new Map(); // email -> {id, salt, hash}
const sessions = new Map(); // token -> email
const notes = require('./notes');

const PAGE = `<!doctype html>
<html><head><meta charset="utf-8"><title>Notes</title></head>
<body>
<h1>Notes</h1>
<div id="out">
  <label>Email <input id="email" type="email" autocomplete="username"></label>
  <label>Password <input id="password" type="password" autocomplete="current-password"></label>
  <button id="signup">Sign up</button>
  <button id="login">Log in</button>
  <p id="msg"></p>
</div>
<div id="in" hidden>
  <button id="logout">Log out</button>
  <div>
    <label>Note <input id="note" maxlength="500"></label>
    <button id="add">Add note</button>
  </div>
  <ul id="list"></ul>
</div>
<script>
const $ = id => document.getElementById(id);
async function api(method, url, body) {
  const r = await fetch(url, {method, headers: {'Content-Type': 'application/json'},
    body: body === undefined ? undefined : JSON.stringify(body)});
  let data = null;
  try { data = await r.json(); } catch (e) {}
  return {status: r.status, data};
}
function show(signedIn) {
  $('out').hidden = signedIn;
  $('in').hidden = !signedIn;
}
async function load() {
  const r = await api('GET', '/api/notes');
  if (r.status !== 200) { show(false); return; }
  show(true);
  const ul = $('list');
  ul.textContent = '';
  for (const n of r.data) {
    const li = document.createElement('li');
    const s = document.createElement('span');
    s.textContent = n.text;
    const b = document.createElement('button');
    b.textContent = 'Delete';
    b.onclick = async () => { await api('DELETE', '/api/notes/' + n.id); load(); };
    li.append(s, ' ', b);
    ul.append(li);
  }
}
async function auth(path) {
  const r = await api('POST', path, {email: $('email').value, password: $('password').value});
  if (r.status === 200 || r.status === 201) { $('msg').textContent = ''; $('password').value = ''; load(); }
  else $('msg').textContent = 'refused';
}
$('signup').onclick = () => auth('/api/signup');
$('login').onclick = () => auth('/api/login');
$('logout').onclick = async () => { await api('POST', '/api/logout'); $('msg').textContent = ''; show(false); };
$('add').onclick = async () => {
  const r = await api('POST', '/api/notes', {text: $('note').value});
  if (r.status === 201) $('note').value = '';
  load();
};
load();
</script>
</body></html>`;

function send(res, status, obj, headers = {}) {
  if (obj === undefined) { res.writeHead(status, headers); return res.end(); }
  res.writeHead(status, {'Content-Type': 'application/json', ...headers});
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise(resolve => {
    let size = 0; const chunks = [];
    req.on('data', c => {
      size += c.length;
      if (size > 65536) { req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      try {
        const v = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        resolve(v && typeof v === 'object' && !Array.isArray(v) ? v : null);
      } catch (e) { resolve(null); }
    });
    req.on('error', () => resolve(null));
  });
}

function cookieToken(req) {
  for (const part of (req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0 && part.slice(0, i).trim() === 'sid') return part.slice(i + 1).trim();
  }
  return null;
}

function currentUser(req) {
  const t = cookieToken(req);
  return t && sessions.has(t) ? sessions.get(t) : null;
}

function hashPw(password, salt) {
  return crypto.scryptSync(password, salt, 64);
}

function startSession(res, status, email) {
  const token = crypto.randomBytes(32).toString('hex');
  sessions.set(token, email);
  send(res, status, {email}, {'Set-Cookie': `sid=${token}; Path=/; HttpOnly; SameSite=Strict`});
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    const path = url.pathname;
    const m = req.method;

    if (path === '/' && (m === 'GET' || m === 'HEAD')) {
      res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store'});
      return res.end(m === 'HEAD' ? undefined : PAGE);
    }

    if (path === '/api/signup' && m === 'POST') {
      const b = await readBody(req);
      if (!b || typeof b.email !== 'string' || typeof b.password !== 'string') return send(res, 400, {error: 'bad request'});
      const email = b.email.trim().toLowerCase();
      if (!EMAIL_RE.test(email) || email.length > 254 || b.password.length < 8 || b.password.length > 1024)
        return send(res, 400, {error: 'bad email or password'});
      if (users.has(email)) return send(res, 409, {error: 'email used'});
      const salt = crypto.randomBytes(16);
      users.set(email, {salt, hash: hashPw(b.password, salt)});
      return startSession(res, 201, email);
    }

    if (path === '/api/login' && m === 'POST') {
      const b = await readBody(req);
      if (!b || typeof b.email !== 'string' || typeof b.password !== 'string' || b.password.length > 1024)
        return send(res, 401, {error: 'refused'});
      const u = users.get(b.email.trim().toLowerCase());
      if (!u) { hashPw(b.password, Buffer.alloc(16)); return send(res, 401, {error: 'refused'}); }
      if (!crypto.timingSafeEqual(hashPw(b.password, u.salt), u.hash)) return send(res, 401, {error: 'refused'});
      return startSession(res, 200, b.email.trim().toLowerCase());
    }

    if (path === '/api/logout' && m === 'POST') {
      const t = cookieToken(req);
      if (t) sessions.delete(t);
      return send(res, 204, undefined, {'Set-Cookie': 'sid=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0'});
    }

    if (path === '/api/notes' || path.startsWith('/api/notes/')) {
      const email = currentUser(req);
      if (!email) return send(res, 401, {error: 'unauthorized'});
      const mine = notes.of(email);
      if (path === '/api/notes' && m === 'GET') return send(res, 200, mine.list());
      if (path === '/api/notes' && m === 'POST') {
        const b = await readBody(req);
        if (!b || typeof b.text !== 'string' || b.text.length < 1 || b.text.length > 500) return send(res, 400, {error: 'bad text'});
        return send(res, 201, mine.add(b.text));
      }
      const dm = path.match(/^\/api\/notes\/(\d+)$/);
      if (dm && m === 'DELETE') {
        const id = Number(dm[1]);
        if (!mine.remove(id)) return send(res, 404, {error: 'not found'});
        return send(res, 204);
      }
      if (dm) return send(res, 404, {error: 'not found'});
    }
    send(res, 404, {error: 'not found'});
  } catch (e) {
    send(res, 500, {error: 'server error'});
  }
});

server.listen(3000, '0.0.0.0');
