const express = require('express');

const app = express();
const PORT = process.env.PORT || 3001;
const DELAY_MS = Number(process.env.DELAY_MS || 0);

app.use(express.json({ limit: '50kb' }));

const crypto = require('crypto');
function getReqId(req) { return req.header('X-Request-Id') || crypto.randomUUID(); }
app.use((req, res, next) => {
  const rid = getReqId(req);
  req.requestId = rid;
  res.setHeader('X-Request-Id', rid);
  console.log(`[rid=${rid}] ${req.method} ${req.path}`);
  next();
});

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

app.get('/health', (req, res) => res.json({ ok: true }));

app.post('/price', async (req, res) => {
  if (DELAY_MS > 0) await sleep(DELAY_MS);

  const { subtotal } = req.body;
  const s = Number(subtotal);
  if (!Number.isFinite(s) || s < 0) {
    return res.status(400).json({ error: 'subtotal must be a non-negative number' });
  }
  const taxRate = 0.23;
  const tax = Number((s * taxRate).toFixed(2));
  const total = Number((s + tax).toFixed(2));
  return res.json({ subtotal: s, taxRate, tax, total });
});

app.listen(PORT, () => console.log(`pricing-fn on ${PORT}`));
