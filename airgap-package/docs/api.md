# API 문서

## Node.js 웹 UI REST API

**Base URL**: `http://localhost:8080`

**인증**: 없음 (localhost 전용)

---

## API 엔드포인트

### 1. 프록시 목록 조회

**GET** `/api/proxies`

프록시 설정 목록을 반환합니다.

**응답 예시**:
```json
{
  "success": true,
  "data": [
    {
      "id": "proxy-001",
      "domain": "app.company.local",
      "upstream_host": "192.168.1.100",
      "upstream_port": 3000,
      "ssl_enabled": true,
      "created_at": "2025-10-20T10:30:00Z"
    }
  ],
  "count": 1
}
```

---

### 2. 프록시 추가

**POST** `/api/proxies`

새 프록시 설정을 추가합니다.

**요청 본문**:
```json
{
  "domain": "app.company.local",
  "upstream_host": "192.168.1.100",
  "upstream_port": 3000,
  "ssl_enabled": true,
  "ssl_cert_path": "C:\\nginx\\ssl\\app.crt",
  "ssl_key_path": "C:\\nginx\\ssl\\app.key"
}
```

**응답 예시**:
```json
{
  "success": true,
  "message": "프록시가 추가되었습니다",
  "data": {
    "id": "proxy-002",
    "config_file": "C:\\nginx\\conf\\conf.d\\app.company.local.conf"
  }
}
```

**에러 응답**:
```json
{
  "success": false,
  "error": "도메인이 이미 존재합니다"
}
```

---

### 3. 프록시 수정

**PUT** `/api/proxies/:id`

기존 프록시 설정을 수정합니다.

**요청 본문**:
```json
{
  "upstream_host": "192.168.1.200",
  "upstream_port": 8080
}
```

**응답 예시**:
```json
{
  "success": true,
  "message": "프록시가 수정되었습니다"
}
```

---

### 4. 프록시 삭제

**DELETE** `/api/proxies/:id`

프록시 설정을 삭제합니다.

**응답 예시**:
```json
{
  "success": true,
  "message": "프록시가 삭제되었습니다"
}
```

---

### 5. Nginx 상태 확인

**GET** `/api/status`

Nginx 서비스 상태를 확인합니다.

**응답 예시**:
```json
{
  "success": true,
  "data": {
    "service_status": "Running",
    "uptime": "3 days 5 hours",
    "active_connections": 42,
    "requests_per_second": 150.5,
    "version": "nginx/1.24.0"
  }
}
```

---

### 6. Nginx 재시작

**POST** `/api/restart`

Nginx 서비스를 재시작합니다.

**응답 예시**:
```json
{
  "success": true,
  "message": "Nginx가 재시작되었습니다",
  "restart_time": "2025-10-20T15:30:45Z"
}
```

---

### 7. 설정 검증

**POST** `/api/validate`

Nginx 설정 문법을 검증합니다.

**응답 예시**:
```json
{
  "success": true,
  "message": "설정이 유효합니다",
  "details": "nginx: configuration file C:\\nginx\\conf\\nginx.conf test is successful"
}
```

**에러 응답**:
```json
{
  "success": false,
  "error": "설정 오류",
  "details": "nginx: [emerg] invalid number of arguments in \"server_name\" directive in C:\\nginx\\conf\\conf.d\\app.conf:10"
}
```

---

### 8. 로그 조회

**GET** `/api/logs?type=access&lines=100`

Nginx 로그를 조회합니다.

**쿼리 파라미터**:
- `type`: `access` 또는 `error`
- `lines`: 조회할 라인 수 (기본값: 100, 최대: 1000)

**응답 예시**:
```json
{
  "success": true,
  "data": {
    "type": "access",
    "lines": [
      "192.168.1.50 - - [20/Oct/2025:15:30:00 +0900] \"GET /api/health HTTP/1.1\" 200 15",
      "192.168.1.51 - - [20/Oct/2025:15:30:05 +0900] \"POST /api/data HTTP/1.1\" 201 234"
    ],
    "total_lines": 2
  }
}
```

---

## PowerShell 스크립트 인터페이스

### add-proxy.ps1

프록시를 추가합니다.

**사용법**:
```powershell
.\add-proxy.ps1 -DomainName "app.company.local" `
                -UpstreamHost "192.168.1.100" `
                -UpstreamPort 3000 `
                -EnableSSL `
                -SSLCertPath "C:\nginx\ssl\app.crt" `
                -SSLKeyPath "C:\nginx\ssl\app.key"
```

**파라미터**:
- `-DomainName` (필수): 도메인 이름
- `-UpstreamHost` (필수): 업스트림 서버 IP
- `-UpstreamPort` (필수): 업스트림 포트
- `-EnableSSL` (선택): SSL 활성화
- `-SSLCertPath` (선택): SSL 인증서 경로
- `-SSLKeyPath` (선택): SSL 키 경로

---

### remove-proxy.ps1

프록시를 삭제합니다.

**사용법**:
```powershell
.\remove-proxy.ps1 -DomainName "app.company.local"
```

---

### restart-nginx.ps1

Nginx 서비스를 재시작합니다.

**사용법**:
```powershell
.\restart-nginx.ps1
```

---

### check-nginx.ps1

Nginx 상태를 확인합니다.

**사용법**:
```powershell
.\check-nginx.ps1 -Detailed
```

**출력 예시**:
```
✓ Nginx 서비스: Running
✓ 프로세스 수: 4
✓ 메모리 사용량: 45 MB
✓ 활성 연결: 42
✓ 포트 80 리스닝: 정상
✓ 포트 443 리스닝: 정상
```

---

## Zoraxy GUI 인터페이스

Zoraxy는 REST API 대신 GUI를 제공합니다.

**실행 방법**:
```powershell
C:\installers\zoraxy_windows_amd64.exe
```

**접속**:
- URL: `http://localhost:8000`
- 기본 계정: `admin` / `admin`

**주요 기능**:
1. 프록시 규칙 추가/수정/삭제
2. SSL 인증서 관리
3. 로그 실시간 모니터링
4. 성능 통계 대시보드

---

## CSV 파일 형식

프록시 설정을 CSV 파일로 일괄 관리할 수 있습니다.

**파일**: `configs/services.csv`

**형식**:
```csv
domain,upstream_host,upstream_port,ssl_enabled,ssl_cert_path,ssl_key_path
app.company.local,192.168.1.100,3000,true,C:\nginx\ssl\app.crt,C:\nginx\ssl\app.key
dashboard.company.local,192.168.1.101,8080,false,,
api.company.local,192.168.1.102,5000,true,C:\nginx\ssl\api.crt,C:\nginx\ssl\api.key
```

**일괄 적용**:
```powershell
.\import-proxies.ps1 -CSVPath "configs\services.csv"
```

---

## Nginx 설정 파일 형식

수동으로 설정 파일을 편집할 수도 있습니다.

**위치**: `C:\nginx\conf\conf.d\{domain}.conf`

**예시**: `app.company.local.conf`
```nginx
server {
    listen 80;
    server_name app.company.local;

    # HTTPS로 리다이렉트
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.company.local;

    # SSL 설정
    ssl_certificate C:/nginx/ssl/app.crt;
    ssl_certificate_key C:/nginx/ssl/app.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 프록시 설정
    location / {
        proxy_pass http://192.168.1.100:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 타임아웃 설정
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 로그
    access_log C:/nginx/logs/app.company.local-access.log;
    error_log C:/nginx/logs/app.company.local-error.log;
}
```

---

## 에러 코드

| 코드 | 의미 | 해결 방법 |
|------|------|----------|
| `ERR_DOMAIN_EXISTS` | 도메인 중복 | 다른 도메인 사용 또는 기존 프록시 삭제 |
| `ERR_INVALID_CONFIG` | 설정 오류 | nginx -t 명령어로 상세 확인 |
| `ERR_SERVICE_DOWN` | 서비스 중단 | Nginx 서비스 재시작 |
| `ERR_UPSTREAM_UNREACHABLE` | 업스트림 접근 불가 | 업스트림 서버 상태 확인 |
| `ERR_SSL_CERT_INVALID` | SSL 인증서 오류 | 인증서 경로 및 유효성 확인 |

---

## 참고 문서

- [아키텍처](architecture.md)
- [배포 가이드](deployment.md)
- [문제 해결](troubleshooting.md)
