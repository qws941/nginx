#!/bin/bash
###############################################################################
# 에어갭 패키지 v2.0 Enhanced Edition 검증 스크립트 (Linux/Bash)
# PowerShell Core 없이 실행 가능한 기본 검증
###############################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 카운터
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_COUNT=0

# 스크립트 루트
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(dirname "$SCRIPT_DIR")"

# 결과 저장
declare -a FAILED_ITEMS=()
declare -a WARNING_ITEMS=()

###############################################################################
# 유틸리티 함수
###############################################################################

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    FAILED_ITEMS+=("$1")
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNING_COUNT++))
    WARNING_ITEMS+=("$1")
}

log_section() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

test_file_exists() {
    local file="$1"
    local name="$2"
    ((TOTAL_TESTS++))

    if [[ -f "$PACKAGE_ROOT/$file" ]]; then
        local size=$(stat -c%s "$PACKAGE_ROOT/$file" 2>/dev/null || stat -f%z "$PACKAGE_ROOT/$file" 2>/dev/null || echo "0")
        local size_kb=$((size / 1024))
        log_success "$name (${size_kb}KB)"
    else
        log_error "$name - 파일 없음: $file"
    fi
}

test_directory_exists() {
    local dir="$1"
    local name="$2"
    ((TOTAL_TESTS++))

    if [[ -d "$PACKAGE_ROOT/$dir" ]]; then
        local file_count=$(find "$PACKAGE_ROOT/$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
        log_success "$name (파일 $file_count개)"
    else
        log_error "$name - 디렉토리 없음: $dir"
    fi
}

###############################################################################
# [1/7] 기본 구조 검증
###############################################################################

test_basic_structure() {
    log_section "[1/7] 기본 패키지 구조 검증"

    log_info "패키지 루트: $PACKAGE_ROOT"

    # 필수 디렉토리
    test_directory_exists "scripts" "스크립트 디렉토리"
    test_directory_exists "installers" "설치 파일 디렉토리"
    test_directory_exists "reverse_proxy" "문서 디렉토리"

    # 루트 파일
    test_file_exists "README.md" "루트 README"
}

###############################################################################
# [2/7] 스크립트 파일 검증
###############################################################################

test_script_files() {
    log_section "[2/7] PowerShell 스크립트 파일 검증"

    # 기본 스크립트
    test_file_exists "scripts/01-create-package.ps1" "패키지 생성 스크립트"
    test_file_exists "scripts/02-install-airgap.ps1" "기본 설치 스크립트"
    test_file_exists "scripts/03-uninstall-airgap.ps1" "제거 스크립트"

    # Enhanced 스크립트
    test_file_exists "scripts/02-install-airgap-enhanced.ps1" "Enhanced 설치 스크립트"
    test_file_exists "scripts/04-setup-ad-integration.ps1" "AD 통합 스크립트"
    test_file_exists "scripts/05-backup-restore.ps1" "백업/복구 스크립트"
    test_file_exists "scripts/06-validate-enhanced-package.ps1" "검증 스크립트"
    test_file_exists "scripts/test-nginx-web-ui.ps1" "테스트 스크립트"

    # Web UI
    test_file_exists "scripts/nginx-web-ui.js" "기본 Web UI"
    test_file_exists "scripts/nginx-web-ui-enhanced.js" "Enhanced Web UI"
}

###############################################################################
# [3/7] 설치 파일 검증
###############################################################################

test_installer_files() {
    log_section "[3/7] 설치 파일 검증"

    # Node.js
    ((TOTAL_TESTS++))
    if [[ -f "$PACKAGE_ROOT/installers/node-v20.11.0-x64.msi" ]]; then
        local size=$(stat -c%s "$PACKAGE_ROOT/installers/node-v20.11.0-x64.msi" 2>/dev/null || stat -f%z "$PACKAGE_ROOT/installers/node-v20.11.0-x64.msi" 2>/dev/null || echo "0")
        local size_mb=$((size / 1024 / 1024))
        if [[ $size_mb -gt 20 ]]; then
            log_success "Node.js v20.11.0 MSI (${size_mb}MB)"
        else
            log_error "Node.js MSI 크기 이상 (${size_mb}MB < 20MB)"
        fi
    else
        log_error "Node.js MSI 파일 없음"
    fi

    # Nginx
    test_file_exists "installers/nginx-1.24.0.zip" "Nginx 1.24.0 ZIP"

    # NSSM
    test_file_exists "installers/nssm-2.24.zip" "NSSM 2.24 ZIP"

    # 전체 크기 확인
    ((TOTAL_TESTS++))
    if [[ -d "$PACKAGE_ROOT/installers" ]]; then
        local total_size=$(du -sk "$PACKAGE_ROOT/installers" 2>/dev/null | cut -f1 || echo "0")
        local total_mb=$((total_size / 1024))
        if [[ $total_mb -gt 100 ]]; then
            log_success "설치 파일 전체 크기: ${total_mb}MB"
        else
            log_warning "설치 파일 크기 작음: ${total_mb}MB (권장: >100MB)"
        fi
    fi
}

###############################################################################
# [4/7] PowerShell 스크립트 구문 기본 검증
###############################################################################

test_script_syntax() {
    log_section "[4/7] 스크립트 구문 기본 검증"

    local ps_files=(
        "scripts/01-create-package.ps1"
        "scripts/02-install-airgap.ps1"
        "scripts/02-install-airgap-enhanced.ps1"
        "scripts/03-uninstall-airgap.ps1"
        "scripts/04-setup-ad-integration.ps1"
        "scripts/05-backup-restore.ps1"
        "scripts/06-validate-enhanced-package.ps1"
        "scripts/test-nginx-web-ui.ps1"
    )

    for ps_file in "${ps_files[@]}"; do
        ((TOTAL_TESTS++))
        local full_path="$PACKAGE_ROOT/$ps_file"
        local name=$(basename "$ps_file")

        if [[ -f "$full_path" ]]; then
            # UTF-8 BOM 체크
            if file "$full_path" | grep -q "UTF-8"; then
                # 기본 구문 체크
                local errors=0

                # 1. 괄호 매칭
                local open_brace=$(grep -o '{' "$full_path" | wc -l | tr -d ' ')
                local close_brace=$(grep -o '}' "$full_path" | wc -l | tr -d ' ')
                if [[ $open_brace -ne $close_brace ]]; then
                    log_error "$name - 중괄호 불일치 ({ $open_brace vs } $close_brace)"
                    continue
                fi

                # 2. param 블록 체크
                if ! grep -q "param\s*(" "$full_path" && ! grep -q "\[CmdletBinding()\]" "$full_path"; then
                    log_warning "$name - param 블록 없음 (선택적)"
                fi

                # 3. 기본 PowerShell 키워드 존재
                if grep -q "function\|param\|if\|foreach" "$full_path"; then
                    log_success "$name - 구문 기본 검증 통과"
                else
                    log_warning "$name - PowerShell 키워드 부족"
                fi
            else
                log_warning "$name - UTF-8 인코딩이 아님"
            fi
        else
            log_error "$name - 파일 없음"
        fi
    done
}

###############################################################################
# [5/7] Enhanced 기능 특징 검증
###############################################################################

test_enhanced_features() {
    log_section "[5/7] Enhanced 기능 특징 검증"

    # 1. Enhanced 설치 스크립트
    ((TOTAL_TESTS++))
    local enhanced_install="$PACKAGE_ROOT/scripts/02-install-airgap-enhanced.ps1"
    if [[ -f "$enhanced_install" ]]; then
        local features=0
        grep -q "class.*EnhancedLogger" "$enhanced_install" && ((features++))
        grep -q "function.*Invoke-Rollback" "$enhanced_install" && ((features++))
        grep -q '\$Script:InstallState' "$enhanced_install" && ((features++))
        grep -q '\[switch\]\$AutoService' "$enhanced_install" && ((features++))

        if [[ $features -ge 3 ]]; then
            log_success "Enhanced 설치 스크립트 - 핵심 기능 $features/4"
        else
            log_error "Enhanced 설치 스크립트 - 핵심 기능 부족 $features/4"
        fi
    else
        log_error "Enhanced 설치 스크립트 없음"
    fi

    # 2. 테스트 스크립트
    ((TOTAL_TESTS++))
    local test_script="$PACKAGE_ROOT/scripts/test-nginx-web-ui.ps1"
    if [[ -f "$test_script" ]]; then
        local test_count=$(grep -c "function.*Test-" "$test_script" || echo "0")
        if [[ $test_count -ge 5 ]]; then
            log_success "테스트 스크립트 - 테스트 함수 ${test_count}개"
        else
            log_warning "테스트 스크립트 - 테스트 함수 부족 ${test_count}개"
        fi
    else
        log_error "테스트 스크립트 없음"
    fi

    # 3. AD 통합 스크립트
    ((TOTAL_TESTS++))
    local ad_script="$PACKAGE_ROOT/scripts/04-setup-ad-integration.ps1"
    if [[ -f "$ad_script" ]]; then
        local ad_features=0
        grep -q "NginxAdministrators\|NginxOperators\|NginxReadOnly" "$ad_script" && ((ad_features++))
        grep -q "nginx-service" "$ad_script" && ((ad_features++))
        grep -q "FileSystemAccessRule" "$ad_script" && ((ad_features++))

        if [[ $ad_features -ge 2 ]]; then
            log_success "AD 통합 스크립트 - 핵심 기능 $ad_features/3"
        else
            log_error "AD 통합 스크립트 - 핵심 기능 부족 $ad_features/3"
        fi
    else
        log_error "AD 통합 스크립트 없음"
    fi

    # 4. 백업/복구 스크립트
    ((TOTAL_TESTS++))
    local backup_script="$PACKAGE_ROOT/scripts/05-backup-restore.ps1"
    if [[ -f "$backup_script" ]]; then
        local backup_features=0
        grep -q "Full\|Incremental" "$backup_script" && ((backup_features++))
        grep -q "New-BackupMetadata\|ConvertTo-Json" "$backup_script" && ((backup_features++))
        grep -q "Schedule\|schtasks" "$backup_script" && ((backup_features++))

        if [[ $backup_features -ge 2 ]]; then
            log_success "백업/복구 스크립트 - 핵심 기능 $backup_features/3"
        else
            log_error "백업/복구 스크립트 - 핵심 기능 부족 $backup_features/3"
        fi
    else
        log_error "백업/복구 스크립트 없음"
    fi

    # 5. Enhanced Web UI
    ((TOTAL_TESTS++))
    local enhanced_webui="$PACKAGE_ROOT/scripts/nginx-web-ui-enhanced.js"
    if [[ -f "$enhanced_webui" ]]; then
        local webui_features=0
        grep -q "127\.0\.0\.1\|localhost" "$enhanced_webui" && ((webui_features++))
        grep -q "class.*Logger" "$enhanced_webui" && ((webui_features++))
        grep -q "createBackup\|backupProxy" "$enhanced_webui" && ((webui_features++))

        if [[ $webui_features -ge 2 ]]; then
            log_success "Enhanced Web UI - 핵심 기능 $webui_features/3"
        else
            log_error "Enhanced Web UI - 핵심 기능 부족 $webui_features/3"
        fi
    else
        log_error "Enhanced Web UI 없음"
    fi

    # 6. 검증 스크립트 자체
    ((TOTAL_TESTS++))
    local validation_script="$PACKAGE_ROOT/scripts/06-validate-enhanced-package.ps1"
    if [[ -f "$validation_script" ]]; then
        local line_count=$(wc -l < "$validation_script" | tr -d ' ')
        if [[ $line_count -gt 500 ]]; then
            log_success "검증 스크립트 - ${line_count} 줄"
        else
            log_warning "검증 스크립트 - 코드 부족 ${line_count} 줄"
        fi
    else
        log_error "검증 스크립트 없음"
    fi
}

###############################################################################
# [6/7] 문서화 검증
###############################################################################

test_documentation() {
    log_section "[6/7] 문서화 검증"

    # reverse_proxy 문서
    ((TOTAL_TESTS++))
    local doc_dir="$PACKAGE_ROOT/reverse_proxy"
    if [[ -d "$doc_dir" ]]; then
        local doc_count=$(find "$doc_dir" -type f -name "[0-9][0-9][0-9]_*" | wc -l | tr -d ' ')
        if [[ $doc_count -ge 8 ]]; then
            log_success "문서 파일 - ${doc_count}개 (001-00X 구조)"
        else
            log_warning "문서 파일 부족 - ${doc_count}개"
        fi
    else
        log_error "문서 디렉토리 없음"
    fi

    # 주요 문서
    test_file_exists "reverse_proxy/001_INDEX.md" "문서 인덱스"
    test_file_exists "reverse_proxy/009_ENHANCED-V2-GUIDE.xwiki" "v2.0 Enhanced 가이드"

    # XWiki 문서 내용 검증
    ((TOTAL_TESTS++))
    local xwiki_doc="$PACKAGE_ROOT/reverse_proxy/009_ENHANCED-V2-GUIDE.xwiki"
    if [[ -f "$xwiki_doc" ]]; then
        if grep -q "2\.0\.0\|Enhanced Edition" "$xwiki_doc"; then
            log_success "v2.0 XWiki 문서 - 버전 정보 확인"
        else
            log_error "v2.0 XWiki 문서 - 버전 정보 없음"
        fi
    else
        log_error "v2.0 XWiki 문서 없음"
    fi
}

###############################################################################
# [7/7] 보안 기본 검사
###############################################################################

test_security() {
    log_section "[7/7] 보안 기본 검사"

    log_info "하드코딩된 비밀번호 검색..."

    local suspicious_found=0
    local ps_files=$(find "$PACKAGE_ROOT/scripts" -name "*.ps1" 2>/dev/null)

    for ps_file in $ps_files; do
        local name=$(basename "$ps_file")

        # password = "xxx" 패턴
        if grep -qi 'password\s*=\s*["\x27]' "$ps_file"; then
            log_warning "$name - 의심스러운 비밀번호 패턴 발견"
            ((suspicious_found++))
        fi

        # ConvertTo-SecureString -AsPlainText
        if grep -q "ConvertTo-SecureString.*-AsPlainText" "$ps_file"; then
            log_warning "$name - 평문 비밀번호 변환 발견"
            ((suspicious_found++))
        fi
    done

    ((TOTAL_TESTS++))
    if [[ $suspicious_found -eq 0 ]]; then
        log_success "보안 검사 - 의심스러운 패턴 없음"
    else
        log_warning "보안 검사 - $suspicious_found 개 의심 패턴 발견"
    fi

    # Enhanced Web UI localhost 바인딩
    ((TOTAL_TESTS++))
    local enhanced_webui="$PACKAGE_ROOT/scripts/nginx-web-ui-enhanced.js"
    if [[ -f "$enhanced_webui" ]]; then
        if grep -q "127\.0\.0\.1" "$enhanced_webui" && ! grep -q "0\.0\.0\.0" "$enhanced_webui"; then
            log_success "Web UI 보안 - localhost 전용 바인딩 확인"
        else
            log_error "Web UI 보안 - 보안 바인딩 문제"
        fi
    fi
}

###############################################################################
# 최종 결과
###############################################################################

print_summary() {
    log_section "검증 완료"

    local pass_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    echo -e "${CYAN}총 테스트:${NC} $TOTAL_TESTS"
    echo -e "${GREEN}성공:${NC} $PASSED_TESTS"
    echo -e "${RED}실패:${NC} $FAILED_TESTS"
    echo -e "${YELLOW}경고:${NC} $WARNING_COUNT"
    echo -e "${CYAN}성공률:${NC} ${pass_rate}%"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}✅ 패키지 검증 성공! 모든 테스트 통과${NC}"
        echo ""
        echo -e "${CYAN}📦 패키지 사용 가능 상태입니다.${NC}"
        echo -e "${CYAN}   - Windows Server 환경으로 이전 후 사용하세요.${NC}"
        echo -e "${CYAN}   - PowerShell 5.1+ 환경에서 스크립트 실행${NC}"
        return 0
    elif [[ $pass_rate -ge 80 ]]; then
        echo -e "${YELLOW}⚠️  패키지 부분 검증 성공 (${pass_rate}%)${NC}"
        echo ""
        echo -e "${YELLOW}다음 항목을 확인하세요:${NC}"
        for item in "${FAILED_ITEMS[@]}"; do
            echo -e "  ${RED}•${NC} $item"
        done
        return 1
    else
        echo -e "${RED}❌ 패키지 검증 실패 (${pass_rate}%)${NC}"
        echo ""
        echo -e "${RED}다음 항목에 문제가 있습니다:${NC}"
        for item in "${FAILED_ITEMS[@]}"; do
            echo -e "  ${RED}•${NC} $item"
        done
        return 2
    fi
}

###############################################################################
# 메인 실행
###############################################################################

main() {
    clear
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                           ║${NC}"
    echo -e "${CYAN}║   에어갭 패키지 v2.0 Enhanced Edition 검증 (Linux)       ║${NC}"
    echo -e "${CYAN}║                                                           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "패키지 경로: $PACKAGE_ROOT"
    echo ""

    # 검증 실행
    test_basic_structure
    test_script_files
    test_installer_files
    test_script_syntax
    test_enhanced_features
    test_documentation
    test_security

    # 최종 결과
    print_summary
}

# 실행
main
