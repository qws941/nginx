/**
 * Nginx 프록시 웹 관리 UI - 고도화 버전
 *
 * 주요 개선사항:
 * - localhost 전용 바인딩 (보안 강화)
 * - 상세 에러 처리 및 로깅
 * - AD 사용자 표시 (읽기 전용)
 * - 백업/복구 기능
 * - 로그 조회 기능
 * - 실시간 모니터링
 * - 설정 검증 강화
 *
 * 사용법:
 *   node nginx-web-ui-enhanced.js
 *   브라우저에서 http://localhost:8080 접속
 *
 * 버전: 2.0.0
 * 날짜: 2025-10-20
 */

const express = require('express');
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 8080;
const NGINX_PATH = process.env.NGINX_PATH || 'C:\\nginx';
const CONF_D_PATH = path.join(NGINX_PATH, 'conf', 'conf.d');
const LOG_PATH = path.join(NGINX_PATH, 'logs');
const BACKUP_PATH = 'C:\\backup';

// 로깅 유틸리티
class Logger {
    static log(level, message, data = {}) {
        const timestamp = new Date().toISOString();
        const logEntry = {
            timestamp,
            level,
            message,
            ...data
        };
        console.log(`[${timestamp}] [${level}] ${message}`, data);

        // 로그 파일에도 기록 (옵션)
        try {
            const logFile = path.join(LOG_PATH, 'web-ui.log');
            fs.appendFileSync(logFile, JSON.stringify(logEntry) + '\n');
        } catch (err) {
            console.error('Failed to write log:', err);
        }
    }

    static info(message, data) { this.log('INFO', message, data); }
    static warn(message, data) { this.log('WARN', message, data); }
    static error(message, data) { this.log('ERROR', message, data); }
    static success(message, data) { this.log('SUCCESS', message, data); }
}

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// 요청 로깅 미들웨어
app.use((req, res, next) => {
    Logger.info('HTTP Request', {
        method: req.method,
        url: req.url,
        ip: req.ip
    });
    next();
});

// 에러 핸들링 미들웨어
app.use((err, req, res, next) => {
    Logger.error('Express Error', { error: err.message, stack: err.stack });
    res.status(500).json({
        success: false,
        error: err.message
    });
});

// ===========================
// Helper Functions
// ===========================

/**
 * PowerShell 명령 실행 (Promise 래퍼)
 */
function execPowerShell(command) {
    return new Promise((resolve, reject) => {
        exec(`powershell.exe -Command "${command.replace(/"/g, '\\"')}"`,
            { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 },
            (error, stdout, stderr) => {
                if (error) {
                    Logger.error('PowerShell Error', { command, error: error.message, stderr });
                    reject({ error: error.message, stderr });
                } else {
                    Logger.info('PowerShell Success', { command, output: stdout.substring(0, 200) });
                    resolve(stdout);
                }
            }
        );
    });
}

/**
 * Nginx 명령 실행
 */
function execNginx(args) {
    return new Promise((resolve, reject) => {
        const nginxExe = path.join(NGINX_PATH, 'nginx.exe');
        exec(`"${nginxExe}" ${args}`, (error, stdout, stderr) => {
            if (error) {
                Logger.error('Nginx Command Error', { args, error: error.message, stderr });
                reject({ error: error.message, stderr });
            } else {
                Logger.success('Nginx Command Success', { args, output: stderr || stdout });
                resolve(stderr || stdout);
            }
        });
    });
}

/**
 * 디렉토리 존재 확인 및 생성
 */
function ensureDirectory(dirPath) {
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
        Logger.info('Directory Created', { path: dirPath });
    }
}

// ===========================
// API 엔드포인트
// ===========================

/**
 * 시스템 정보 조회
 */
app.get('/api/system', async (req, res) => {
    try {
        const systemInfo = {
            hostname: os.hostname(),
            platform: os.platform(),
            arch: os.arch(),
            cpus: os.cpus().length,
            totalMemory: Math.round(os.totalmem() / 1024 / 1024 / 1024) + ' GB',
            freeMemory: Math.round(os.freemem() / 1024 / 1024 / 1024) + ' GB',
            uptime: Math.round(os.uptime() / 3600) + ' hours',
            nodeVersion: process.version,
            nginxPath: NGINX_PATH
        };

        // AD 정보 조회 (도메인 가입 여부)
        try {
            const adInfo = await execPowerShell(
                '(Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain'
            );
            systemInfo.domainJoined = adInfo.trim() === 'True';

            if (systemInfo.domainJoined) {
                const domain = await execPowerShell(
                    '(Get-WmiObject -Class Win32_ComputerSystem).Domain'
                );
                systemInfo.domain = domain.trim();
            }
        } catch (err) {
            Logger.warn('AD Info retrieval failed', { error: err.message });
            systemInfo.domainJoined = false;
        }

        res.json({ success: true, system: systemInfo });
    } catch (error) {
        Logger.error('System Info Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * 모든 프록시 설정 조회 (개선된 파싱)
 */
app.get('/api/proxies', (req, res) => {
    try {
        if (!fs.existsSync(CONF_D_PATH)) {
            Logger.warn('conf.d directory not found', { path: CONF_D_PATH });
            return res.json({ success: true, proxies: [] });
        }

        const files = fs.readdirSync(CONF_D_PATH);
        const confFiles = files.filter(f => f.endsWith('.conf'));
        const proxies = [];

        confFiles.forEach(file => {
            try {
                const filePath = path.join(CONF_D_PATH, file);
                const content = fs.readFileSync(filePath, 'utf8');
                const stats = fs.statSync(filePath);

                // 설정 파싱 (개선된 정규식)
                const serverNameMatch = content.match(/server_name\s+([^;]+);/);
                const listenMatch = content.match(/listen\s+(\d+)\s*(ssl)?/);
                const proxyPassMatch = content.match(/proxy_pass\s+([^;]+);/);
                const sslCertMatch = content.match(/ssl_certificate\s+([^;]+);/);

                proxies.push({
                    filename: file,
                    serverName: serverNameMatch ? serverNameMatch[1].trim() : 'unknown',
                    port: listenMatch ? parseInt(listenMatch[1]) : 80,
                    backend: proxyPassMatch ? proxyPassMatch[1].trim() : 'unknown',
                    ssl: content.includes('ssl_certificate'),
                    sslCert: sslCertMatch ? sslCertMatch[1].trim() : null,
                    size: Math.round(stats.size / 1024 * 100) / 100 + ' KB',
                    modified: stats.mtime.toISOString()
                });
            } catch (err) {
                Logger.error('Proxy parsing error', { file, error: err.message });
            }
        });

        Logger.success('Proxies loaded', { count: proxies.length });
        res.json({ success: true, proxies });
    } catch (error) {
        Logger.error('Proxies API Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * 새 프록시 설정 추가 (검증 강화)
 */
app.post('/api/proxies', async (req, res) => {
    try {
        const { serviceName, aRecord, ip, port, useHTTPS, customPath, description } = req.body;

        // 입력 검증
        if (!serviceName || !aRecord || !ip || !port) {
            Logger.warn('Invalid proxy input', { body: req.body });
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: serviceName, aRecord, ip, port'
            });
        }

        // IP 주소 형식 검증
        const ipRegex = /^(\d{1,3}\.){3}\d{1,3}$/;
        if (!ipRegex.test(ip)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid IP address format'
            });
        }

        // 포트 범위 검증
        if (port < 1 || port > 65535) {
            return res.status(400).json({
                success: false,
                error: 'Port must be between 1 and 65535'
            });
        }

        Logger.info('Adding new proxy', { serviceName, aRecord, ip, port });

        // CSV에 추가
        const csvPath = path.join(NGINX_PATH, 'services.csv');
        ensureDirectory(path.dirname(csvPath));

        if (!fs.existsSync(csvPath)) {
            fs.writeFileSync(csvPath, '서비스명,ARecord,IP,Port,UseHTTPS,CustomPath,비고\n', 'utf8');
        }

        const csvLine = `${serviceName},${aRecord},${ip},${port},${useHTTPS ? 'Y' : 'N'},${customPath || ''},${description || ''}\n`;
        fs.appendFileSync(csvPath, csvLine, 'utf8');

        // Nginx 설정 생성 (conf.d에 직접 생성)
        ensureDirectory(CONF_D_PATH);
        const confFilename = `${serviceName.toLowerCase().replace(/\s+/g, '-')}.conf`;
        const confPath = path.join(CONF_D_PATH, confFilename);

        const confContent = `
# ${serviceName} - ${description || 'Reverse Proxy'}
# Created: ${new Date().toISOString()}
# Backend: ${ip}:${port}

server {
    listen 80;
    server_name ${aRecord};

    location ${customPath || '/'} {
        proxy_pass http://${ip}:${port};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
`;

        fs.writeFileSync(confPath, confContent, 'utf8');
        Logger.success('Proxy config created', { filename: confFilename });

        // Nginx 설정 테스트
        try {
            await execNginx('-t');
        } catch (testError) {
            // 설정 오류 시 롤백
            fs.unlinkSync(confPath);
            Logger.error('Config test failed, rolled back', testError);
            return res.status(500).json({
                success: false,
                error: 'Nginx config test failed: ' + testError.stderr
            });
        }

        // Nginx 재로드
        await execNginx('-s reload');

        Logger.success('Proxy added successfully', { serviceName });
        res.json({
            success: true,
            message: 'Proxy added successfully',
            filename: confFilename
        });
    } catch (error) {
        Logger.error('Add Proxy Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * 프록시 설정 삭제 (백업 포함)
 */
app.delete('/api/proxies/:filename', async (req, res) => {
    try {
        const filename = req.params.filename;

        if (!filename.endsWith('.conf')) {
            return res.status(400).json({ success: false, error: 'Invalid filename' });
        }

        const filePath = path.join(CONF_D_PATH, filename);

        if (!fs.existsSync(filePath)) {
            return res.status(404).json({ success: false, error: 'File not found' });
        }

        Logger.info('Deleting proxy', { filename });

        // 백업 생성
        ensureDirectory(BACKUP_PATH);
        const backupFilename = `${filename}.${Date.now()}.backup`;
        const backupPath = path.join(BACKUP_PATH, backupFilename);
        fs.copyFileSync(filePath, backupPath);
        Logger.info('Backup created', { backup: backupFilename });

        // 파일 삭제
        fs.unlinkSync(filePath);

        // Nginx 재로드
        await execNginx('-s reload');

        Logger.success('Proxy deleted', { filename });
        res.json({
            success: true,
            message: 'Proxy deleted successfully',
            backup: backupFilename
        });
    } catch (error) {
        Logger.error('Delete Proxy Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * Nginx 상태 확인 (상세)
 */
app.get('/api/status', async (req, res) => {
    try {
        // 설정 테스트
        let configValid = false;
        let configMessage = '';
        try {
            const testResult = await execNginx('-t');
            configValid = true;
            configMessage = testResult;
        } catch (err) {
            configMessage = err.stderr || err.error;
        }

        // 서비스 상태 (Windows)
        let serviceRunning = false;
        try {
            const serviceStatus = await execPowerShell(
                '(Get-Service -Name nginx -ErrorAction SilentlyContinue).Status'
            );
            serviceRunning = serviceStatus.trim() === 'Running';
        } catch (err) {
            Logger.warn('Service status check failed', { error: err.message });
        }

        // 프로세스 정보
        let processInfo = {};
        try {
            const processes = await execPowerShell(
                'Get-Process -Name nginx -ErrorAction SilentlyContinue | Select-Object Id, WorkingSet64 | ConvertTo-Json'
            );
            const parsed = JSON.parse(processes);
            if (Array.isArray(parsed)) {
                processInfo.count = parsed.length;
                processInfo.memory = Math.round(parsed.reduce((sum, p) => sum + p.WorkingSet64, 0) / 1024 / 1024) + ' MB';
            } else if (parsed.Id) {
                processInfo.count = 1;
                processInfo.memory = Math.round(parsed.WorkingSet64 / 1024 / 1024) + ' MB';
            }
        } catch (err) {
            Logger.warn('Process info retrieval failed', { error: err.message });
        }

        const status = {
            configValid,
            configMessage,
            serviceRunning,
            processInfo,
            timestamp: new Date().toISOString()
        };

        res.json({ success: true, status });
    } catch (error) {
        Logger.error('Status Check Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * Nginx 재로드
 */
app.post('/api/reload', async (req, res) => {
    try {
        Logger.info('Reloading Nginx');

        // 먼저 설정 테스트
        await execNginx('-t');

        // 재로드 실행
        await execNginx('-s reload');

        Logger.success('Nginx reloaded successfully');
        res.json({ success: true, message: 'Nginx reloaded successfully' });
    } catch (error) {
        Logger.error('Reload Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * 로그 조회
 */
app.get('/api/logs/:type', async (req, res) => {
    try {
        const type = req.params.type; // access or error
        const lines = parseInt(req.query.lines) || 100;

        if (!['access', 'error'].includes(type)) {
            return res.status(400).json({ success: false, error: 'Invalid log type' });
        }

        const logFile = path.join(LOG_PATH, `${type}.log`);

        if (!fs.existsSync(logFile)) {
            return res.json({ success: true, logs: [], message: 'Log file not found' });
        }

        // PowerShell로 마지막 N줄 가져오기
        const logs = await execPowerShell(
            `Get-Content "${logFile}" -Tail ${lines} -Encoding UTF8`
        );

        const logLines = logs.split('\n').filter(line => line.trim());

        res.json({
            success: true,
            logs: logLines,
            count: logLines.length,
            file: logFile
        });
    } catch (error) {
        Logger.error('Logs API Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * 백업 생성
 */
app.post('/api/backup', async (req, res) => {
    try {
        Logger.info('Creating backup');

        ensureDirectory(BACKUP_PATH);

        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupDir = path.join(BACKUP_PATH, `nginx-config-${timestamp}`);

        // 백업 디렉토리 생성
        fs.mkdirSync(backupDir, { recursive: true });

        // 설정 파일 복사
        const confSrc = path.join(NGINX_PATH, 'conf');
        const confDst = path.join(backupDir, 'conf');
        await execPowerShell(`Copy-Item -Recurse -Path "${confSrc}" -Destination "${confDst}"`);

        // CSV 파일 복사
        const csvPath = path.join(NGINX_PATH, 'services.csv');
        if (fs.existsSync(csvPath)) {
            fs.copyFileSync(csvPath, path.join(backupDir, 'services.csv'));
        }

        // 압축
        const zipPath = `${backupDir}.zip`;
        await execPowerShell(
            `Compress-Archive -Path "${backupDir}" -DestinationPath "${zipPath}"`
        );

        // 임시 폴더 삭제
        await execPowerShell(`Remove-Item -Recurse -Force "${backupDir}"`);

        Logger.success('Backup created', { backup: zipPath });

        res.json({
            success: true,
            message: 'Backup created successfully',
            backup: zipPath,
            size: Math.round(fs.statSync(zipPath).size / 1024) + ' KB'
        });
    } catch (error) {
        Logger.error('Backup Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * 백업 목록 조회
 */
app.get('/api/backups', async (req, res) => {
    try {
        if (!fs.existsSync(BACKUP_PATH)) {
            return res.json({ success: true, backups: [] });
        }

        const files = fs.readdirSync(BACKUP_PATH);
        const backups = files
            .filter(f => f.startsWith('nginx-config-') && f.endsWith('.zip'))
            .map(f => {
                const filePath = path.join(BACKUP_PATH, f);
                const stats = fs.statSync(filePath);
                return {
                    filename: f,
                    path: filePath,
                    size: Math.round(stats.size / 1024) + ' KB',
                    created: stats.mtime.toISOString()
                };
            })
            .sort((a, b) => new Date(b.created) - new Date(a.created));

        res.json({ success: true, backups });
    } catch (error) {
        Logger.error('Backups List Error', { error: error.message });
        res.status(500).json({ success: false, error: error.message });
    }
});

// ===========================
// 웹 UI (HTML) - 고도화
// ===========================

app.get('/', (req, res) => {
    res.send(`
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nginx Proxy Manager - Enhanced v2.0</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        header {
            background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            color: white;
            padding: 20px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        header h1 { font-size: 24px; display: flex; align-items: center; gap: 10px; }
        .version { font-size: 12px; background: #3498db; padding: 4px 8px; border-radius: 4px; }
        .status-panel {
            display: flex;
            gap: 20px;
            align-items: center;
        }
        .status-item {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 5px;
        }
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #2ecc71;
            animation: pulse 2s infinite;
        }
        .status-dot.error { background: #e74c3c; }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(1.1); }
        }
        .tabs {
            display: flex;
            background: #ecf0f1;
            border-bottom: 2px solid #bdc3c7;
        }
        .tab {
            padding: 15px 30px;
            cursor: pointer;
            border: none;
            background: transparent;
            font-size: 14px;
            font-weight: 600;
            color: #7f8c8d;
            transition: all 0.3s;
        }
        .tab:hover { background: #d5dbdb; }
        .tab.active {
            background: white;
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
        }
        .content { padding: 30px; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .actions {
            display: flex;
            gap: 15px;
            margin-bottom: 30px;
            flex-wrap: wrap;
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
        .btn-primary { background: #3498db; color: white; }
        .btn-primary:hover { background: #2980b9; transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0,0,0,0.2); }
        .btn-success { background: #2ecc71; color: white; }
        .btn-success:hover { background: #27ae60; }
        .btn-danger { background: #e74c3c; color: white; }
        .btn-danger:hover { background: #c0392b; }
        .btn-warning { background: #f39c12; color: white; }
        .btn-warning:hover { background: #e67e22; }
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
        tr:hover { background: #f8f9fa; }
        .badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
        }
        .badge-ssl { background: #2ecc71; color: white; }
        .badge-http { background: #95a5a6; color: white; }
        .badge-running { background: #2ecc71; color: white; }
        .badge-stopped { background: #e74c3c; color: white; }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .info-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #3498db;
        }
        .info-card h3 {
            font-size: 14px;
            color: #7f8c8d;
            margin-bottom: 10px;
        }
        .info-card p {
            font-size: 18px;
            font-weight: 600;
            color: #2c3e50;
        }
        .log-viewer {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 400px;
            overflow-y: auto;
        }
        .log-line {
            padding: 4px 0;
            border-bottom: 1px solid #34495e;
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
            max-height: 80vh;
            overflow-y: auto;
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
        .form-group input, .form-group textarea {
            width: 100%;
            padding: 10px;
            border: 2px solid #ecf0f1;
            border-radius: 5px;
            font-size: 14px;
        }
        .form-group input:focus, .form-group textarea:focus {
            outline: none;
            border-color: #3498db;
        }
        .alert {
            padding: 15px 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert-error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .alert-info { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>
                🚀 Nginx Proxy Manager
                <span class="version">v2.0 Enhanced</span>
            </h1>
            <div class="status-panel">
                <div class="status-item">
                    <div class="status-dot" id="nginx-status"></div>
                    <span id="nginx-text" style="font-size: 12px;">Checking...</span>
                </div>
                <div class="status-item">
                    <span style="font-size: 12px;">🖥️ <span id="hostname">-</span></span>
                </div>
            </div>
        </header>

        <div class="tabs">
            <button class="tab active" onclick="switchTab('dashboard')">📊 Dashboard</button>
            <button class="tab" onclick="switchTab('proxies')">🔀 Proxies</button>
            <button class="tab" onclick="switchTab('logs')">📜 Logs</button>
            <button class="tab" onclick="switchTab('backup')">💾 Backup</button>
            <button class="tab" onclick="switchTab('system')">⚙️ System</button>
        </div>

        <div class="content">
            <!-- Dashboard Tab -->
            <div id="tab-dashboard" class="tab-content active">
                <h2 style="margin-bottom: 20px;">System Overview</h2>
                <div id="alert-container"></div>
                <div class="info-grid" id="system-info">
                    <div class="info-card">
                        <h3>Nginx Status</h3>
                        <p id="dash-nginx-status">Loading...</p>
                    </div>
                    <div class="info-card">
                        <h3>Total Proxies</h3>
                        <p id="dash-proxy-count">0</p>
                    </div>
                    <div class="info-card">
                        <h3>Memory Usage</h3>
                        <p id="dash-memory">-</p>
                    </div>
                    <div class="info-card">
                        <h3>Domain Status</h3>
                        <p id="dash-domain">-</p>
                    </div>
                </div>

                <div class="actions">
                    <button class="btn-success" onclick="reloadNginx()">🔄 Reload Nginx</button>
                    <button class="btn-warning" onclick="createBackup()">💾 Create Backup</button>
                    <button class="btn-primary" onclick="refreshDashboard()">🔍 Refresh</button>
                </div>
            </div>

            <!-- Proxies Tab -->
            <div id="tab-proxies" class="tab-content">
                <h2 style="margin-bottom: 20px;">Proxy Configuration</h2>
                <div class="actions">
                    <button class="btn-primary" onclick="showAddModal()">➕ Add Proxy</button>
                    <button class="btn-primary" onclick="loadProxies()">🔍 Refresh</button>
                </div>

                <table id="proxy-table">
                    <thead>
                        <tr>
                            <th>Domain</th>
                            <th>Port</th>
                            <th>Backend</th>
                            <th>SSL</th>
                            <th>Size</th>
                            <th>Modified</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody id="proxy-list">
                        <tr><td colspan="7" style="text-align: center;">Loading...</td></tr>
                    </tbody>
                </table>
            </div>

            <!-- Logs Tab -->
            <div id="tab-logs" class="tab-content">
                <h2 style="margin-bottom: 20px;">Log Viewer</h2>
                <div class="actions">
                    <button class="btn-primary" onclick="loadLogs('access')">📄 Access Log</button>
                    <button class="btn-danger" onclick="loadLogs('error')">⚠️ Error Log</button>
                    <button class="btn-primary" onclick="refreshCurrentLog()">🔄 Refresh</button>
                </div>
                <div class="log-viewer" id="log-content">
                    <div>Select a log type to view...</div>
                </div>
            </div>

            <!-- Backup Tab -->
            <div id="tab-backup" class="tab-content">
                <h2 style="margin-bottom: 20px;">Backup Management</h2>
                <div class="actions">
                    <button class="btn-warning" onclick="createBackup()">💾 Create Backup</button>
                    <button class="btn-primary" onclick="loadBackups()">🔍 Refresh</button>
                </div>

                <table>
                    <thead>
                        <tr>
                            <th>Filename</th>
                            <th>Size</th>
                            <th>Created</th>
                        </tr>
                    </thead>
                    <tbody id="backup-list">
                        <tr><td colspan="3" style="text-align: center;">Loading...</td></tr>
                    </tbody>
                </table>
            </div>

            <!-- System Tab -->
            <div id="tab-system" class="tab-content">
                <h2 style="margin-bottom: 20px;">System Information</h2>
                <div class="info-grid" id="detailed-system-info">
                    <div class="info-card">
                        <h3>Loading...</h3>
                        <p>Please wait...</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Add Proxy Modal -->
    <div id="add-modal" class="modal">
        <div class="modal-content">
            <h2 style="margin-bottom: 20px;">Add New Proxy</h2>
            <form id="add-proxy-form">
                <div class="form-group">
                    <label>Service Name *</label>
                    <input type="text" name="serviceName" required placeholder="e.g., My Application">
                </div>
                <div class="form-group">
                    <label>A Record (Subdomain) *</label>
                    <input type="text" name="aRecord" required placeholder="e.g., app.company.local">
                </div>
                <div class="form-group">
                    <label>Backend IP *</label>
                    <input type="text" name="ip" required placeholder="e.g., 192.168.1.100">
                </div>
                <div class="form-group">
                    <label>Backend Port *</label>
                    <input type="number" name="port" required placeholder="e.g., 3000">
                </div>
                <div class="form-group">
                    <label>Custom Path</label>
                    <input type="text" name="customPath" placeholder="e.g., /api (leave empty for /)">
                </div>
                <div class="form-group">
                    <label>Description</label>
                    <textarea name="description" rows="3" placeholder="Optional notes"></textarea>
                </div>
                <div class="form-group">
                    <label>
                        <input type="checkbox" name="useHTTPS"> Use HTTPS (requires SSL certificate)
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
        // Global state
        let currentLogType = null;

        // 페이지 로드
        window.addEventListener('load', () => {
            loadSystemInfo();
            loadProxies();
            loadBackups();
            refreshDashboard();
            startStatusMonitoring();
        });

        // Tab switching
        function switchTab(tabName) {
            document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));

            event.target.classList.add('active');
            document.getElementById('tab-' + tabName).classList.add('active');

            // Load data for specific tabs
            if (tabName === 'system') loadSystemInfo();
            if (tabName === 'backup') loadBackups();
        }

        // System info
        async function loadSystemInfo() {
            try {
                const response = await fetch('/api/system');
                const data = await response.json();

                if (data.success) {
                    const sys = data.system;
                    document.getElementById('hostname').textContent = sys.hostname;

                    // Dashboard
                    document.getElementById('dash-memory').textContent = sys.freeMemory + ' / ' + sys.totalMemory;
                    document.getElementById('dash-domain').textContent = sys.domainJoined ?
                        '✅ Joined: ' + sys.domain : '❌ Not Joined';

                    // System tab
                    const systemGrid = document.getElementById('detailed-system-info');
                    systemGrid.innerHTML = Object.entries(sys).map(([key, value]) => \`
                        <div class="info-card">
                            <h3>\${key}</h3>
                            <p>\${value}</p>
                        </div>
                    \`).join('');
                }
            } catch (error) {
                console.error('System info error:', error);
            }
        }

        // Proxies
        async function loadProxies() {
            try {
                const response = await fetch('/api/proxies');
                const data = await response.json();

                const tbody = document.getElementById('proxy-list');

                if (data.proxies.length === 0) {
                    tbody.innerHTML = '<tr><td colspan="7" style="text-align: center;">No proxies configured</td></tr>';
                    document.getElementById('dash-proxy-count').textContent = '0';
                    return;
                }

                tbody.innerHTML = data.proxies.map(proxy => \`
                    <tr>
                        <td><strong>\${proxy.serverName}</strong></td>
                        <td>\${proxy.port}</td>
                        <td><code>\${proxy.backend}</code></td>
                        <td><span class="badge \${proxy.ssl ? 'badge-ssl' : 'badge-http'}">\${proxy.ssl ? 'HTTPS' : 'HTTP'}</span></td>
                        <td>\${proxy.size}</td>
                        <td>\${new Date(proxy.modified).toLocaleString()}</td>
                        <td>
                            <button class="btn-danger" onclick="deleteProxy('\${proxy.filename}')" style="padding: 8px 16px;">Delete</button>
                        </td>
                    </tr>
                \`).join('');

                document.getElementById('dash-proxy-count').textContent = data.proxies.length;
            } catch (error) {
                showAlert('Error loading proxies: ' + error.message, 'error');
            }
        }

        // Status monitoring
        async function checkStatus() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();

                if (data.success) {
                    const status = data.status;
                    const dot = document.getElementById('nginx-status');
                    const text = document.getElementById('nginx-text');
                    const dashStatus = document.getElementById('dash-nginx-status');

                    if (status.configValid && status.serviceRunning) {
                        dot.className = 'status-dot';
                        text.textContent = 'Running';
                        dashStatus.innerHTML = '<span class="badge badge-running">Running</span>';
                    } else {
                        dot.className = 'status-dot error';
                        text.textContent = 'Error';
                        dashStatus.innerHTML = '<span class="badge badge-stopped">Stopped</span>';
                    }

                    if (status.processInfo.memory) {
                        document.getElementById('dash-memory').textContent = status.processInfo.memory;
                    }
                }
            } catch (error) {
                console.error('Status check failed:', error);
            }
        }

        function startStatusMonitoring() {
            checkStatus();
            setInterval(checkStatus, 5000);
        }

        // Dashboard refresh
        async function refreshDashboard() {
            await Promise.all([
                loadSystemInfo(),
                checkStatus(),
                loadProxies()
            ]);
            showAlert('Dashboard refreshed', 'success');
            setTimeout(() => document.getElementById('alert-container').innerHTML = '', 2000);
        }

        // Logs
        async function loadLogs(type) {
            currentLogType = type;
            try {
                const response = await fetch(\`/api/logs/\${type}?lines=100\`);
                const data = await response.json();

                const logContent = document.getElementById('log-content');

                if (data.logs.length === 0) {
                    logContent.innerHTML = '<div>No logs found</div>';
                    return;
                }

                logContent.innerHTML = data.logs.map(line =>
                    \`<div class="log-line">\${line}</div>\`
                ).join('');

                // Auto-scroll to bottom
                logContent.scrollTop = logContent.scrollHeight;
            } catch (error) {
                showAlert('Error loading logs: ' + error.message, 'error');
            }
        }

        function refreshCurrentLog() {
            if (currentLogType) {
                loadLogs(currentLogType);
            } else {
                showAlert('Please select a log type first', 'info');
            }
        }

        // Backups
        async function loadBackups() {
            try {
                const response = await fetch('/api/backups');
                const data = await response.json();

                const tbody = document.getElementById('backup-list');

                if (data.backups.length === 0) {
                    tbody.innerHTML = '<tr><td colspan="3" style="text-align: center;">No backups found</td></tr>';
                    return;
                }

                tbody.innerHTML = data.backups.map(backup => \`
                    <tr>
                        <td><code>\${backup.filename}</code></td>
                        <td>\${backup.size}</td>
                        <td>\${new Date(backup.created).toLocaleString()}</td>
                    </tr>
                \`).join('');
            } catch (error) {
                showAlert('Error loading backups: ' + error.message, 'error');
            }
        }

        async function createBackup() {
            if (!confirm('Create a new backup? This may take a moment.')) return;

            try {
                const response = await fetch('/api/backup', { method: 'POST' });
                const result = await response.json();

                if (result.success) {
                    showAlert('Backup created: ' + result.size, 'success');
                    loadBackups();
                } else {
                    showAlert('Backup failed: ' + result.error, 'error');
                }
            } catch (error) {
                showAlert('Error creating backup: ' + error.message, 'error');
            }
        }

        // Modal
        function showAddModal() {
            document.getElementById('add-modal').classList.add('active');
        }

        function closeAddModal() {
            document.getElementById('add-modal').classList.remove('active');
            document.getElementById('add-proxy-form').reset();
        }

        // Add proxy
        document.getElementById('add-proxy-form').addEventListener('submit', async (e) => {
            e.preventDefault();

            const formData = new FormData(e.target);
            const data = {
                serviceName: formData.get('serviceName'),
                aRecord: formData.get('aRecord'),
                ip: formData.get('ip'),
                port: formData.get('port'),
                useHTTPS: formData.get('useHTTPS') ? 'Y' : 'N',
                customPath: formData.get('customPath'),
                description: formData.get('description')
            };

            try {
                const response = await fetch('/api/proxies', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                });

                const result = await response.json();

                if (result.success) {
                    showAlert('Proxy added successfully!', 'success');
                    closeAddModal();
                    loadProxies();
                } else {
                    showAlert('Error: ' + result.error, 'error');
                }
            } catch (error) {
                showAlert('Error adding proxy: ' + error.message, 'error');
            }
        });

        // Delete proxy
        async function deleteProxy(filename) {
            if (!confirm(\`Delete proxy "\${filename}"? A backup will be created.\`)) return;

            try {
                const response = await fetch(\`/api/proxies/\${filename}\`, {
                    method: 'DELETE'
                });

                const result = await response.json();

                if (result.success) {
                    showAlert('Proxy deleted successfully!', 'success');
                    loadProxies();
                } else {
                    showAlert('Error: ' + result.error, 'error');
                }
            } catch (error) {
                showAlert('Error deleting proxy: ' + error.message, 'error');
            }
        }

        // Reload Nginx
        async function reloadNginx() {
            if (!confirm('Reload Nginx configuration?')) return;

            try {
                const response = await fetch('/api/reload', { method: 'POST' });
                const result = await response.json();

                if (result.success) {
                    showAlert('Nginx reloaded successfully!', 'success');
                    checkStatus();
                } else {
                    showAlert('Error: ' + result.error, 'error');
                }
            } catch (error) {
                showAlert('Error reloading Nginx: ' + error.message, 'error');
            }
        }

        // Alert helper
        function showAlert(message, type) {
            const container = document.getElementById('alert-container');
            const alertClass = 'alert-' + type;
            container.innerHTML = \`<div class="alert \${alertClass}">\${message}</div>\`;

            setTimeout(() => {
                container.innerHTML = '';
            }, 5000);
        }
    </script>
</body>
</html>
    `);
});

// 서버 시작 - localhost 전용 바인딩 (보안 강화)
app.listen(PORT, '127.0.0.1', () => {
    Logger.success('Server Started', {
        url: `http://127.0.0.1:${PORT}`,
        nginxPath: NGINX_PATH,
        confDPath: CONF_D_PATH,
        version: '2.0.0'
    });

    console.log(`
╔════════════════════════════════════════════════════════════╗
║  🚀 Nginx Proxy Manager Web UI - Enhanced v2.0           ║
║                                                            ║
║  🌐 URL: http://127.0.0.1:${PORT}                           ║
║  🔒 Security: localhost only (127.0.0.1)                  ║
║  📂 Nginx Path: ${NGINX_PATH.padEnd(36)} ║
║  📋 Conf.d Path: ${CONF_D_PATH}    ║
║  💾 Backup Path: ${BACKUP_PATH.padEnd(36)} ║
║                                                            ║
║  ✅ Server is running...                                  ║
║  📊 Features: Dashboard, Logs, Backup, AD Info           ║
╚════════════════════════════════════════════════════════════╝
    `);
});

// Graceful shutdown
process.on('SIGINT', () => {
    Logger.info('Shutting down server...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    Logger.info('Shutting down server...');
    process.exit(0);
});
