'use strict';

const express = require('express');
const os      = require('os');

const app  = express();
const PORT = parseInt(process.env.PORT  || '3001', 10);
const NAME = process.env.NAME           || `${os.hostname()}-${PORT}`;

// ── Endpoint principal ─────────────────────────────────────────────────────────
app.get('/', (_req, res) => {
  res.json({
    status:     'ok',
    instance:   NAME,
    hostname:   os.hostname(),
    port:       PORT,
    pid:        process.pid,
    timestamp:  new Date().toISOString(),
    message:    'Respuesta desde réplica Node.js via HAProxy + Consul'
  });
});

// ── Health-check (Consul + HAProxy lo usan) ────────────────────────────────────
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'healthy', instance: NAME });
});

// ── Arranque ───────────────────────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`[${NAME}] escuchando en 0.0.0.0:${PORT}`);
});