#!/usr/bin/env node
// plan-quota.js — auto-detect Copilot plan AI credits total
// Reads GITHUB_TOKEN / GH_TOKEN / COPILOT_TOKEN from env,
// calls https://api.github.com/copilot_internal/user,
// extracts quota_snapshots.premium_interactions.entitlementRequests,
// and prints JSON: {"total": N, "used": M, "source": "api"|"cache"|"none"}
// Caches to %USERPROFILE%\.copilot\plan-quota-cache.json with 6h TTL.

const fs = require('fs');
const path = require('path');
const https = require('https');
const os = require('os');

const CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const CACHE_FILE = path.join(os.homedir(), '.copilot', 'plan-quota-cache.json');

function readCache() {
  try {
    const raw = fs.readFileSync(CACHE_FILE, 'utf8');
    const j = JSON.parse(raw);
    if (j && j.ts && (Date.now() - j.ts) < CACHE_TTL_MS && j.total > 0) return j;
  } catch {}
  return null;
}

function writeCache(obj) {
  try { fs.writeFileSync(CACHE_FILE, JSON.stringify(obj)); } catch {}
}

function fetchQuota(token) {
  return new Promise((resolve) => {
    const opts = {
      method: 'GET',
      hostname: 'api.github.com',
      path: '/copilot_internal/user',
      headers: {
        'Authorization': 'token ' + token,
        'User-Agent': 'copilot-cli-statusline/1.0',
        'Accept': 'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      timeout: 4000,
    };
    const req = https.request(opts, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        try {
          const j = JSON.parse(body);
          const snap = j && j.quota_snapshots && j.quota_snapshots.premium_interactions;
          // Schema (09/26): entitlement / credits_used / unlimited / quota_reset_at.
          // Fallback to legacy field names for older responses.
          const total = snap && (
            (typeof snap.entitlement === 'number' && snap.entitlement) ||
            (typeof snap.entitlementRequests === 'number' && snap.entitlementRequests)
          );
          if (total > 0) {
            const used = (typeof snap.credits_used === 'number' ? snap.credits_used
                        : typeof snap.usedRequests === 'number' ? snap.usedRequests : 0);
            resolve({
              total: total,
              used: used,
              unlimited: !!(snap.unlimited || snap.isUnlimitedEntitlement),
              resetDate: snap.quota_reset_at || snap.resetDate || null,
            });
          } else resolve(null);
        } catch { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
    req.end();
  });
}

(async () => {
  const cached = readCache();
  if (cached) {
    process.stdout.write(JSON.stringify({ total: cached.total, used: cached.used, source: 'cache' }));
    return;
  }
  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN || process.env.COPILOT_TOKEN || process.env.GITHUB_COPILOT_TOKEN;
  if (!token) {
    process.stdout.write(JSON.stringify({ total: 0, used: 0, source: 'none' }));
    return;
  }
  const q = await fetchQuota(token);
  if (q) {
    writeCache({ ts: Date.now(), total: q.total, used: q.used });
    process.stdout.write(JSON.stringify({ total: q.total, used: q.used, source: 'api' }));
  } else {
    process.stdout.write(JSON.stringify({ total: 0, used: 0, source: 'none' }));
  }
})();
