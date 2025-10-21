#!/bin/bash

#
# 에어갭 환경용 패키지 자동 다운로드 스크립트
# Linux 환경에서 실행하여 Windows Server용 설치 파일 수집
#

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 버전 설정
NODE_VERSION="20.11.0"
NGINX_VERSION="1.24.0"
NSSM_VERSION="2.24"

# 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALLER_DIR="$PACKAGE_ROOT/installers"
NPM_DIR="$PACKAGE_ROOT/npm-packages"
LOG_DIR="$PACKAGE_ROOT/logs"

# 로그 파일
LOG_FILE="$LOG_DIR/download-$(date +%Y%m%d-%H%M%S).log"

# 함수: 로그 출력
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)
            echo -e "${CYAN}[$timestamp] [INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[$timestamp] [ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# 함수: 파일 다운로드
download_file() {
    local url=$1
    local output=$2
    local description=$3

    log INFO "다운로드 시작: $description"
    log INFO "  URL: $url"
    log INFO "  저장: $output"

    # 이미 존재하는 파일 확인
    if [ -f "$output" ]; then
        log WARN "파일이 이미 존재합니다. 덮어쓰시겠습니까? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log INFO "다운로드 건너뜀: $description"
            return 0
        fi
        rm -f "$output"
    fi

    # wget 또는 curl 사용
    if command -v wget &> /dev/null; then
        if wget --show-progress -O "$output" "$url" 2>&1 | tee -a "$LOG_FILE"; then
            log SUCCESS "다운로드 완료: $(basename "$output")"
            return 0
        else
            log ERROR "wget 다운로드 실패"
            return 1
        fi
    elif command -v curl &> /dev/null; then
        if curl -L --progress-bar -o "$output" "$url" 2>&1 | tee -a "$LOG_FILE"; then
            log SUCCESS "다운로드 완료: $(basename "$output")"
            return 0
        else
            log ERROR "curl 다운로드 실패"
            return 1
        fi
    else
        log ERROR "wget 또는 curl이 필요합니다"
        return 1
    fi
}

# 함수: SHA256 체크섬 계산
calculate_checksum() {
    local file=$1

    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        log ERROR "sha256sum 또는 shasum 명령어를 찾을 수 없습니다"
        return 1
    fi
}

# 배너 출력
echo -e "${CYAN}"
cat << 'EOF'
================================================================================
              에어갭 환경 패키지 다운로드 도구
================================================================================
  이 스크립트는 인터넷에서 필요한 모든 파일을 다운로드합니다.

  다운로드 항목:
    - Node.js v20.11.0 설치 파일 (~30MB)
    - Nginx v1.24.0 웹서버 (~1.5MB)
    - NSSM v2.24 서비스 관리자 (~500KB)
    - Visual C++ 재배포 패키지 (~15MB)

  예상 시간: 5-10분 (네트워크 속도에 따라)
  총 크기: 약 50-100MB
================================================================================
EOF
echo -e "${NC}"

log INFO "다운로드 시작: $(date)"
log INFO "패키지 루트: $PACKAGE_ROOT"

# 디렉토리 생성 확인
mkdir -p "$INSTALLER_DIR" "$NPM_DIR" "$LOG_DIR"

# 체크섬 파일 초기화
CHECKSUM_FILE="$PACKAGE_ROOT/checksums.txt"
echo "# SHA256 Checksums - Generated $(date '+%Y-%m-%d %H:%M:%S')" > "$CHECKSUM_FILE"
echo "" >> "$CHECKSUM_FILE"

#
# Step 1: Node.js 다운로드
#
log INFO ""
log INFO "=== [1/4] Node.js 다운로드 ==="

NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-x64.msi"
NODE_FILE="$INSTALLER_DIR/node-v${NODE_VERSION}-x64.msi"

if download_file "$NODE_URL" "$NODE_FILE" "Node.js v${NODE_VERSION}"; then
    CHECKSUM=$(calculate_checksum "$NODE_FILE")
    echo "node-v${NODE_VERSION}-x64.msi	$CHECKSUM" >> "$CHECKSUM_FILE"
    log SUCCESS "Node.js 체크섬: $CHECKSUM"
fi

#
# Step 2: Nginx 다운로드
#
log INFO ""
log INFO "=== [2/4] Nginx 다운로드 ==="

NGINX_URL="https://nginx.org/download/nginx-${NGINX_VERSION}.zip"
NGINX_FILE="$INSTALLER_DIR/nginx-${NGINX_VERSION}.zip"

if download_file "$NGINX_URL" "$NGINX_FILE" "Nginx v${NGINX_VERSION}"; then
    CHECKSUM=$(calculate_checksum "$NGINX_FILE")
    echo "nginx-${NGINX_VERSION}.zip	$CHECKSUM" >> "$CHECKSUM_FILE"
    log SUCCESS "Nginx 체크섬: $CHECKSUM"
fi

#
# Step 3: NSSM 다운로드
#
log INFO ""
log INFO "=== [3/4] NSSM 다운로드 ==="

NSSM_URL="https://nssm.cc/release/nssm-${NSSM_VERSION}.zip"
NSSM_FILE="$INSTALLER_DIR/nssm-${NSSM_VERSION}.zip"

if download_file "$NSSM_URL" "$NSSM_FILE" "NSSM v${NSSM_VERSION}"; then
    CHECKSUM=$(calculate_checksum "$NSSM_FILE")
    echo "nssm-${NSSM_VERSION}.zip	$CHECKSUM" >> "$CHECKSUM_FILE"
    log SUCCESS "NSSM 체크섬: $CHECKSUM"
fi

#
# Step 4: Visual C++ 재배포 패키지 다운로드
#
log INFO ""
log INFO "=== [4/4] Visual C++ 재배포 패키지 다운로드 ==="

VCREDIST_URL="https://aka.ms/vs/17/release/vc_redist.x64.exe"
VCREDIST_FILE="$INSTALLER_DIR/vcredist_x64.exe"

if download_file "$VCREDIST_URL" "$VCREDIST_FILE" "Visual C++ Redistributable"; then
    CHECKSUM=$(calculate_checksum "$VCREDIST_FILE")
    echo "vcredist_x64.exe	$CHECKSUM" >> "$CHECKSUM_FILE"
    log SUCCESS "Visual C++ 체크섬: $CHECKSUM"
fi

#
# Step 5: PowerShell 스크립트 복사
#
log INFO ""
log INFO "=== [5/5] 설치 스크립트 준비 ==="

# 스크립트 파일들이 이미 있는지 확인
REQUIRED_SCRIPTS=(
    "01-prepare-airgap.ps1"
    "02-install-airgap.ps1"
    "03-verify-installation.ps1"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        log SUCCESS "스크립트 존재: $script"
    else
        log WARN "스크립트 없음: $script (수동으로 추가 필요)"
    fi
done

# .env.example 생성
cat > "$PACKAGE_ROOT/configs/.env.example" << 'EOL'
# 프록시 서버 설정
PROXY_SERVER_IP=172.24.178.23
DNS_ZONE_NAME=nxtd.co.kr
NGINX_PATH=C:\nginx

# Node.js 설정
NODE_ENV=production
NODE_PATH=C:\Program Files\nodejs

# 로그 설정
LOG_LEVEL=info
LOG_PATH=C:\nginx\logs
EOL

log SUCCESS ".env.example 생성 완료"

# services.csv.example 생성
cat > "$PACKAGE_ROOT/configs/services.csv.example" << 'EOL'
서비스명,ARecord,IP,Port,UseHTTPS,CustomPath,비고
메인웹서버,web1,192.168.1.10,80,N,,일반 웹서버
API서버,api1,192.168.1.20,8080,N,,REST API 서버
Node.js앱,nodeapp,127.0.0.1,3000,N,,Express 애플리케이션
관리콘솔,admin1,192.168.1.30,8443,Y,,HTTPS 관리콘솔
EOL

log SUCCESS "services.csv.example 생성 완료"

# PACKAGE-INFO.txt 생성
cat > "$PACKAGE_ROOT/PACKAGE-INFO.txt" << EOL
# 에어갭 설치 패키지 정보

## 생성 일시
$(date '+%Y-%m-%d %H:%M:%S')

## 버전 정보
- Node.js: ${NODE_VERSION}
- Nginx: ${NGINX_VERSION}
- NSSM: ${NSSM_VERSION}

## 다운로드 항목
- Node.js v${NODE_VERSION} 설치 파일
- Nginx v${NGINX_VERSION} 웹서버
- NSSM v${NSSM_VERSION} 서비스 관리자
- Visual C++ 재배포 패키지

## 설치 순서
1. 전체 airgap-package 폴더를 Windows Server로 전송
2. PowerShell에서 02-install-airgap.ps1 실행 (관리자 권한)
3. 03-verify-installation.ps1로 검증

## 파일 무결성
checksums.txt 파일로 검증하세요.

## 주의사항
- Windows Server 2016 이상 필요
- 관리자 권한 필수
- 최소 10GB 여유 공간 필요

## 추가 필요 항목
- SSL 인증서 (ssl/ 폴더에 추가)
  - cert.crt 또는 cert.pem
  - cert.key
- npm 패키지 (선택사항)
  - Node.js 설치 후 npm으로 다운로드 가능

## 문제 해결
logs/ 디렉토리의 로그 파일을 확인하세요.
EOL

log SUCCESS "PACKAGE-INFO.txt 생성 완료"

#
# 최종 검증 및 요약
#
log INFO ""
log INFO "=== 다운로드 검증 ==="

TOTAL_FILES=0
SUCCESS_FILES=0
FAILED_FILES=0

REQUIRED_FILES=(
    "$NODE_FILE"
    "$NGINX_FILE"
    "$NSSM_FILE"
    "$VCREDIST_FILE"
)

for file in "${REQUIRED_FILES[@]}"; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    if [ -f "$file" ]; then
        SIZE=$(du -h "$file" | cut -f1)
        log SUCCESS "  [✓] $(basename "$file") ($SIZE)"
        SUCCESS_FILES=$((SUCCESS_FILES + 1))
    else
        log ERROR "  [✗] $(basename "$file") (누락됨)"
        FAILED_FILES=$((FAILED_FILES + 1))
    fi
done

# 전체 크기 계산
if [ -d "$INSTALLER_DIR" ]; then
    TOTAL_SIZE=$(du -sh "$INSTALLER_DIR" | cut -f1)
    log INFO "다운로드 총 크기: $TOTAL_SIZE"
fi

# 최종 요약
echo ""
echo -e "${CYAN}================================================================================${NC}"
echo -e "${GREEN}                    다운로드 완료!${NC}"
echo -e "${CYAN}================================================================================${NC}"
echo ""
echo -e "${GREEN}✅ 패키지 위치: $PACKAGE_ROOT${NC}"
echo -e "${GREEN}✅ 성공: $SUCCESS_FILES/$TOTAL_FILES 파일${NC}"
if [ $FAILED_FILES -gt 0 ]; then
    echo -e "${RED}❌ 실패: $FAILED_FILES 파일${NC}"
fi
echo ""
echo -e "${CYAN}📦 다음 단계:${NC}"
echo -e "  1. SSL 인증서를 ssl/ 폴더에 추가 (선택)"
echo -e "  2. 전체 airgap-package 폴더를 Windows Server로 전송"
echo -e "  3. PowerShell에서 실행:"
echo -e "     ${YELLOW}cd airgap-package\\scripts${NC}"
echo -e "     ${YELLOW}.\\02-install-airgap.ps1${NC}"
echo ""
echo -e "${CYAN}🔒 보안 권장사항:${NC}"
echo -e "  - 전송 전 바이러스 검사 수행"
echo -e "  - checksums.txt로 파일 무결성 검증"
echo -e "  - 전송 경로 보안 확인"
echo ""
echo -e "${CYAN}================================================================================${NC}"

log INFO "로그 파일: $LOG_FILE"
log INFO "체크섬 파일: $CHECKSUM_FILE"
log INFO "다운로드 완료 시각: $(date)"

# 체크섬 파일 내용 표시
log INFO ""
log INFO "=== SHA256 체크섬 ==="
tee -a "$LOG_FILE" < "$CHECKSUM_FILE"

exit 0
