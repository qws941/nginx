# 아키텍처 문서

## 프로젝트 개요

**Windows 에어갭 환경용 Nginx 리버스 프록시 통합 설치 패키지**

오프라인 Windows Server 환경에서 Nginx 기반 리버스 프록시를 완전 자동 설치하고 관리하기 위한 통합 솔루션입니다.

---

## 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│ Windows Server (에어갭 환경)                                 │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Nginx       │  │ Node.js      │  │ Active       │       │
│  │ 1.24.0      │  │ v20.11.0     │  │ Directory    │       │
│  │             │  │              │  │              │       │
│  │ Port: 80    │  │ Web UI:      │  │ LDAP Auth    │       │
│  │       443   │  │ 8080         │  │ Groups       │       │
│  └─────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│        │                  │                  │               │
│        └──────────────────┴──────────────────┘               │
│                           │                                  │
│  ┌────────────────────────┴────────────────────────┐        │
│  │ NSSM (Windows Service Manager)                  │        │
│  │ - nginx.service                                  │        │
│  │ - nginx-web-ui.service                           │        │
│  └──────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

---

## 구성 요소

### 1. 핵심 컴포넌트

| 컴포넌트 | 버전 | 역할 | 포트 |
|---------|------|------|------|
| **Nginx** | 1.24.0 | 리버스 프록시 엔진 | 80, 443 |
| **Node.js** | v20.11.0 | 웹 UI 런타임 | 8080 |
| **NSSM** | 2.24 | Windows 서비스 관리 | - |
| **Visual C++** | 2015-2022 | Node.js 의존성 | - |

### 2. 옵션 컴포넌트

| 컴포넌트 | 용도 | 특징 |
|---------|------|------|
| **Zoraxy** | GUI 프록시 관리 | 독립 실행형, Windows 네이티브 |

---

## 데이터 흐름

```
외부 요청 → Nginx (Port 80/443)
             ↓
          프록시 룰 매칭
             ↓
       업스트림 서버 전달
          (192.168.x.x)
             ↓
          응답 반환
```

### 프록시 설정 흐름

```
옵션 1: PowerShell 스크립트
  CSV 파일 → add-proxy.ps1 → nginx.conf 생성 → Nginx 재시작

옵션 2: Node.js 웹 UI (추천)
  브라우저 (localhost:8080) → REST API → nginx.conf 수정 → Nginx 재시작

옵션 3: Zoraxy
  GUI → 설정 변경 → Nginx 설정 동기화
```

---

## Active Directory 통합

### AD 구조

```
Domain: company.local
├── OU=Service Accounts
│   └── nginx-service (서비스 실행 계정)
├── OU=Security Groups
│   ├── NginxAdministrators (전체 관리 권한)
│   └── NginxOperators (운영 권한)
```

### 권한 모델

| 그룹 | 권한 | 작업 |
|------|------|------|
| **NginxAdministrators** | Full Control | 프록시 추가/삭제/수정, 서비스 재시작, 설정 변경 |
| **NginxOperators** | Read + Execute | 상태 조회, 로그 확인, 프록시 추가만 가능 |

---

## 보안 아키텍처

### 1. 네트워크 보안

```
┌──────────────────────────────────────┐
│ Windows Firewall Rules               │
├──────────────────────────────────────┤
│ ALLOW: 80/tcp (HTTP)                 │
│ ALLOW: 443/tcp (HTTPS)               │
│ DENY:  8080/tcp (외부 → 웹 UI)      │
│ ALLOW: 8080/tcp (localhost만)       │
└──────────────────────────────────────┘
```

### 2. 파일 시스템 권한

```
C:\nginx\
├── conf\          (읽기 전용 - Operators)
├── logs\          (읽기 전용 - Operators)
├── html\          (읽기 전용 - All)
└── ssl\           (접근 금지 - Admins만)
```

### 3. 서비스 보안

- **실행 계정**: `nginx-service` (도메인 서비스 계정)
- **권한 최소화**: 필요한 포트 바인딩만 허용
- **로그 감사**: 모든 설정 변경 기록

---

## 디렉토리 구조

```
C:\
├── nginx\                      # Nginx 설치 디렉토리
│   ├── conf\
│   │   ├── nginx.conf         # 메인 설정
│   │   └── conf.d\            # 프록시 설정들
│   ├── logs\
│   │   ├── access.log
│   │   └── error.log
│   ├── html\                  # 기본 웹 루트
│   └── ssl\                   # SSL 인증서
│
├── airgap-package\             # 설치 패키지
│   ├── installers\            # 설치 파일들
│   ├── scripts\               # PowerShell 스크립트
│   │   ├── nginx-web-ui.js   # Node.js 웹 UI
│   │   ├── add-proxy.ps1     # 프록시 추가
│   │   └── *.ps1             # 관리 스크립트들
│   ├── configs\
│   │   ├── .env.example
│   │   └── services.csv.example
│   └── reverse_proxy\         # 문서
│
└── Program Files\
    └── nodejs\                # Node.js 런타임
```

---

## 확장성

### 수평 확장 (Scale Out)

```
Load Balancer (F5/HAProxy)
       ↓
┌──────┴──────┐
│   Nginx #1  │
│   Nginx #2  │  ← 설정 파일 동기화 (Robocopy/DFS-R)
│   Nginx #3  │
└─────────────┘
```

### 수직 확장 (Scale Up)

- **Worker Processes**: CPU 코어 수에 맞춰 조정
- **Worker Connections**: 메모리에 따라 증가 (기본 1024)
- **Keepalive Timeout**: 연결 유지 최적화

---

## 모니터링 통합

### Prometheus Metrics (향후 추가 예정)

```
nginx_http_requests_total
nginx_http_request_duration_seconds
nginx_upstream_response_time_seconds
nginx_connections_active
```

### 로그 수집

```
Nginx Logs → Promtail → Loki → Grafana
```

---

## 버전 정보

| 항목 | 값 |
|------|-----|
| **패키지 버전** | v1.1.0 |
| **릴리스 날짜** | 2025-10-21 |
| **지원 OS** | Windows Server 2016+ |
| **아키텍처** | x64 |

---

## 참고 문서

- [배포 가이드](deployment.md)
- [API 문서](api.md)
- [문제 해결](troubleshooting.md)
