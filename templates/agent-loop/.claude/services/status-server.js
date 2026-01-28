#!/usr/bin/env node

/**
 * Claude Agent Status Server
 * Exposes agent health and status via HTTP API
 *
 * Endpoints:
 *   GET /           - Basic health check
 *   GET /status     - Full status JSON
 *   GET /tasks      - Current task queue
 *   GET /metrics    - Resource metrics
 */

const http = require('http');
const fs = require('fs');
const { execSync } = require('child_process');

const PORT = process.env.PORT || 3000;
const WORKSPACE = '/agent-workspace';

// Read file safely
function readFile(path) {
  try {
    return fs.readFileSync(path, 'utf8');
  } catch (e) {
    return null;
  }
}

// Read JSON file safely
function readJSON(path) {
  try {
    return JSON.parse(fs.readFileSync(path, 'utf8'));
  } catch (e) {
    return null;
  }
}

// Get task counts from tasks.md
function getTaskCounts() {
  const content = readFile(`${WORKSPACE}/.claude/loop/tasks.md`) || '';
  const pending = (content.match(/^- \[ \]/gm) || []).length;
  const inProgress = (content.match(/^- \[\.\]/gm) || []).length;
  const completed = (content.match(/^- \[x\]/gm) || []).length;
  return { pending, in_progress: inProgress, completed };
}

// Get current in-progress task
function getCurrentTask() {
  const content = readFile(`${WORKSPACE}/.claude/loop/tasks.md`) || '';
  const match = content.match(/^- \[\.\] (.+)$/m);
  return match ? match[1] : null;
}

// Check if agent process is running
function isAgentRunning() {
  const lockFile = `${WORKSPACE}/.claude/loop/claude.lock`;
  try {
    const pid = fs.readFileSync(lockFile, 'utf8').trim();
    if (pid) {
      execSync(`kill -0 ${pid}`, { stdio: 'ignore' });
      return { running: true, pid: parseInt(pid) };
    }
  } catch (e) {
    // Process not running or lock file doesn't exist
  }
  return { running: false, pid: null };
}

// Get resource metrics
function getMetrics() {
  try {
    // Disk usage
    const dfOutput = execSync(`df -B1 ${WORKSPACE}`, { encoding: 'utf8' });
    const dfParts = dfOutput.split('\n')[1].split(/\s+/);
    const diskTotal = parseInt(dfParts[1]);
    const diskUsed = parseInt(dfParts[2]);
    const diskPercent = Math.round((diskUsed / diskTotal) * 100);

    // Memory usage
    const memOutput = execSync('free -b', { encoding: 'utf8' });
    const memLine = memOutput.split('\n')[1].split(/\s+/);
    const memTotal = parseInt(memLine[1]);
    const memUsed = parseInt(memLine[2]);
    const memPercent = Math.round((memUsed / memTotal) * 100);

    // Load average
    const loadOutput = execSync('cat /proc/loadavg', { encoding: 'utf8' });
    const [load1, load5, load15] = loadOutput.split(' ').slice(0, 3);

    return {
      disk: { percent: diskPercent, used_bytes: diskUsed, total_bytes: diskTotal },
      memory: { percent: memPercent, used_bytes: memUsed, total_bytes: memTotal },
      load: { load_1m: parseFloat(load1), load_5m: parseFloat(load5), load_15m: parseFloat(load15) }
    };
  } catch (e) {
    return { error: e.message };
  }
}

// Build full status response
function getFullStatus() {
  const state = readJSON(`${WORKSPACE}/.claude/loop/state.json`) || {};
  const health = readJSON(`${WORKSPACE}/.claude/health.json`) || {};
  const agent = isAgentRunning();
  const tasks = getTaskCounts();
  const currentTask = getCurrentTask();
  const metrics = getMetrics();

  return {
    status: agent.running ? 'active' : 'idle',
    timestamp: new Date().toISOString(),
    agent: {
      running: agent.running,
      pid: agent.pid,
      iteration: state.iteration || 0,
      last_update: state.updated_at || null
    },
    tasks: {
      ...tasks,
      current: currentTask
    },
    metrics,
    health: health.status || 'unknown'
  };
}

// Request handler
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'application/json');

  let response;
  let statusCode = 200;

  switch (url.pathname) {
    case '/':
    case '/health':
      const agent = isAgentRunning();
      response = {
        status: 'ok',
        agent_running: agent.running,
        timestamp: new Date().toISOString()
      };
      break;

    case '/status':
      response = getFullStatus();
      break;

    case '/tasks':
      response = {
        ...getTaskCounts(),
        current: getCurrentTask(),
        timestamp: new Date().toISOString()
      };
      break;

    case '/metrics':
      response = {
        ...getMetrics(),
        timestamp: new Date().toISOString()
      };
      break;

    default:
      statusCode = 404;
      response = {
        error: 'Not found',
        endpoints: ['/', '/health', '/status', '/tasks', '/metrics']
      };
  }

  res.statusCode = statusCode;
  res.end(JSON.stringify(response, null, 2));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Status server running on http://0.0.0.0:${PORT}`);
  console.log('Endpoints:');
  console.log('  GET /        - Basic health check');
  console.log('  GET /status  - Full status JSON');
  console.log('  GET /tasks   - Task queue status');
  console.log('  GET /metrics - Resource metrics');
});
