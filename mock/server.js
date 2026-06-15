/**
 * ServiceNow Mock API Server
 * Mimics the ServiceNow REST Table API so Backstage works without a real instance.
 * Supports: cmdb_ci_service, incident, change_request, on_call_rota/whoisoncall
 */
const express = require('express');
const app = express();
app.use(express.json());

// ── Logging ──────────────────────────────────────────────────────────────────
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// ── Auth (accept any Basic auth in mock mode) ────────────────────────────────
app.use((req, res, next) => {
  if (!req.headers.authorization?.startsWith('Basic ')) {
    return res.status(401).json({ error: 'Unauthorized — send Basic auth' });
  }
  next();
});

// ── Seed data ────────────────────────────────────────────────────────────────
const CIs = [
  { sys_id: 'svc001', name: 'Payment Gateway',       short_description: 'Handles all payment processing flows',    u_team: 'Payments',  u_tier: '1', operational_status: '1', sys_class_name: 'cmdb_ci_service' },
  { sys_id: 'svc002', name: 'User Auth Service',     short_description: 'OAuth2 / SSO identity provider',         u_team: 'Platform',  u_tier: '1', operational_status: '1', sys_class_name: 'cmdb_ci_service' },
  { sys_id: 'svc003', name: 'Notification Engine',   short_description: 'Email, SMS, and push notifications',     u_team: 'Messaging', u_tier: '2', operational_status: '1', sys_class_name: 'cmdb_ci_service' },
  { sys_id: 'svc004', name: 'Reporting Service',     short_description: 'Business intelligence & reporting',      u_team: 'Analytics', u_tier: '2', operational_status: '2', sys_class_name: 'cmdb_ci_service' },
  { sys_id: 'svc005', name: 'API Gateway',           short_description: 'Edge API gateway and rate limiting',     u_team: 'Platform',  u_tier: '1', operational_status: '1', sys_class_name: 'cmdb_ci_service' },
];

const INCIDENTS = [
  { sys_id: 'inc001', number: 'INC0001001', short_description: 'Payment Gateway timeout errors',          state: '1', priority: '1', cmdb_ci: { value: 'svc001', display_value: 'Payment Gateway' },     opened_at: '2026-06-10 08:23:00', resolved_at: null },
  { sys_id: 'inc002', number: 'INC0001002', short_description: 'Auth token expiry not refreshing',        state: '2', priority: '2', cmdb_ci: { value: 'svc002', display_value: 'User Auth Service' },   opened_at: '2026-06-11 14:00:00', resolved_at: null },
  { sys_id: 'inc003', number: 'INC0001003', short_description: 'Email queue backlog > 10k',               state: '6', priority: '3', cmdb_ci: { value: 'svc003', display_value: 'Notification Engine' }, opened_at: '2026-06-08 09:00:00', resolved_at: '2026-06-09 17:00:00' },
  { sys_id: 'inc004', number: 'INC0001004', short_description: '3DS verification failures on EU region',  state: '2', priority: '2', cmdb_ci: { value: 'svc001', display_value: 'Payment Gateway' },     opened_at: '2026-06-12 11:05:00', resolved_at: null },
  { sys_id: 'inc005', number: 'INC0001005', short_description: 'API Gateway latency spike p99 > 2s',      state: '1', priority: '1', cmdb_ci: { value: 'svc005', display_value: 'API Gateway' },         opened_at: '2026-06-14 06:00:00', resolved_at: null },
];

const CHANGES = [
  { sys_id: 'chg001', number: 'CHG0001001', short_description: 'Upgrade Payment Gateway to v3.2',       state: '3',  risk: '2', cmdb_ci: { value: 'svc001', display_value: 'Payment Gateway' },     start_date: '2026-06-20 22:00:00', end_date: '2026-06-21 02:00:00' },
  { sys_id: 'chg002', number: 'CHG0001002', short_description: 'Rotate Auth Service TLS certificates',  state: '1',  risk: '1', cmdb_ci: { value: 'svc002', display_value: 'User Auth Service' },   start_date: '2026-06-18 06:00:00', end_date: '2026-06-18 07:00:00' },
  { sys_id: 'chg003', number: 'CHG0001003', short_description: 'Scale Notification workers to 20',      state: '-2', risk: '1', cmdb_ci: { value: 'svc003', display_value: 'Notification Engine' }, start_date: '2026-06-17 03:00:00', end_date: '2026-06-17 04:00:00' },
];

const ON_CALL = {
  svc001: [{ name: 'Alice Chen',   email: 'alice@example.com',  schedule: 'Primary' }, { name: 'Frank Lee', email: 'frank@example.com', schedule: 'Secondary' }],
  svc002: [{ name: 'Bob Smith',    email: 'bob@example.com',    schedule: 'Primary' }],
  svc003: [{ name: 'Carol Davis',  email: 'carol@example.com',  schedule: 'Primary' }],
  svc004: [{ name: 'Dave Wilson',  email: 'dave@example.com',   schedule: 'Primary' }],
  svc005: [{ name: 'Eve Martinez', email: 'eve@example.com',    schedule: 'Primary' }],
};

// ── Helpers ───────────────────────────────────────────────────────────────────
function paginate(req, rows) {
  const limit = parseInt(req.query.sysparm_limit || '20', 10);
  const offset = parseInt(req.query.sysparm_offset || '0', 10);
  return rows.slice(offset, offset + limit);
}
function applyQuery(rows, q) {
  if (!q) return rows;
  // Support: field=value  and  field=value^field2=value2
  const clauses = q.split('^');
  return rows.filter(row =>
    clauses.every(clause => {
      const [field, value] = clause.split('=');
      const cell = row[field];
      if (cell == null) return false;
      if (typeof cell === 'object') return cell.value === value;
      return String(cell).toLowerCase().includes(value.toLowerCase());
    })
  );
}

// ── Routes ────────────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok', mock: true }));
app.get('/api/now/table/cmdb_ci_service', (req, res) => {
  const rows = applyQuery(CIs, req.query.sysparm_query);
  res.json({ result: paginate(req, rows) });
});
app.get('/api/now/table/cmdb_ci_service/:sys_id', (req, res) => {
  const ci = CIs.find(c => c.sys_id === req.params.sys_id);
  return ci ? res.json({ result: ci }) : res.status(404).json({ error: 'Not found' });
});
app.get('/api/now/table/incident', (req, res) => {
  const rows = applyQuery(INCIDENTS, req.query.sysparm_query);
  res.json({ result: paginate(req, rows) });
});
app.get('/api/now/table/change_request', (req, res) => {
  const rows = applyQuery(CHANGES, req.query.sysparm_query);
  res.json({ result: paginate(req, rows) });
});
app.get('/api/now/on_call_rota/whoisoncall', (req, res) => {
  res.json({ result: ON_CALL[req.query.cmdb_ci] || [] });
});
app.use((req, res) => {
  console.warn(`[mock] Unhandled: ${req.method} ${req.path}`);
  res.status(404).json({ error: `No mock for ${req.method} ${req.path}` });
});

const PORT = process.env.MOCK_PORT || 8181;
app.listen(PORT, () => console.log(`🟢  ServiceNow mock listening on :${PORT}`));
