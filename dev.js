const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = process.env.PORT || 3000;
const ROOT = __dirname;
const WEB_BUILD_DIR = path.join(ROOT, 'build', 'web');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2'
};

const server = http.createServer((req, res) => {
  let [rawPath, queryString] = req.url.split('?');
  let reqPath = decodeURI(rawPath);
  const isLegacy = (queryString && queryString.includes('mode=canvas')) ||
                   reqPath === '/canvas' || reqPath === '/canvas/' ||
                   reqPath === '/legacy' || reqPath === '/legacy/' ||
                   reqPath === '/index.canvas.html';

  if (isLegacy) {
    // Serve preserved standalone canvas browser implementation
    const canvasFile = path.join(ROOT, 'index.canvas.html');
    fs.readFile(canvasFile, (readErr, content) => {
      if (readErr) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        return res.end('404 Canvas Backup Not Found');
      }
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-cache, no-store, must-revalidate'
      });
      res.end(content);
    });
    return;
  }

  if (reqPath === '/' || reqPath === '') {
    reqPath = '/index.html';
  }

  // Prioritize web build directory for exported Godot files (index.html, index.js, index.wasm, index.pck, etc.)
  const cleanGodotPath = reqPath.replace(/^\/godot/, '') || '/index.html';
  const webBuildPath = path.join(WEB_BUILD_DIR, cleanGodotPath);
  let filePath;

  if (fs.existsSync(webBuildPath) && fs.statSync(webBuildPath).isFile()) {
    filePath = webBuildPath;
  } else {
    filePath = path.join(ROOT, reqPath);
  }

  // Prevent directory traversal
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    return res.end('403 Forbidden');
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Fallback to Godot web index.html
      const indexPath = path.join(WEB_BUILD_DIR, 'index.html');
      fs.readFile(indexPath, (readErr, content) => {
        if (readErr) {
          res.writeHead(404, { 'Content-Type': 'text/plain' });
          return res.end('404 Not Found');
        }
        res.writeHead(200, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cross-Origin-Opener-Policy': 'same-origin',
          'Cross-Origin-Embedder-Policy': 'require-corp',
          'Cache-Control': 'no-cache, no-store, must-revalidate'
        });
        res.end(content);
      });
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    fs.readFile(filePath, (readErr, content) => {
      if (readErr) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        return res.end('500 Internal Server Error');
      }
      res.writeHead(200, {
        'Content-Type': contentType,
        'Content-Length': content.length,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Access-Control-Allow-Origin': '*'
      });
      res.end(content);
    });
  });
});

let currentPort = Number(PORT);

function startListening(port) {
  server.listen(port, '0.0.0.0', () => {
    const url = `http://localhost:${port}/`;
    console.log('\n=======================================================');
    console.log('🚀 RESPawn: PARALLAX — Godot 4.7.2 Web Dev Server');
    console.log('=======================================================');
    console.log(`\n  ➜  Godot Web:    ${url}`);
    console.log(`  ➜  Legacy Canvas: ${url}?mode=canvas (or /canvas)`);
    console.log(`  ➜  Network:      http://127.0.0.1:${port}/`);
    console.log('\n  Press Ctrl+C to terminate the server.\n');

    if (process.env.NO_AUTO_OPEN !== 'true' && process.env.CI !== 'true') {
      if (process.platform === 'win32') {
        exec(`start ${url}`);
      } else if (process.platform === 'darwin') {
        exec(`open ${url}`);
      } else {
        exec(`xdg-open ${url}`);
      }
    }
  });
}

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    currentPort += 1;
    console.error(`Port ${currentPort - 1} is in use. Retrying on port ${currentPort}...`);
    startListening(currentPort);
  } else {
    console.error('Server error:', err);
  }
});

startListening(currentPort);
