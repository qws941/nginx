/**
 * Nginx 프록시 웹 관리 UI
 * 기존 PowerShell 스크립트를 웹 인터페이스로 제공
 *
 * 사용법:
 *   node nginx-web-ui.js
 *   브라우저에서 http://localhost:8080 접속
 */

const express = require('express');
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 8080;
const NGINX_PATH = process.env.NGINX_PATH || 'C:\\nginx';
const CONF_D_PATH = path.join(NGINX_PATH, 'conf', 'conf.d');

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static('public'));

// ===========================
// API 엔드포인트
// ===========================

/**
 * 모든 프록시 설정 조회
 */
app.get('/api/proxies', (req, res) => {
    fs.readdir(CONF_D_PATH, (err, files) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }

        const confFiles = files.filter(f => f.endsWith('.conf'));
        const proxies = [];

        confFiles.forEach(file => {
            const filePath = path.join(CONF_D_PATH, file);
            const content = fs.readFileSync(filePath, 'utf8');

            // 설정 파싱 (간단한 버전)
            const serverNameMatch = content.match(/server_name\s+([^;]+);/);
            const listenMatch = content.match(/listen\s+(\d+)\s*ssl?;/);
            const proxyPassMatch = content.match(/proxy_pass\s+([^;]+);/);

            proxies.push({
                filename: file,
                serverName: serverNameMatch ? serverNameMatch[1].trim() : 'unknown',
                port: listenMatch ? parseInt(listenMatch[1]) : 80,
                backend: proxyPassMatch ? proxyPassMatch[1].trim() : 'unknown',
                ssl: content.includes('ssl_certificate')
            });
        });

        res.json({ success: true, proxies });
    });
});

/**
 * 새 프록시 설정 추가
 */
app.post('/api/proxies', (req, res) => {
    const { serviceName, aRecord, ip, port, useHTTPS, customPath, description } = req.body;

    if (!serviceName || !aRecord || !ip || !port) {
        return res.status(400).json({ error: 'Missing required fields' });
    }

    // PowerShell 스크립트 호출
    const psScript = `
        $csvPath = "${CONF_D_PATH}\\..\\..\\services.csv"
        if (-not (Test-Path $csvPath)) {
            "서비스명,ARecord,IP,Port,UseHTTPS,CustomPath,비고" | Out-File -FilePath $csvPath -Encoding UTF8
        }
        "${serviceName},${aRecord},${ip},${port},${useHTTPS || 'N'},${customPath || ''},${description || ''}" | Add-Content -Path $csvPath -Encoding UTF8

        # Nginx 설정 재로드
        & "${NGINX_PATH}\\nginx.exe" -s reload
    `;

    exec(`powershell.exe -Command "${psScript.replace(/\n/g, '; ')}"`, (error, stdout, stderr) => {
        if (error) {
            return res.status(500).json({ error: error.message, stderr });
        }
        res.json({ success: true, message: 'Proxy added successfully', stdout });
    });
});

/**
 * 프록시 설정 삭제
 */
app.delete('/api/proxies/:filename', (req, res) => {
    const filename = req.params.filename;
    const filePath = path.join(CONF_D_PATH, filename);

    if (!filename.endsWith('.conf')) {
        return res.status(400).json({ error: 'Invalid filename' });
    }

    fs.unlink(filePath, (err) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }

        // Nginx 재로드
        exec(`${NGINX_PATH}\\nginx.exe -s reload`, (error) => {
            if (error) {
                return res.status(500).json({ error: error.message });
            }
            res.json({ success: true, message: 'Proxy deleted successfully' });
        });
    });
});

/**
 * Nginx 상태 확인
 */
app.get('/api/status', (req, res) => {
    exec(`${NGINX_PATH}\\nginx.exe -t`, (error, stdout, stderr) => {
        const status = {
            configValid: !error,
            message: stderr || stdout,
            timestamp: new Date().toISOString()
        };
        res.json(status);
    });
});

/**
 * Nginx 재로드
 */
app.post('/api/reload', (req, res) => {
    exec(`${NGINX_PATH}\\nginx.exe -s reload`, (error, stdout, stderr) => {
        if (error) {
            return res.status(500).json({ error: error.message, stderr });
        }
        res.json({ success: true, message: 'Nginx reloaded successfully' });
    });
});

// ===========================
// 웹 UI (HTML)
// ===========================

app.get('/', (req, res) => {
    res.send(`
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nginx Proxy Manager - Windows</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        header {
            background: #2c3e50;
            color: white;
            padding: 20px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        header h1 { font-size: 24px; }
        .status { display: flex; gap: 10px; align-items: center; }
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #2ecc71;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .content { padding: 30px; }
        .actions {
            display: flex;
            gap: 15px;
            margin-bottom: 30px;
        }
        button {
            padding: 12px 24px;
            border: none;
            border-radius: 5px;
            font-size: 14px;
            cursor: pointer;
            transition: all 0.3s;
            font-weight: 600;
        }
        .btn-primary {
            background: #3498db;
            color: white;
        }
        .btn-primary:hover {
            background: #2980b9;
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        .btn-success {
            background: #2ecc71;
            color: white;
        }
        .btn-success:hover {
            background: #27ae60;
        }
        .btn-danger {
            background: #e74c3c;
            color: white;
        }
        .btn-danger:hover {
            background: #c0392b;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th, td {
            padding: 15px;
            text-align: left;
            border-bottom: 1px solid #ecf0f1;
        }
        th {
            background: #34495e;
            color: white;
            font-weight: 600;
        }
        tr:hover {
            background: #f8f9fa;
        }
        .badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
        }
        .badge-ssl {
            background: #2ecc71;
            color: white;
        }
        .badge-http {
            background: #95a5a6;
            color: white;
        }
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.5);
            z-index: 1000;
            align-items: center;
            justify-content: center;
        }
        .modal.active { display: flex; }
        .modal-content {
            background: white;
            padding: 30px;
            border-radius: 10px;
            width: 90%;
            max-width: 500px;
        }
        .form-group {
            margin-bottom: 20px;
        }
        .form-group label {
            display: block;
            margin-bottom: 8px;
            font-weight: 600;
            color: #2c3e50;
        }
        .form-group input {
            width: 100%;
            padding: 10px;
            border: 2px solid #ecf0f1;
            border-radius: 5px;
            font-size: 14px;
        }
        .form-group input:focus {
            outline: none;
            border-color: #3498db;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🚀 Nginx Proxy Manager</h1>
            <div class="status">
                <div class="status-dot"></div>
                <span id="status-text">Nginx Running</span>
            </div>
        </header>

        <div class="content">
            <div class="actions">
                <button class="btn-primary" onclick="showAddModal()">➕ Add Proxy</button>
                <button class="btn-success" onclick="reloadNginx()">🔄 Reload Nginx</button>
                <button class="btn-primary" onclick="loadProxies()">🔍 Refresh</button>
            </div>

            <table id="proxy-table">
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>Port</th>
                        <th>Backend</th>
                        <th>SSL</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody id="proxy-list">
                    <tr><td colspan="5" style="text-align: center;">Loading...</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Add Proxy Modal -->
    <div id="add-modal" class="modal">
        <div class="modal-content">
            <h2 style="margin-bottom: 20px;">Add New Proxy</h2>
            <form id="add-proxy-form">
                <div class="form-group">
                    <label>Service Name</label>
                    <input type="text" name="serviceName" required>
                </div>
                <div class="form-group">
                    <label>A Record (Subdomain)</label>
                    <input type="text" name="aRecord" required>
                </div>
                <div class="form-group">
                    <label>Backend IP</label>
                    <input type="text" name="ip" required>
                </div>
                <div class="form-group">
                    <label>Backend Port</label>
                    <input type="number" name="port" required>
                </div>
                <div class="form-group">
                    <label>
                        <input type="checkbox" name="useHTTPS"> Use HTTPS
                    </label>
                </div>
                <div style="display: flex; gap: 10px; justify-content: flex-end;">
                    <button type="button" class="btn-danger" onclick="closeAddModal()">Cancel</button>
                    <button type="submit" class="btn-success">Add Proxy</button>
                </div>
            </form>
        </div>
    </div>

    <script>
        // 페이지 로드 시 프록시 목록 가져오기
        window.addEventListener('load', loadProxies);

        async function loadProxies() {
            try {
                const response = await fetch('/api/proxies');
                const data = await response.json();

                const tbody = document.getElementById('proxy-list');

                if (data.proxies.length === 0) {
                    tbody.innerHTML = '<tr><td colspan="5" style="text-align: center;">No proxies configured</td></tr>';
                    return;
                }

                tbody.innerHTML = data.proxies.map(proxy => \`
                    <tr>
                        <td><strong>\${proxy.serverName}</strong></td>
                        <td>\${proxy.port}</td>
                        <td>\${proxy.backend}</td>
                        <td><span class="badge \${proxy.ssl ? 'badge-ssl' : 'badge-http'}">\${proxy.ssl ? 'HTTPS' : 'HTTP'}</span></td>
                        <td>
                            <button class="btn-danger" onclick="deleteProxy('\${proxy.filename}')">Delete</button>
                        </td>
                    </tr>
                \`).join('');
            } catch (error) {
                alert('Error loading proxies: ' + error.message);
            }
        }

        function showAddModal() {
            document.getElementById('add-modal').classList.add('active');
        }

        function closeAddModal() {
            document.getElementById('add-modal').classList.remove('active');
            document.getElementById('add-proxy-form').reset();
        }

        document.getElementById('add-proxy-form').addEventListener('submit', async (e) => {
            e.preventDefault();

            const formData = new FormData(e.target);
            const data = {
                serviceName: formData.get('serviceName'),
                aRecord: formData.get('aRecord'),
                ip: formData.get('ip'),
                port: formData.get('port'),
                useHTTPS: formData.get('useHTTPS') ? 'Y' : 'N'
            };

            try {
                const response = await fetch('/api/proxies', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                });

                const result = await response.json();

                if (result.success) {
                    alert('Proxy added successfully!');
                    closeAddModal();
                    loadProxies();
                } else {
                    alert('Error: ' + result.error);
                }
            } catch (error) {
                alert('Error adding proxy: ' + error.message);
            }
        });

        async function deleteProxy(filename) {
            if (!confirm('Are you sure you want to delete this proxy?')) return;

            try {
                const response = await fetch(\`/api/proxies/\${filename}\`, {
                    method: 'DELETE'
                });

                const result = await response.json();

                if (result.success) {
                    alert('Proxy deleted successfully!');
                    loadProxies();
                } else {
                    alert('Error: ' + result.error);
                }
            } catch (error) {
                alert('Error deleting proxy: ' + error.message);
            }
        }

        async function reloadNginx() {
            try {
                const response = await fetch('/api/reload', { method: 'POST' });
                const result = await response.json();

                if (result.success) {
                    alert('Nginx reloaded successfully!');
                } else {
                    alert('Error: ' + result.error);
                }
            } catch (error) {
                alert('Error reloading Nginx: ' + error.message);
            }
        }

        // 상태 확인 (5초마다)
        setInterval(async () => {
            try {
                const response = await fetch('/api/status');
                const status = await response.json();

                const statusText = document.getElementById('status-text');
                statusText.textContent = status.configValid ? 'Nginx Running' : 'Config Error';
            } catch (error) {
                console.error('Status check failed:', error);
            }
        }, 5000);
    </script>
</body>
</html>
    `);
});

// 서버 시작
app.listen(PORT, () => {
    console.log(`
╔════════════════════════════════════════════════════╗
║  🚀 Nginx Proxy Manager Web UI                    ║
║                                                    ║
║  🌐 URL: http://localhost:${PORT}                   ║
║  📂 Nginx Path: ${NGINX_PATH}                    ║
║  📋 Conf.d Path: ${CONF_D_PATH}           ║
║                                                    ║
║  ✅ Server is running...                          ║
╚════════════════════════════════════════════════════╝
    `);
});
