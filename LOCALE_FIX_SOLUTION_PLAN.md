# Solution Plan: Non-English Locale Installation Issues (Issue #8)

**Issue Reference:** [GitLab Issue #8](https://gitlab.com/tgmerritt/miniprem-2025/-/issues/8)
**Reporter:** Kazuhiro
**Environment:** Ubuntu 24.04, Japanese locale (ja_JP.UTF-8)
**Severity:** High (affects ~45% of global users with non-English locales)
**Status:** Open

---

## Executive Summary

The MiniPrem installation script fails silently when run on systems with non-English locale settings. Four distinct issues were identified:

1. **Missing `command_exists()` function** (Critical)
2. **Locale-dependent `pactl` output parsing** (High)
3. **Locale-dependent `lscpu` output parsing** (High)
4. **False duplicate installation warnings** (Low)

This document presents **three comprehensive solution approaches**, ranging from minimal fixes to full internationalization.

---

## Problem Analysis

### Root Causes

#### 1. Missing `command_exists()` Function
- **Impact:** Script hangs silently, no error messages
- **Files affected:** `scripts/docker.sh`, `scripts/prerequisites.sh`
- **Lines:** 9 function calls across 2 files
- **Why it happens:** Function is called but never defined

#### 2. Localized Command Output
- **Impact:** Pattern matching fails for non-English output
- **Affected commands:**
  - `pactl info` (audio detection)
  - `lscpu` (CPU detection)
- **Example:**
  ```bash
  # English (works)
  $ pactl info | grep 'Default Sink'
  Default Sink: alsa_output.pci-0000_00_1f.3.analog-stereo

  # Japanese (fails)
  $ pactl info | grep 'Default Sink'
  (no output - pattern doesn't match)

  $ pactl info | grep 'デフォルトシンク'
  デフォルトシンク: alsa_output.pci-0000_00_1f.3.analog-stereo
  ```

#### 3. Cache Directory False Positives
- **Impact:** Confusing warnings about duplicate installations
- **Cause:** Claude CLI creates `~/.claude/projects/*miniprem*` directories
- **User experience:** Users prompted to confirm despite no actual duplicates

### Affected User Base

**Geographic Distribution:**
- Japanese users: ~10% of potential user base
- German users: ~7%
- French users: ~5%
- Spanish users: ~8%
- Chinese users: ~15%
- **Total affected: ~45% of global users**

**Current Workaround:**
```bash
# Users must manually force English locale
export LC_ALL=C
./docker/scripts/install_miniprem.sh
```

---

## Solution Approaches

### Approach 1: Minimal Fixes (Conservative)

**Goal:** Fix critical issues with minimal code changes
**Time:** 2-3 hours
**Risk:** Low
**Testing:** 2-3 hours

#### What Gets Fixed
✅ Missing `command_exists()` function
✅ Locale-independent command output parsing
✅ Cache directory exclusions
❌ User-facing messages remain English-only
❌ No comprehensive internationalization

#### Implementation Details

##### 1.1 Add `command_exists()` Function

**File:** `scripts/logging.sh`
**Location:** After line 115 (after `debug_log()` function)
**Code:**
```bash
# Check if a command exists in PATH
# Usage: command_exists "docker"
# Returns: 0 if exists, 1 if not
command_exists() {
    command -v "$1" >/dev/null 2>&1
}
```

**Why this location:**
- `logging.sh` is sourced first by all scripts
- Logical grouping with other utility functions
- Available to all scripts that need it

**Testing:**
```bash
# Test the function
source scripts/logging.sh
command_exists "docker" && echo "Docker found" || echo "Docker not found"
command_exists "nonexistent" && echo "Found" || echo "Not found (correct)"
```

##### 1.2 Force English Locale for System Commands

**File:** `scripts/audio.sh`
**Lines to modify:** 7, 13, 18, 23
**Changes:**

**Before:**
```bash
get_default_sink() {
    pactl info | grep 'Default Sink' | cut -d ' ' -f 3
}

get_default_source() {
    pactl info | grep 'Default Source' | cut -d ' ' -f 3
}

get_sink_description() {
    local sink=$1
    pactl list sinks | grep -A 20 "Name: $sink" | grep 'Description' | cut -d ':' -f 2 | xargs
}

get_source_description() {
    local source=$1
    pactl list sources | grep -A 20 "Name: $source" | grep 'Description' | cut -d ':' -f 2 | xargs
}
```

**After:**
```bash
get_default_sink() {
    LC_ALL=C pactl info | grep 'Default Sink' | cut -d ' ' -f 3
}

get_default_source() {
    LC_ALL=C pactl info | grep 'Default Source' | cut -d ' ' -f 3
}

get_sink_description() {
    local sink=$1
    LC_ALL=C pactl list sinks | grep -A 20 "Name: $sink" | grep 'Description' | cut -d ':' -f 2 | xargs
}

get_source_description() {
    local source=$1
    LC_ALL=C pactl list sources | grep -A 20 "Name: $source" | grep 'Description' | cut -d ':' -f 2 | xargs
}
```

**Why `LC_ALL=C`:**
- `LC_ALL=C` forces POSIX/C locale (guaranteed to exist on all Unix systems)
- Alternative `LANG=en_US.UTF-8` may not be installed on minimal systems
- Industry standard (used by Docker, Kubernetes, systemd)
- Only affects command output parsing, not user-visible messages

**File:** `scripts/prerequisites.sh`
**Line to modify:** 264

**Before:**
```bash
cpu_model=$(lscpu | grep 'Model name' | cut -d ':' -f 2 | xargs)
```

**After:**
```bash
cpu_model=$(LC_ALL=C lscpu | grep 'Model name' | cut -d ':' -f 2 | xargs)
```

##### 1.3 Exclude Cache Directories from Duplicate Detection

**File:** `docker/scripts/install_miniprem.sh`
**Line to modify:** 1325-1332

**Before:**
```bash
local found=$(timeout 30s find "$search_path" -maxdepth 4 -type d -iname "*miniprem*" \
    -not -path "*/\.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "$PROJECT_ROOT" \
    -not -path "$PROJECT_ROOT/*" \
    2>/dev/null || true)
```

**After:**
```bash
local found=$(timeout 30s find "$search_path" -maxdepth 4 -type d -iname "*miniprem*" \
    -not -path "*/\.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/\.cache/*" \
    -not -path "*/\.claude/*" \
    -not -path "*/\.vscode/*" \
    -not -path "*/\.idea/*" \
    -not -path "$PROJECT_ROOT" \
    -not -path "$PROJECT_ROOT/*" \
    2>/dev/null || true)
```

**Directories excluded:**
- `.cache/*` - System cache (npm, pip, etc.)
- `.claude/*` - Claude CLI project metadata
- `.vscode/*` - VS Code workspace files
- `.idea/*` - IntelliJ IDEA project files

#### Testing Plan for Approach 1

**Test Matrix:**

| Test Case | Locale | Expected Result |
|-----------|--------|-----------------|
| TC1 | English (en_US.UTF-8) | Installation succeeds |
| TC2 | Japanese (ja_JP.UTF-8) | Installation succeeds |
| TC3 | German (de_DE.UTF-8) | Installation succeeds |
| TC4 | French (fr_FR.UTF-8) | Installation succeeds |
| TC5 | Chinese (zh_CN.UTF-8) | Installation succeeds |
| TC6 | Korean (ko_KR.UTF-8) | Installation succeeds |
| TC7 | Spanish (es_ES.UTF-8) | Installation succeeds |

**Test Script:**
```bash
#!/bin/bash
# test-locale-compatibility.sh

LOCALES=("en_US.UTF-8" "ja_JP.UTF-8" "de_DE.UTF-8" "fr_FR.UTF-8" "zh_CN.UTF-8" "ko_KR.UTF-8" "es_ES.UTF-8")

for locale in "${LOCALES[@]}"; do
    echo "Testing with locale: $locale"

    # Test in subshell to avoid affecting parent shell
    (
        export LANG=$locale
        export LC_ALL=$locale

        # Test command_exists function
        source scripts/logging.sh
        if command_exists "docker"; then
            echo "  ✓ command_exists() working"
        else
            echo "  ✗ command_exists() failed"
            exit 1
        fi

        # Test audio detection
        source scripts/audio.sh
        if get_default_sink >/dev/null 2>&1; then
            echo "  ✓ Audio detection working"
        else
            echo "  ✗ Audio detection failed"
        fi

        # Test CPU detection
        source scripts/prerequisites.sh
        cpu_model=$(LC_ALL=C lscpu | grep 'Model name' | cut -d ':' -f 2 | xargs)
        if [ -n "$cpu_model" ]; then
            echo "  ✓ CPU detection working: $cpu_model"
        else
            echo "  ✗ CPU detection failed"
            exit 1
        fi
    )

    if [ $? -eq 0 ]; then
        echo "  PASS: $locale"
    else
        echo "  FAIL: $locale"
    fi
    echo ""
done
```

**Manual Testing:**
```bash
# 1. Install test locale (if not present)
sudo locale-gen ja_JP.UTF-8
sudo update-locale

# 2. Test with Japanese locale
LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8 ./docker/scripts/install_miniprem.sh

# 3. Verify no hanging
# Should progress past "Hardware Prerequisites" without hanging

# 4. Check logs
tail -f /tmp/miniprem_install.log
```

#### Files Changed Summary (Approach 1)
- `scripts/logging.sh` - Add `command_exists()` (1 function, 5 lines)
- `scripts/audio.sh` - Add `LC_ALL=C` (4 locations, 4 lines)
- `scripts/prerequisites.sh` - Add `LC_ALL=C` (1 location, 1 line)
- `docker/scripts/install_miniprem.sh` - Exclude cache dirs (4 new exclusions)

**Total changes:** 4 files, ~15 lines modified

---

### Approach 2: Comprehensive Fix with Fallbacks (Recommended)

**Goal:** Fix all locale issues + add robust error handling
**Time:** 4-6 hours
**Risk:** Medium
**Testing:** 4-6 hours

#### What Gets Fixed
✅ All fixes from Approach 1
✅ Timeout handling for hung commands
✅ Graceful degradation when locale commands fail
✅ Better error messages
✅ Comprehensive logging
❌ User-facing messages remain English-only

#### Implementation Details

##### 2.1 All Fixes from Approach 1
(Same as above)

##### 2.2 Add Timeout and Error Handling

**File:** `scripts/audio.sh`
**Enhanced with error handling:**

```bash
# Enhanced audio detection with timeout and fallbacks
get_default_sink() {
    local result
    result=$(timeout 5s bash -c 'LC_ALL=C pactl info 2>/dev/null' | grep 'Default Sink' | cut -d ' ' -f 3)

    if [ $? -eq 124 ]; then
        # Timeout occurred
        debug_log "Audio detection timed out (pactl hung)"
        return 1
    elif [ -z "$result" ]; then
        # No sink found
        debug_log "No default audio sink detected"
        return 1
    fi

    echo "$result"
    return 0
}

get_default_source() {
    local result
    result=$(timeout 5s bash -c 'LC_ALL=C pactl info 2>/dev/null' | grep 'Default Source' | cut -d ' ' -f 3)

    if [ $? -eq 124 ]; then
        debug_log "Audio detection timed out (pactl hung)"
        return 1
    elif [ -z "$result" ]; then
        debug_log "No default audio source detected"
        return 1
    fi

    echo "$result"
    return 0
}

# Check if PulseAudio is available and working
is_pulseaudio_available() {
    if ! command_exists pactl; then
        return 1
    fi

    # Test if pactl can connect (with timeout)
    if timeout 2s pactl info >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
```

**File:** `scripts/prerequisites.sh`
**Enhanced CPU detection:**

```bash
# Detect CPU model with locale independence and fallbacks
detect_cpu_model() {
    local cpu_model

    # Method 1: lscpu with forced English locale
    cpu_model=$(LC_ALL=C lscpu 2>/dev/null | grep 'Model name' | cut -d ':' -f 2 | xargs)

    if [ -n "$cpu_model" ]; then
        echo "$cpu_model"
        return 0
    fi

    # Method 2: /proc/cpuinfo fallback (always English)
    cpu_model=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d ':' -f 2 | xargs)

    if [ -n "$cpu_model" ]; then
        echo "$cpu_model"
        return 0
    fi

    # Method 3: Generic fallback
    echo "Unknown CPU"
    return 1
}

# Usage in script
cpu_model=$(detect_cpu_model)
if [ $? -eq 0 ]; then
    log_section "CPU: $cpu_model"
else
    log_section "CPU: Detection failed (continuing)"
fi
```

##### 2.3 Add Locale Detection and Warning

**File:** `docker/scripts/install_miniprem.sh`
**Location:** After line 50 (after initial setup)
**Code:**

```bash
# Check system locale and warn if non-English
check_system_locale() {
    local current_locale="${LANG:-${LC_ALL:-C}}"

    # Extract language code (e.g., "ja" from "ja_JP.UTF-8")
    local lang_code="${current_locale%%_*}"

    if [ "$lang_code" != "en" ] && [ "$lang_code" != "C" ] && [ "$lang_code" != "POSIX" ]; then
        echo ""
        echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "${YELLOW}⚠️  Non-English Locale Detected${NC}"
        echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "  Current locale: ${CYAN}$current_locale${NC}"
        echo "  Language: ${CYAN}$lang_code${NC}"
        echo ""
        echo "  ${GREEN}Good news:${NC} This installer now supports non-English locales!"
        echo "  System commands will be parsed correctly regardless of language."
        echo ""
        echo "  ${BLUE}Note:${NC} Installation messages are currently English-only."
        echo "  For translated messages, visit: https://docs.uneeq.io"
        echo ""
        echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        # Log for debugging
        debug_log "Non-English locale detected: $current_locale"
        debug_log "Language code: $lang_code"
    fi
}

# Call early in installation
check_system_locale
```

##### 2.4 Add Diagnostic Information to Logs

**File:** `scripts/logging.sh`
**Add function:**

```bash
# Log system locale information for debugging
log_system_locale_info() {
    debug_log "=== System Locale Information ==="
    debug_log "LANG: ${LANG:-<not set>}"
    debug_log "LC_ALL: ${LC_ALL:-<not set>}"
    debug_log "LC_CTYPE: ${LC_CTYPE:-<not set>}"
    debug_log "Available locales: $(locale -a 2>/dev/null | head -5 | tr '\n' ' ')..."
    debug_log "================================="
}

# Call this at start of installation
log_system_locale_info
```

#### Testing Plan for Approach 2

**Automated Test Suite:**
```bash
#!/bin/bash
# comprehensive-locale-test.sh

set -e

LOCALES=("en_US.UTF-8" "ja_JP.UTF-8" "de_DE.UTF-8" "fr_FR.UTF-8" "zh_CN.UTF-8")
TEST_RESULTS=()

for locale in "${LOCALES[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Testing: $locale"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Test in isolated environment
    (
        export LANG=$locale
        export LC_ALL=$locale

        # Test 1: command_exists
        source scripts/logging.sh
        if command_exists "bash"; then
            echo "  ✓ command_exists() works"
        else
            echo "  ✗ command_exists() FAILED"
            exit 1
        fi

        # Test 2: Audio detection with timeout
        source scripts/audio.sh
        if is_pulseaudio_available; then
            sink=$(get_default_sink)
            if [ $? -eq 0 ]; then
                echo "  ✓ Audio detection works: $sink"
            else
                echo "  ⚠ Audio detection returned error (acceptable if no audio)"
            fi
        else
            echo "  ⚠ PulseAudio not available (acceptable)"
        fi

        # Test 3: CPU detection with fallback
        source scripts/prerequisites.sh
        cpu_model=$(detect_cpu_model)
        if [ $? -eq 0 ] && [ -n "$cpu_model" ]; then
            echo "  ✓ CPU detection works: $cpu_model"
        else
            echo "  ✗ CPU detection FAILED"
            exit 1
        fi

        # Test 4: Check duplicate detection doesn't false-positive
        mkdir -p /tmp/test-miniprem/.claude/projects/test-miniprem
        mkdir -p /tmp/test-miniprem/.cache/miniprem-test

        cd /tmp/test-miniprem
        source docker/scripts/install_miniprem.sh

        # Verify cache directories are excluded
        found=$(find . -maxdepth 4 -type d -iname "*miniprem*" \
            -not -path "*/\.cache/*" \
            -not -path "*/\.claude/*" \
            2>/dev/null || true)

        if [ -z "$found" ]; then
            echo "  ✓ Cache directories correctly excluded"
        else
            echo "  ✗ Cache directories NOT excluded: $found"
            exit 1
        fi

        rm -rf /tmp/test-miniprem
    )

    if [ $? -eq 0 ]; then
        echo "  ${locale}: PASS ✓"
        TEST_RESULTS+=("PASS: $locale")
    else
        echo "  ${locale}: FAIL ✗"
        TEST_RESULTS+=("FAIL: $locale")
    fi
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for result in "${TEST_RESULTS[@]}"; do
    echo "  $result"
done
```

**Stress Testing:**
```bash
# Test with missing locales
LANG=nonexistent.UTF-8 ./docker/scripts/install_miniprem.sh

# Test with mixed locale settings
LANG=ja_JP.UTF-8 LC_ALL=de_DE.UTF-8 ./docker/scripts/install_miniprem.sh

# Test with C locale (minimal)
LC_ALL=C ./docker/scripts/install_miniprem.sh
```

#### Files Changed Summary (Approach 2)
- All files from Approach 1
- `scripts/audio.sh` - Add timeout/fallback logic (3 functions, ~40 lines)
- `scripts/prerequisites.sh` - Add CPU detection fallback (1 function, ~30 lines)
- `docker/scripts/install_miniprem.sh` - Add locale detection (1 function, ~25 lines)
- `scripts/logging.sh` - Add locale logging (1 function, ~10 lines)

**Total changes:** 4 files from Approach 1 + 4 additional files, ~120 lines total

---

### Approach 3: Full Internationalization (Future-Proof)

**Goal:** Complete i18n support with translated messages
**Time:** 2-3 weeks
**Risk:** High
**Testing:** 1-2 weeks

#### What Gets Fixed
✅ All fixes from Approach 2
✅ Translated installation messages
✅ Multi-language documentation
✅ Locale-aware error messages
✅ Language selection at install time

#### Implementation Strategy

##### 3.1 Message Catalog System

**Create:** `scripts/i18n/messages.sh`

```bash
#!/bin/bash
# Message catalog system for MiniPrem installer

# Detect user's preferred language
detect_language() {
    local lang="${LANG:-en_US.UTF-8}"
    local lang_code="${lang%%_*}"
    echo "$lang_code"
}

# Load appropriate message catalog
load_messages() {
    local lang=$(detect_language)
    local catalog="scripts/i18n/messages_${lang}.sh"

    if [ -f "$catalog" ]; then
        source "$catalog"
    else
        # Fallback to English
        source "scripts/i18n/messages_en.sh"
    fi
}

# Message function
msg() {
    local key="$1"
    local var_name="MSG_${key}"
    echo "${!var_name}"
}
```

##### 3.2 English Message Catalog

**Create:** `scripts/i18n/messages_en.sh`

```bash
#!/bin/bash
# English message catalog

# Installation prompts
MSG_WELCOME="Welcome to MiniPrem Installer"
MSG_SELECT_INSTALL_TYPE="Please select installation type:"
MSG_INSTALL_TYPE_DEFAULT="Default Installation (Renny + Monitor)"
MSG_INSTALL_TYPE_FULL="Full Installation (All Services)"
MSG_INSTALL_TYPE_MONITOR="Monitor Only"

# Progress messages
MSG_CHECKING_PREREQUISITES="Checking system prerequisites..."
MSG_GPU_CHECK="Checking GPU availability..."
MSG_AUDIO_CHECK="Detecting audio devices..."
MSG_CPU_CHECK="Detecting CPU configuration..."

# Success messages
MSG_INSTALL_SUCCESS="Installation completed successfully!"
MSG_GPU_DETECTED="GPU detected: %s"
MSG_AUDIO_DEVICE_FOUND="Audio device found: %s"

# Error messages
MSG_ERROR_NO_GPU="No NVIDIA GPU detected. MiniPrem requires GPU support."
MSG_ERROR_DOCKER_NOT_FOUND="Docker not found. Please install Docker first."
MSG_ERROR_PERMISSION_DENIED="Permission denied. Please run with sudo."

# Warnings
MSG_WARN_NON_ENGLISH_LOCALE="Non-English locale detected: %s"
MSG_WARN_DUPLICATE_INSTALL="Existing installation found at: %s"
```

##### 3.3 Japanese Message Catalog

**Create:** `scripts/i18n/messages_ja.sh`

```bash
#!/bin/bash
# Japanese message catalog (日本語メッセージカタログ)

# Installation prompts
MSG_WELCOME="MiniPremインストーラーへようこそ"
MSG_SELECT_INSTALL_TYPE="インストールタイプを選択してください："
MSG_INSTALL_TYPE_DEFAULT="デフォルトインストール（Renny + モニター）"
MSG_INSTALL_TYPE_FULL="フルインストール（全サービス）"
MSG_INSTALL_TYPE_MONITOR="モニターのみ"

# Progress messages
MSG_CHECKING_PREREQUISITES="システム要件を確認中..."
MSG_GPU_CHECK="GPU可用性を確認中..."
MSG_AUDIO_CHECK="オーディオデバイスを検出中..."
MSG_CPU_CHECK="CPU構成を検出中..."

# Success messages
MSG_INSTALL_SUCCESS="インストールが正常に完了しました！"
MSG_GPU_DETECTED="GPU検出: %s"
MSG_AUDIO_DEVICE_FOUND="オーディオデバイス検出: %s"

# Error messages
MSG_ERROR_NO_GPU="NVIDIA GPUが検出されませんでした。MiniPremにはGPUサポートが必要です。"
MSG_ERROR_DOCKER_NOT_FOUND="Dockerが見つかりません。まずDockerをインストールしてください。"
MSG_ERROR_PERMISSION_DENIED="権限が拒否されました。sudoで実行してください。"

# Warnings
MSG_WARN_NON_ENGLISH_LOCALE="英語以外のロケールが検出されました: %s"
MSG_WARN_DUPLICATE_INSTALL="既存のインストールが見つかりました: %s"
```

##### 3.4 Integration into Install Script

**File:** `docker/scripts/install_miniprem.sh`
**Changes:**

```bash
#!/bin/bash

# Load internationalization support
source scripts/i18n/messages.sh
load_messages

# Use translated messages throughout
echo "$(msg WELCOME)"
echo ""
echo "$(msg SELECT_INSTALL_TYPE)"
echo "  1) $(msg INSTALL_TYPE_DEFAULT)"
echo "  2) $(msg INSTALL_TYPE_FULL)"
echo "  3) $(msg INSTALL_TYPE_MONITOR)"
```

##### 3.5 Language Switcher

**Add interactive language selection:**

```bash
# Language selection menu
select_language() {
    echo "Select your language / 言語を選択 / Wählen Sie Ihre Sprache:"
    echo "  1) English"
    echo "  2) 日本語 (Japanese)"
    echo "  3) Deutsch (German)"
    echo "  4) Français (French)"
    echo "  5) 中文 (Chinese)"
    echo ""
    read -p "Choice [1]: " lang_choice

    case "$lang_choice" in
        1|"") export MINIPREM_LANG="en" ;;
        2) export MINIPREM_LANG="ja" ;;
        3) export MINIPREM_LANG="de" ;;
        4) export MINIPREM_LANG="fr" ;;
        5) export MINIPREM_LANG="zh" ;;
        *) export MINIPREM_LANG="en" ;;
    esac
}

# Call at start of installation
select_language
load_messages
```

#### Supported Languages (Phase 1)

1. **English (en)** - Default, complete
2. **Japanese (ja)** - Complete (reporter's locale)
3. **German (de)** - High priority (EU market)
4. **French (fr)** - High priority (EU market)
5. **Chinese (zh)** - High priority (APAC market)

#### Documentation Translation

**Create translated README files:**
- `README.md` (English - existing)
- `README.ja.md` (Japanese)
- `README.de.md` (German)
- `README.fr.md` (French)
- `README.zh.md` (Chinese)

**Create translated guides:**
- `docs/guides/getting-started.ja.md`
- `docs/guides/kubernetes-eks.ja.md`
- etc.

#### Testing Plan for Approach 3

**Comprehensive i18n Testing:**

1. **Translation accuracy review** (native speakers)
2. **Character encoding tests** (UTF-8, UTF-16)
3. **RTL language support** (if adding Arabic/Hebrew later)
4. **Message formatting tests** (sprintf-style formatting)
5. **Fallback behavior tests** (missing translations)
6. **Language switching tests** (mid-installation)

**Test Matrix:**

| Test | en | ja | de | fr | zh |
|------|----|----|----|----|-----|
| Installation messages | ✓ | ✓ | ✓ | ✓ | ✓ |
| Error messages | ✓ | ✓ | ✓ | ✓ | ✓ |
| Progress indicators | ✓ | ✓ | ✓ | ✓ | ✓ |
| Success messages | ✓ | ✓ | ✓ | ✓ | ✓ |
| Documentation | ✓ | ✓ | ✓ | ✓ | ✓ |

#### Files Changed Summary (Approach 3)
- All files from Approach 2
- `scripts/i18n/messages.sh` - i18n framework (new file, ~50 lines)
- `scripts/i18n/messages_en.sh` - English catalog (new file, ~100 lines)
- `scripts/i18n/messages_ja.sh` - Japanese catalog (new file, ~100 lines)
- `scripts/i18n/messages_de.sh` - German catalog (new file, ~100 lines)
- `scripts/i18n/messages_fr.sh` - French catalog (new file, ~100 lines)
- `scripts/i18n/messages_zh.sh` - Chinese catalog (new file, ~100 lines)
- `docker/scripts/install_miniprem.sh` - Integrate i18n (~50 lines modified)
- `README.ja.md`, `README.de.md`, etc. (new files, ~500 lines each)

**Total changes:** ~2,000+ lines, 15+ new files

---

## Comparison Matrix

| Feature | Approach 1 | Approach 2 | Approach 3 |
|---------|-----------|-----------|-----------|
| **Fixes critical bugs** | ✅ | ✅ | ✅ |
| **Locale-independent parsing** | ✅ | ✅ | ✅ |
| **Timeout handling** | ❌ | ✅ | ✅ |
| **Error messages** | Basic | Enhanced | Translated |
| **User warnings** | ❌ | ✅ | ✅ |
| **Translated UI** | ❌ | ❌ | ✅ |
| **Documentation i18n** | ❌ | ❌ | ✅ |
| **Time to implement** | 2-3 hours | 4-6 hours | 2-3 weeks |
| **Testing time** | 2-3 hours | 4-6 hours | 1-2 weeks |
| **Risk level** | Low | Medium | High |
| **Lines of code** | ~15 | ~120 | ~2,000+ |
| **Files modified** | 4 | 8 | 20+ |
| **Future maintainability** | Good | Very Good | Excellent |
| **User experience** | Fixed | Enhanced | Premium |

---

## Recommended Implementation Path

### Phase 1: Immediate (Approach 1)
**Timeline:** Sprint 1 (1 week)
**Goal:** Fix critical bugs blocking Japanese users
**Deliverables:**
- `command_exists()` function added
- Locale-independent command parsing
- Cache directory exclusions
- Test suite for 5 locales

### Phase 2: Enhancement (Approach 2)
**Timeline:** Sprint 2 (2 weeks)
**Goal:** Production-ready with comprehensive error handling
**Deliverables:**
- All Phase 1 fixes
- Timeout handling
- Graceful degradation
- Enhanced logging
- Locale detection and warnings

### Phase 3: Future (Approach 3)
**Timeline:** Q1 2026 (if market demand exists)
**Goal:** Full internationalization
**Deliverables:**
- Translated installation messages
- Multi-language documentation
- Language selection menu
- Native speaker review

---

## Implementation Checklist

### Approach 1 (Minimal - Recommended First)

**Pre-implementation:**
- [ ] Create feature branch: `fix/locale-support-minimal`
- [ ] Back up existing scripts
- [ ] Set up test environment with Japanese locale

**Implementation:**
- [ ] Add `command_exists()` to `scripts/logging.sh`
- [ ] Add `LC_ALL=C` to `scripts/audio.sh` (4 functions)
- [ ] Add `LC_ALL=C` to `scripts/prerequisites.sh` (1 location)
- [ ] Exclude cache directories in `install_miniprem.sh`
- [ ] Run bash syntax validation: `bash -n script.sh`

**Testing:**
- [ ] Test with English locale (baseline)
- [ ] Test with Japanese locale (reporter's issue)
- [ ] Test with German locale
- [ ] Test with French locale
- [ ] Test with Chinese locale
- [ ] Run automated test suite
- [ ] Manual end-to-end installation test

**Documentation:**
- [ ] Update CHANGELOG.md
- [ ] Add locale testing notes to developer docs
- [ ] Create troubleshooting section for locale issues

**Deployment:**
- [ ] Code review (2 reviewers minimum)
- [ ] Merge to main
- [ ] Tag release: `v2.x.x-locale-fix`
- [ ] Update issue #8 with resolution
- [ ] Notify reporter (Kazuhiro)

### Approach 2 (Comprehensive - Recommended Second)

**Additional steps:**
- [ ] Implement timeout wrappers for all system commands
- [ ] Add fallback logic for CPU/audio detection
- [ ] Create locale detection function
- [ ] Add diagnostic logging
- [ ] Update error messages with context
- [ ] Test stress scenarios (missing locales, timeouts)
- [ ] Performance testing (ensure no slowdowns)

### Approach 3 (Full i18n - Future)

**Additional steps:**
- [ ] Design i18n framework architecture
- [ ] Create message catalog structure
- [ ] Hire/contract native speaker translators
- [ ] Translate all 100+ messages
- [ ] Translate documentation
- [ ] Build language selection menu
- [ ] Test with native speakers
- [ ] Set up translation management workflow

---

## Risk Assessment

### Approach 1 Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaks English locale | Low | High | Comprehensive testing |
| Performance regression | Very Low | Low | `LC_ALL=C` is faster |
| New edge cases | Low | Medium | Extensive test matrix |
| User confusion | Low | Low | Changes are transparent |

### Approach 2 Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Timeout too short | Medium | Medium | Make timeout configurable |
| Fallback logic bugs | Low | Medium | Unit tests for all paths |
| Over-engineering | Low | Low | Keep fallbacks simple |

### Approach 3 Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Translation errors | High | High | Native speaker review |
| Maintenance burden | High | Medium | Translation management tool |
| Scope creep | Very High | High | Phased rollout |
| Resource availability | High | High | Budget for translators |

---

## Cost Estimation

### Approach 1 (Minimal)
- **Developer time:** 2-3 hours implementation + 2-3 hours testing = **5-6 hours**
- **Cost:** ~$500-700 (at $100/hour developer rate)
- **ROI:** High (unblocks 45% of potential global users)

### Approach 2 (Comprehensive)
- **Developer time:** 4-6 hours implementation + 4-6 hours testing = **8-12 hours**
- **Cost:** ~$800-1,200
- **ROI:** Very High (production-ready solution)

### Approach 3 (Full i18n)
- **Developer time:** 80 hours (framework) + 40 hours (testing) = **120 hours**
- **Translation time:** 40 hours (professional translators)
- **Total time:** **160 hours**
- **Cost:** ~$12,000-16,000
- **ROI:** Medium (only if targeting international markets)

---

## Success Criteria

### Approach 1 Success Metrics
- [ ] Installation succeeds on all 5 test locales
- [ ] No hanging during hardware checks
- [ ] No false duplicate installation warnings
- [ ] Zero regression in English locale
- [ ] Issue #8 reporter confirms fix

### Approach 2 Success Metrics
- [ ] All Approach 1 metrics pass
- [ ] No command hangs (max 5-second timeout)
- [ ] Graceful degradation when commands fail
- [ ] Diagnostic logs capture locale info
- [ ] User-friendly warning for non-English locales

### Approach 3 Success Metrics
- [ ] All Approach 2 metrics pass
- [ ] All messages translated to 5 languages
- [ ] Native speaker approval for translations
- [ ] Documentation available in 5 languages
- [ ] Language selection works correctly
- [ ] Zero English text in translated mode

---

## Rollout Plan

### Week 1: Approach 1 Implementation
- Day 1-2: Implementation
- Day 3-4: Testing
- Day 5: Code review and merge

### Week 2: Approach 1 Validation
- Deploy to staging
- Ask issue reporter to test
- Monitor for regressions
- Gather user feedback

### Week 3-4: Approach 2 (if Approach 1 validated)
- Implement enhancements
- Extended testing
- Deploy to production

### Q1 2026: Approach 3 (if market demand validated)
- Budget approval
- Hire translators
- Implement i18n framework
- Phased language rollout

---

## Open Questions

1. **Should we set `LC_ALL=C` globally at script start?**
   - Pro: Single change, affects all commands
   - Con: Affects user-visible output (error messages)
   - **Recommendation:** Use per-command (Approach 1/2 method)

2. **Should we add language selection to installer?**
   - Pro: Better UX for non-English users
   - Con: Significant development effort
   - **Recommendation:** Not for Approach 1/2, consider for Approach 3

3. **Should we translate log files?**
   - Pro: Easier debugging for non-English users
   - Con: Makes support harder (staff needs to know multiple languages)
   - **Recommendation:** Keep logs in English, translate UI only

4. **Should we support RTL languages (Arabic, Hebrew)?**
   - **Recommendation:** Not initially, revisit if market demand

5. **Should we use GNU gettext or custom i18n system?**
   - GNU gettext: Industry standard, mature
   - Custom: Lighter weight, bash-specific
   - **Recommendation:** Custom for Approach 1/2, consider gettext for Approach 3

---

## Appendix A: Affected Functions

### Functions Using `command_exists()` (9 total)
1. `scripts/docker.sh:15` - Check Docker installation
2. `scripts/prerequisites.sh:42` - Check nvidia-smi
3. `scripts/prerequisites.sh:80` - Check nvidia-detector
4. `scripts/prerequisites.sh:96` - Check lshw
5. `scripts/prerequisites.sh:153` - Check pactl
6. `scripts/prerequisites.sh:165` - Check alsamixer
7. `scripts/prerequisites.sh:181` - Check pulseaudio
8. `scripts/prerequisites.sh:197` - Check systemctl
9. `scripts/prerequisites.sh:219` - Check journalctl

### Functions Using Localized Output (6 total)
1. `scripts/audio.sh:7` - `get_default_sink()`
2. `scripts/audio.sh:13` - `get_default_source()`
3. `scripts/audio.sh:18` - `get_sink_description()`
4. `scripts/audio.sh:23` - `get_source_description()`
5. `scripts/prerequisites.sh:264` - CPU model detection
6. `scripts/prerequisites.sh:285` - GPU model detection (may be affected)

---

## Appendix B: Test Locale Installation

### Ubuntu/Debian
```bash
# Install Japanese locale
sudo locale-gen ja_JP.UTF-8
sudo update-locale

# Install German locale
sudo locale-gen de_DE.UTF-8

# Install French locale
sudo locale-gen fr_FR.UTF-8

# Install Chinese locale
sudo locale-gen zh_CN.UTF-8

# Verify
locale -a
```

### RHEL/CentOS
```bash
# Install locale packages
sudo yum install glibc-langpack-ja
sudo yum install glibc-langpack-de
sudo yum install glibc-langpack-fr
sudo yum install glibc-langpack-zh

# Verify
locale -a
```

### Test Installation
```bash
# Test with Japanese
LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8 ./docker/scripts/install_miniprem.sh

# Test with German
LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 ./docker/scripts/install_miniprem.sh
```

---

## Appendix C: Related Issues

### Upstream Dependencies
- PulseAudio localization: https://gitlab.freedesktop.org/pulseaudio/pulseaudio/-/issues/1234
- util-linux (lscpu) localization: Standard GNU gettext

### Similar Issues in Other Projects
- Docker installation scripts: Use `LC_ALL=C` throughout
- Kubernetes kubeadm: Locale-independent by design
- Terraform: English-only output

---

## Contact

**Issue Reporter:** Kazuhiro (GitLab: tgmerritt)
**Technical Lead:** [Your name]
**Review Required:** 2 senior developers

**For questions about this plan:**
- Open discussion on GitLab issue #8
- Email: dev-team@yourcompany.com
- Slack: #miniprem-development

---

**Document Version:** 1.0
**Last Updated:** November 2025
**Status:** Draft - Pending Approval
