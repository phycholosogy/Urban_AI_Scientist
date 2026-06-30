#!/usr/bin/env bash
# =============================================================================
# Urban AI Scientist — User LLM Skill Installer
# Installs the `idea-creator-user-llm` skill for Claude Code.
#
# Usage:
#   bash install_user_llm_skill.sh
#   bash install_user_llm_skill.sh --key sk-xxx --base https://api.openai.com/v1 --model gpt-4o-mini
# =============================================================================
set -euo pipefail

SKILL_NAME="idea-creator-user-llm"
SKILL_SRC="https://raw.githubusercontent.com/phycholosogy/Urban_AI_Scientist/main/skills/SKILL_user_llm.md"
SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
SKILL_FILE="$SKILL_DIR/SKILL.md"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Parse CLI args ─────────────────────────────────────────────────────────────
ARG_KEY=""; ARG_BASE=""; ARG_MODEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --key)   ARG_KEY="$2";   shift 2 ;;
    --base)  ARG_BASE="$2";  shift 2 ;;
    --model) ARG_MODEL="$2"; shift 2 ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Urban AI Scientist — User LLM Skill Installer     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Check dependencies ─────────────────────────────────────────────────────────
info "Checking dependencies..."
for cmd in curl python3; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd is required but not found."
    exit 1
  fi
done
success "curl and python3 found"

# ── Check Claude Code ──────────────────────────────────────────────────────────
if [ ! -d "$HOME/.claude" ]; then
  error "~/.claude not found. Is Claude Code installed?"
  echo "  Install from: https://claude.ai/code"
  exit 1
fi
success "Claude Code directory found"

# ── Create skill directory ──────────────────────────────────────────────────────
mkdir -p "$SKILL_DIR"
success "Skill directory: $SKILL_DIR"

# ── Download skill definition ──────────────────────────────────────────────────
info "Downloading skill definition..."
if curl -fsSL --max-time 30 "$SKILL_SRC" -o "$SKILL_FILE" 2>/dev/null; then
  success "Skill file saved to $SKILL_FILE"
else
  warn "Could not download from GitHub. Using local copy if available."
  # Fallback: check if we're running from the project directory
  LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/SKILL_user_llm.md"
  if [ -f "$LOCAL" ]; then
    cp "$LOCAL" "$SKILL_FILE"
    success "Copied from local: $LOCAL"
  else
    error "Skill definition not found. Check your internet connection."
    exit 1
  fi
fi

# ── Verify backend is reachable ────────────────────────────────────────────────
info "Checking backend availability..."
BACKEND=$(curl -s --max-time 15 "https://phycholosogy.github.io/Urban_AI_Scientist/config.js" | \
  python3 -c "import sys,re; m=re.search(r'USER_LLM_API_BASE\s*:\s*\"([^\"]+)\"', sys.stdin.read()); print(m.group(1) if m else '')" 2>/dev/null)

if [ -z "$BACKEND" ]; then
  warn "Could not resolve backend URL from GitHub Pages. You can still use the skill."
else
  HEALTH=$(curl -s --max-time 10 "$BACKEND/api/health" 2>/dev/null || echo "")
  if echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('ok')" 2>/dev/null; then
    success "Backend reachable: $BACKEND"
  else
    warn "Backend not responding right now (may be restarting). URL: $BACKEND"
  fi
fi

# ── Collect LLM credentials ────────────────────────────────────────────────────
CRED_FILE="$SKILL_DIR/credentials.json"

echo ""
echo "─────────────────────────────────────────────────────────"
echo " LLM Credentials Setup"
echo " Your API key is stored locally and sent over HTTPS only."
echo "─────────────────────────────────────────────────────────"

# Use CLI args if provided, otherwise prompt interactively
if [ -n "$ARG_KEY" ]; then
  OPENAI_API_KEY="$ARG_KEY"
else
  if [ -f "$CRED_FILE" ]; then
    EXISTING_KEY=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('openai_api_key',''))" 2>/dev/null || echo "")
    if [ -n "$EXISTING_KEY" ]; then
      MASKED="${EXISTING_KEY:0:8}****"
      warn "Existing key found: $MASKED"
      read -rp "  Press Enter to keep it, or type a new key: " INPUT_KEY
      OPENAI_API_KEY="${INPUT_KEY:-$EXISTING_KEY}"
    else
      read -rp "  OpenAI-compatible API key (sk-...): " OPENAI_API_KEY
    fi
  else
    read -rp "  OpenAI-compatible API key (sk-...): " OPENAI_API_KEY
  fi
fi

if [ -n "$ARG_BASE" ]; then
  OPENAI_BASE_URL="$ARG_BASE"
else
  DEFAULT_BASE="https://api.openai.com/v1"
  if [ -f "$CRED_FILE" ]; then
    EXISTING_BASE=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('openai_base_url',''))" 2>/dev/null || echo "")
    DEFAULT_BASE="${EXISTING_BASE:-$DEFAULT_BASE}"
  fi
  read -rp "  Base URL [$DEFAULT_BASE]: " INPUT_BASE
  OPENAI_BASE_URL="${INPUT_BASE:-$DEFAULT_BASE}"
fi

if [ -n "$ARG_MODEL" ]; then
  LLM_MODEL="$ARG_MODEL"
else
  DEFAULT_MODEL="gpt-4o-mini"
  if [ -f "$CRED_FILE" ]; then
    EXISTING_MODEL=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('llm_model',''))" 2>/dev/null || echo "")
    DEFAULT_MODEL="${EXISTING_MODEL:-$DEFAULT_MODEL}"
  fi
  read -rp "  Model name [$DEFAULT_MODEL]: " INPUT_MODEL
  LLM_MODEL="${INPUT_MODEL:-$DEFAULT_MODEL}"
fi

# Optional: Semantic Scholar API key (for novelty subcommand)
EXISTING_S2=""
if [ -f "$CRED_FILE" ]; then
  EXISTING_S2=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('semantic_scholar_api_key',''))" 2>/dev/null || echo "")
fi
if [ -n "$EXISTING_S2" ]; then
  MASKED_S2="${EXISTING_S2:0:4}****"
  warn "Existing Semantic Scholar key found: $MASKED_S2"
  read -rp "  Press Enter to keep it, or type a new key (optional): " INPUT_S2
  S2_API_KEY="${INPUT_S2:-$EXISTING_S2}"
else
  read -rp "  Semantic Scholar API key (optional, press Enter to skip): " S2_API_KEY
fi

# Validate: key must not be empty
if [ -z "$OPENAI_API_KEY" ]; then
  error "API key cannot be empty."
  exit 1
fi

# ── Save credentials ────────────────────────────────────────────────────────────
python3 - << PYEOF
import json
cred = {
    "openai_api_key":           "$OPENAI_API_KEY",
    "openai_base_url":          "$OPENAI_BASE_URL",
    "llm_model":                "$LLM_MODEL",
    "semantic_scholar_api_key": "$S2_API_KEY",
}
with open("$CRED_FILE", "w") as f:
    json.dump(cred, f, indent=2)
PYEOF
chmod 600 "$CRED_FILE"
success "Credentials saved to $CRED_FILE (mode 600)"

# ── Quick connectivity test ────────────────────────────────────────────────────
echo ""
info "Testing your API key (quick ping)..."
TEST_RESULT=$(python3 - << PYEOF 2>&1
import json, urllib.request, urllib.error

url = "$OPENAI_BASE_URL".rstrip("/") + "/models"
req = urllib.request.Request(url, headers={"Authorization": "Bearer $OPENAI_API_KEY"})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        print("ok")
except urllib.error.HTTPError as e:
    if e.code == 401:
        print("auth_failed")
    elif e.code in (404, 405):
        print("ok")   # /models not supported by all providers — that's fine
    else:
        print(f"http_{e.code}")
except Exception as e:
    print(f"error: {e}")
PYEOF
)

case "$TEST_RESULT" in
  ok)          success "API key connectivity OK" ;;
  auth_failed) error "API key rejected (401). Please check your key."; exit 1 ;;
  *)           warn "Could not verify key ($TEST_RESULT) — proceeding anyway." ;;
esac

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                   Installation Complete              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Skill file : $SKILL_FILE"
echo "  Credentials: $CRED_FILE"
echo ""
echo "  Usage in Claude Code:"
echo "    /idea-creator-user-llm FAST 城市交通与碳排放"
echo "    /idea-creator-user-llm CAMP --paper_domain Economics 城市化与贫富差距"
echo "    /idea-creator-user-llm DIRECT --temperature 0.7 LLM与公共政策"
echo "    /idea-creator-user-llm novelty ./output/my_idea.md"
echo ""
echo "  Methods:  CAMP | DIRECT | FAST | novelty"
echo "  Model:    $LLM_MODEL"
echo "  Base URL: $OPENAI_BASE_URL"
echo ""
