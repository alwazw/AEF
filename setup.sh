#!/usr/bin/env bash
# ====================================================================
# Advanced AI Production Fabric Stack — Bootstrap Script
# ====================================================================
# Idempotent: safe to run multiple times. Regenerates all templates
# and configuration files from scratch. Does NOT touch .env/.secrets
# if they already exist (preserves user credentials).
# ====================================================================

set -e

echo "==============================================================="
echo "🚀 INITIALIZING ADVANCED AI SYSTEM OPERATING FABRIC ARCHITECTURE"
echo "==============================================================="

# ==================================================================
# PHASE 1: Directory Structure
# ==================================================================
echo "📁 Structuring directory spaces..."
mkdir -p data/{postgres,redis,qdrant,openwebui,litellm,ollama,agent-zero,openclaw,n8n,mcp,caddy/data,caddy/config}
mkdir -p configs/{litellm,searxng,n8n,mcp,agent-zero,caddy}
mkdir -p documentation
mkdir -p .github/workflows

# ==================================================================
# PHASE 2: Docker Compose — Primary Stack
# ==================================================================
echo "📄 Writing container configuration matrix (docker-compose.yml)..."
cat << 'COMPOSE_EOF' > docker-compose.yml
networks:
  frontend-net:
    driver: bridge
  backend-net:
    driver: bridge
  database-net:
    driver: bridge

services:
  # ==================================================================
  # CADDY — Reverse Proxy + Automatic TLS
  # ==================================================================
  caddy:
    image: caddy:2-alpine
    container_name: ai-caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./data/caddy/data:/data
      - ./data/caddy/config:/config
    networks:
      - frontend-net
      - backend-net
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:2019/metrics"]
      interval: 10s
      timeout: 5s
      retries: 3

  # ==================================================================
  # CORE UTILITY DATA LAYER (database-net only)
  # ==================================================================
  postgres:
    image: postgres:16-alpine
    container_name: ai-postgres
    restart: always
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    networks:
      - database-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: ai-redis
    restart: always
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - ./data/redis:/data
    networks:
      - database-net
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  qdrant:
    image: qdrant/qdrant:latest
    container_name: ai-qdrant
    restart: always
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
    volumes:
      - ./data/qdrant:/qdrant/storage
    ports:
      - "${QDRANT_PORT:-6333}:6333"
    networks:
      - database-net
      - backend-net
    healthcheck:
      test: ["CMD-SHELL", "pidof qdrant"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s

  # ==================================================================
  # WEB SEARCH FOR AGENTS (backend-net only)
  # ==================================================================
  searxng:
    image: searxng/searxng:latest
    container_name: ai-searxng
    restart: always
    volumes:
      - ./configs/searxng:/etc/searxng
    networks:
      - backend-net
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/"]
      interval: 10s
      timeout: 5s
      retries: 3

  # ==================================================================
  # INFERENCE ENGINE LAYER (backend-net)
  # ==================================================================
  ollama:
    image: ollama/ollama:latest
    container_name: ai-ollama
    restart: always
    volumes:
      - ./data/ollama:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    networks:
      - backend-net
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 30s

  # ==================================================================
  # LiteLLM GATEWAY — Cross-network bridge
  # ==================================================================
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ai-litellm
    restart: always
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    env_file:
      - ./.env
      - ./.secrets
    volumes:
      - ./configs/litellm/litellm.yml:/app/config.yaml:ro
      - ./data/litellm:/app/data
    command: ["--config", "/app/config.yaml"]
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - frontend-net
      - backend-net
      - database-net
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:4000/routes')\""]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s

  # ==================================================================
  # FRONTEND INTERFACE (frontend-net + backend-net)
  # ==================================================================
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ai-openwebui
    restart: always
    ports:
      - "${OPENWEBUI_PORT:-3000}:8080"
    environment:
      - OPENAI_API_BASE_URL=http://ai-litellm:4000/v1
      - OPENAI_API_KEY=${LITELLM_MASTER_KEY}
      - REDIS_CONNECTION_STRING=redis://:${REDIS_PASSWORD}@ai-redis:6379/0
    volumes:
      - ./data/openwebui:/app/backend/data
    depends_on:
      redis:
        condition: service_healthy
      litellm:
        condition: service_healthy
    networks:
      - frontend-net
      - backend-net

  # ==================================================================
  # WORKFLOW AUTOMATION (frontend-net + backend-net + database-net)
  # ==================================================================
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: ai-n8n
    restart: always
    ports:
      - "${N8N_PORT:-5678}:5678"
    env_file:
      - ./.env
      - ./.secrets
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=ai-postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_SECURE_COOKIE=false
      - WEBHOOK_URL=http://localhost:${N8N_PORT:-5678}/
    volumes:
      - ./data/n8n:/home/node/.n8n
      - ./configs/n8n:/opt/n8n/configs
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - frontend-net
      - backend-net
      - database-net

  # ==================================================================
  # WEB BROWSER AUTOMATION (backend-net only)
  # ==================================================================
  browserless:
    image: browserless/chrome:latest
    container_name: ai-browserless
    restart: always
    env_file:
      - ./.env
    environment:
      - MAX_CONCURRENT_SESSIONS=5
      - TOKEN=${BROWSERLESS_TOKEN}
    networks:
      - backend-net

  # ==================================================================
  # AUTONOMOUS WORKERS (backend-net only)
  # ==================================================================
  agent-zero:
    image: agent0ai/agent-zero:latest
    container_name: ai-agent-zero
    restart: always
    env_file:
      - ./.env
      - ./.secrets
    volumes:
      - ./data/agent-zero:/a0/usr
      - ./configs/agent-zero:/app/config
    environment:
      - OPENAI_API_BASE=http://ai-litellm:4000/v1
      - OPENAI_API_KEY=${LITELLM_MASTER_KEY}
      - SEARXNG_URL=http://ai-searxng:8080
    depends_on:
      litellm:
        condition: service_healthy
      searxng:
        condition: service_healthy
    networks:
      - backend-net

  openclaw:
    image: alpine/openclaw:latest
    container_name: ai-openclaw
    restart: "no"
    env_file:
      - ./.env
      - ./.secrets
    volumes:
      - ./data/openclaw:/app/data
    environment:
      - OPENAI_BASE_URL=http://ai-litellm:4000/v1
    depends_on:
      litellm:
        condition: service_healthy
    networks:
      - backend-net
COMPOSE_EOF

# ==================================================================
# PHASE 3: Docker Compose — Backup/Alternate Copy
# ==================================================================
echo "📄 Writing backup compose file (docker-compose-bcp1.yml)..."
cp docker-compose.yml docker-compose-bcp1.yml

# ==================================================================
# PHASE 4: Reset Script
# ==================================================================
echo "📄 Generating development teardown tool (reset_data.sh)..."
cat << 'RESET_EOF' > reset_data.sh
#!/usr/bin/env bash
set -e
echo "⚠️  WARNING: Destructive cleanup command initiated."
read -p "Purge persistent state engines entirely? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Execution gracefully aborted."
    exit 1
fi
echo "🛑 Lowering active cluster components..."
docker compose down --volumes --remove-orphans || true
echo "🔓 Overriding container structural path locks..."
sudo chown -R $(id -u):$(id -g) data/
echo "🗑️  Emptying runtime persistent blocks..."
find data -mindepth 1 -not -name data -delete 2>/dev/null || true
echo "✨ System cleanup completed."
RESET_EOF
chmod +x reset_data.sh

# ==================================================================
# PHASE 5: Environment Templates (.env.example, .secrets.example)
# ==================================================================
echo "🔒 Preparing baseline secret environments and tracking exclusion protocols..."

cat << 'ENV_EOF' > .env.example
# ====================================================================
# Advanced AI Production Fabric Stack — Environment Configuration
# ====================================================================
# Copy this file to .env and replace all placeholder values with real credentials.
# NEVER commit .env to version control.
# ====================================================================

# --- GPU VERIFICATION ---
# To verify Docker can access your NVIDIA GPU, run:
#   docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi

# --- CADDY REVERSE PROXY ---
# Your public domain name. Caddy auto-provisions TLS certs for this domain.
# For LAN-only access without public DNS, set this to your LAN hostname
# and uncomment "tls internal" in configs/caddy/Caddyfile.
DOMAIN=ai-stack.example.com

# --- EXTERNAL PORT MAPPINGS (used in direct-access mode, not via Caddy) ---
OPENWEBUI_PORT=3000
LITELLM_PORT=4000
N8N_PORT=5678
QDRANT_PORT=6333

# --- SYSTEM ACCESS STRINGS ---
# LITELLM_MASTER_KEY: Bearer token for the LiteLLM API gateway (min 32 chars)
LITELLM_MASTER_KEY=sk-master-key-replace-me-with-at-least-32-chars

# N8N_ENCRYPTION_KEY: Encryption key for n8n credentials storage (min 32 chars)
N8N_ENCRYPTION_KEY=replace-with-a-random-64-character-string-here-now

# BROWSERLESS_TOKEN: Auth token for headless Chrome automation
BROWSERLESS_TOKEN=replace-with-secure-browserless-token

# --- CORE DATA LAYER CREDENTIALS ---
POSTGRES_DB=ai_stack
POSTGRES_USER=db_admin
POSTGRES_PASSWORD=replace-with-strong-postgres-password

# --- REDIS ---
REDIS_PASSWORD=replace-with-strong-redis-password

# --- QDRANT VECTOR DB ---
# QDRANT_API_KEY must be non-empty; agents use this to authenticate vector queries.
QDRANT_API_KEY=replace-with-strong-qdrant-api-key
ENV_EOF

cat << 'SECRETS_EOF' > .secrets.example
# ====================================================================
# Advanced AI Production Fabric Stack — Third-Party API Secrets
# ====================================================================
# Copy this file to .secrets and replace placeholder values with real API keys.
# NEVER commit .secrets to version control.
# ====================================================================
# All keys below are referenced by configs/litellm/litellm.yml via
# "os.environ/VARIABLE_NAME" syntax.
# ====================================================================

# --- OPENROUTER (Tier 1 Morpheus-Core, Tier 3 Free Fallback) ---
OPENROUTER_KEY_1=sk-or-v1-PASTE_OPENROUTER_KEY_1_HERE
OPENROUTER_KEY_2=sk-or-v1-PASTE_OPENROUTER_KEY_2_HERE
OPENROUTER_KEY_3=sk-or-v1-PASTE_OPENROUTER_KEY_3_HERE
OPENROUTER_KEY_4=sk-or-v1-PASTE_OPENROUTER_KEY_4_HERE
OPENROUTER_KEY_5=sk-or-v1-PASTE_OPENROUTER_KEY_5_HERE
OPENROUTER_KEY_6=sk-or-v1-PASTE_OPENROUTER_KEY_6_HERE

# --- DEEPSEEK (Tier 1 Morpheus-Deep-Thought) ---
DEEPSEEK_KEY_1=sk-PASTE_DEEPSEEK_KEY_1_HERE
DEEPSEEK_KEY_2=sk-PASTE_DEEPSEEK_KEY_2_HERE
DEEPSEEK_KEY_3=sk-PASTE_DEEPSEEK_KEY_3_HERE
DEEPSEEK_KEY_4=sk-PASTE_DEEPSEEK_KEY_4_HERE
DEEPSEEK_KEY_5=sk-PASTE_DEEPSEEK_KEY_5_HERE

# --- GOOGLE GEMINI (Tier 2 Morpheus-Flash) ---
GEMINI_API_KEY_1=AIza-PASTE_GEMINI_KEY_1_HERE
GEMINI_API_KEY_2=AIza-PASTE_GEMINI_KEY_2_HERE
GEMINI_API_KEY_3=AIza-PASTE_GEMINI_KEY_3_HERE
GEMINI_API_KEY_4=AIza-PASTE_GEMINI_KEY_4_HERE
GEMINI_API_KEY_5=AIza-PASTE_GEMINI_KEY_5_HERE

# --- ALIBABA DASHSCOPE / QWEN (Tier 2 Morpheus-Qwen) ---
ALIBABA_MODELSTUDIO_KEY_1=sk-PASTE_ALIBABA_KEY_1_HERE
ALIBABA_MODELSTUDIO_KEY_2=sk-PASTE_ALIBABA_KEY_2_HERE
ALIBABA_MODELSTUDIO_KEY_3=sk-PASTE_ALIBABA_KEY_3_HERE
ALIBABA_MODELSTUDIO_KEY_4=sk-PASTE_ALIBABA_KEY_4_HERE
ALIBABA_MODELSTUDIO_KEY_5=sk-PASTE_ALIBABA_KEY_5_HERE

# --- GROK / X.AI (Reserved for future Tier expansion) ---
GROK_KEY_1=xai-PASTE_GROK_KEY_1_HERE
GROK_KEY_2=xai-PASTE_GROK_KEY_2_HERE
GROK_KEY_3=xai-PASTE_GROK_KEY_3_HERE
GROK_KEY_4=xai-PASTE_GROK_KEY_4_HERE
GROK_KEY_5=xai-PASTE_GROK_KEY_5_HERE

# --- LEGACY FALLBACK PROVIDERS ---
OPENAI_API_KEY=sk-proj-PASTE_OPENAI_KEY_HERE
ANTHROPIC_API_KEY=sk-ant-PASTE_ANTHROPIC_KEY_HERE
SECRETS_EOF

cat << 'GITIGNORE_EOF' > .gitignore
data/
.env
.secrets
.env.*
.secrets.*
.DS_Store
Thumbs.db
*.pyc
__pycache__/
GITIGNORE_EOF

# Only copy templates to .env/.secrets if they don't already exist
# (preserves user's real credentials across re-runs)
if [ ! -f .env ]; then
    cp .env.example .env
    echo "  📋 Created .env from template — EDIT WITH REAL CREDENTIALS"
else
    echo "  ✅ .env already exists — preserving user credentials"
fi

if [ ! -f .secrets ]; then
    cp .secrets.example .secrets
    echo "  📋 Created .secrets from template — EDIT WITH REAL API KEYS"
else
    echo "  ✅ .secrets already exists — preserving user API keys"
fi

# ==================================================================
# PHASE 6: LiteLLM Gateway Configuration
# ==================================================================
echo "⚙️ Configuring LiteLLM gateway routers (Morpheus tiered routing)..."

cat << 'LITELLM_EOF' > configs/litellm/litellm.yml
model_list:
  # ====================================================================
  # TIER 1: SUPREME REASONING (Load Balanced & Prioritized)
  # ====================================================================
  - model_name: morpheus-core
    litellm_params:
      model: openrouter/google/gemini-2.5-pro
      api_key: "os.environ/OPENROUTER_KEY_1"
      max_tokens: 4096
    model_info:
      tier: premium
      max_input_tokens: 15000

  - model_name: morpheus-core
    litellm_params:
      model: openrouter/google/gemini-2.5-pro
      api_key: "os.environ/OPENROUTER_KEY_2"
      max_tokens: 4096
    model_info:
      tier: premium
      max_input_tokens: 15000

  - model_name: morpheus-deep-thought
    litellm_params:
      model: deepseek/deepseek-reasoner
      api_key: "os.environ/DEEPSEEK_KEY_1"
      max_tokens: 8192
    model_info:
      tier: premium
      max_input_tokens: 32000

  - model_name: morpheus-deep-thought
    litellm_params:
      model: deepseek/deepseek-reasoner
      api_key: "os.environ/DEEPSEEK_KEY_2"
      max_tokens: 8192
    model_info:
      tier: premium
      max_input_tokens: 32000

  # ====================================================================
  # TIER 2: FAST OPERATIONAL EXECUTION
  # ====================================================================
  - model_name: morpheus-flash
    litellm_params:
      model: gemini/gemini-1.5-flash
      api_key: "os.environ/GEMINI_API_KEY_1"
      max_tokens: 2048
    model_info:
      tier: premium
      max_input_tokens: 15000

  - model_name: morpheus-qwen
    litellm_params:
      model: dashscope/qwen-max
      api_key: "os.environ/ALIBABA_MODELSTUDIO_KEY_1"
      max_tokens: 2048
    model_info:
      tier: premium
      max_input_tokens: 32000

  - model_name: morpheus-qwen
    litellm_params:
      model: dashscope/qwen-max
      api_key: "os.environ/ALIBABA_MODELSTUDIO_KEY_2"
      max_tokens: 2048
    model_info:
      tier: premium
      max_input_tokens: 32000

  # ====================================================================
  # TIER 3: OPENROUTER FREE FALLBACK POOL
  # ====================================================================
  - model_name: morpheus-free-fallback
    litellm_params:
      model: openrouter/google/gemma-4-26b-a4b-it:free
      api_key: "os.environ/OPENROUTER_KEY_1"
      max_tokens: 2048
    model_info:
      tier: free
      max_input_tokens: 15000

  - model_name: morpheus-free-fallback
    litellm_params:
      model: openrouter/google/gemma-4-26b-a4b-it:free
      api_key: "os.environ/OPENROUTER_KEY_2"
      max_tokens: 2048
    model_info:
      tier: free
      max_input_tokens: 15000

  # ====================================================================
  # TIER 4: LOCAL HARDWARE (NVIDIA GPU via Ollama)
  # ====================================================================
  - model_name: local-processor
    litellm_params:
      model: ollama/deepseek-r1:8b
      api_base: http://ai-ollama:11434
      num_ctx: 8192

  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://ai-ollama:11434

# ====================================================================
# ADVANCED PRIORITY, ROUTING, & RETRY ENGINE
# ====================================================================
router_settings:
  routing_strategy: simple-shuffle
  num_retries: 3
  cooldown_time: 30

  fallbacks:
    - {"morpheus-core": ["morpheus-free-fallback", "local-processor"]}
    - {"morpheus-deep-thought": ["morpheus-free-fallback", "local-processor"]}
    - {"morpheus-flash": ["morpheus-free-fallback"]}
    - {"morpheus-qwen": ["morpheus-free-fallback"]}

litellm_settings:
  drop_params: true
  set_verbose: false
LITELLM_EOF

# ==================================================================
# PHASE 7: SearXNG — Lean Agent-Focused Configuration
# ==================================================================
echo "⚙️ Writing lean SearXNG agent search configuration..."

cat << 'SEARXNG_EOF' > configs/searxng/settings.yml
# ====================================================================
# SearXNG — Lean Agent-Focused Configuration
# ====================================================================

general:
  debug: false
  instance_name: "AI-Stack SearXNG"
  enable_metrics: false
  formats:
    - json
    - html

search:
  safe_search: 0
  autocomplete: "google"
  autocomplete_min: 3
  default_lang: "auto"
  ban_time_on_fail: 5
  max_ban_time_on_fail: 120
  suspended_times:
    SearxEngineAccessDenied: 180
    SearxEngineCaptcha: 3600
    SearxEngineTooManyRequests: 180

server:
  port: 8080
  bind_address: "0.0.0.0"
  base_url: false
  limiter: false
  public_instance: false
  secret_key: "searxng-agent-secret-key-replace-in-production"
  image_proxy: false
  http_protocol_version: "1.0"
  method: "GET"

ui:
  static_path: ""
  templates_path: ""
  default_theme: simple
  default_locale: "en"
  hotkeys: default
  search_on_category_select: true

outgoing:
  request_timeout: 5.0
  max_request_timeout: 15.0
  useragent_suffix: ""
  pool_connections: 50
  pool_maxsize: 10
  enable_http2: true

categories_as_tabs:
  general:
  images:
  news:

engines:
  - name: duckduckgo
    engine: duckduckgo
    shortcut: ddg
    disabled: false

  - name: duckduckgo images
    engine: duckduckgo_extra
    categories: [images]
    ddg_category: images
    shortcut: ddi
    disabled: false

  - name: duckduckgo news
    engine: duckduckgo_extra
    categories: [news]
    ddg_category: news
    shortcut: ddn
    disabled: false

  - name: wikipedia
    engine: wikipedia
    shortcut: wp
    disabled: false
    categories: [general]

  - name: wikidata
    engine: wikidata
    shortcut: wd
    disabled: false
    categories: [general]

  - name: arch linux wiki
    engine: archlinux
    shortcut: al
    disabled: false

  - name: docker hub
    engine: docker_hub
    shortcut: dh
    disabled: false
    categories: [it]

  - name: github
    engine: github
    shortcut: gh
    disabled: false
    categories: [it]

  - name: stackoverflow
    engine: stackoverflow
    shortcut: st
    disabled: false
    categories: [it]

  - name: searchcode code
    engine: searchcode_code
    shortcut: scc
    disabled: false
    categories: [it]

  - name: npm
    engine: npm
    shortcut: npm
    disabled: false
    categories: [it]

  - name: pypi
    engine: pypi
    shortcut: pypi
    disabled: false
    categories: [it]

  - name: currency
    engine: currency_convert
    shortcut: cc
    disabled: false

  - name: google
    engine: google
    shortcut: go
    disabled: true

  - name: bing
    engine: bing
    shortcut: bi
    disabled: true

  - name: yahoo
    engine: yahoo
    shortcut: yh
    disabled: true

  - name: brave
    engine: brave
    shortcut: br
    disabled: true

  - name: startpage
    engine: startpage
    shortcut: sp
    disabled: true
SEARXNG_EOF

# ==================================================================
# PHASE 7.5: Caddy Reverse Proxy Configuration
# ==================================================================
echo "⚙️ Writing Caddy reverse proxy configuration..."

cat << 'CADDY_EOF' > configs/caddy/Caddyfile
# ====================================================================
# Caddy Reverse Proxy — AI Production Fabric Stack
# ====================================================================
# Automatic TLS via Let's Encrypt (requires public DNS + port 80/443
# reachable). For LAN-only use, uncomment the "tls internal" lines.
# ====================================================================

{$DOMAIN} {
    # tls internal                    # ← Uncomment for self-signed LAN certs

    reverse_proxy /v1/* ai-litellm:4000 {
        header_up Host {upstream_hostport}
    }

    reverse_proxy ai-openwebui:8080 {
        header_up Host {upstream_hostport}
    }
}

n8n.{$DOMAIN} {
    # tls internal                    # ← Uncomment for self-signed LAN certs

    reverse_proxy ai-n8n:5678 {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}

litellm.{$DOMAIN} {
    # tls internal                    # ← Uncomment for self-signed LAN certs

    reverse_proxy ai-litellm:4000 {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}

qdrant.{$DOMAIN} {
    # tls internal                    # ← Uncomment for self-signed LAN certs

    reverse_proxy ai-qdrant:6333 {
        header_up Host {upstream_hostport}
    }
}

ollama.{$DOMAIN} {
    # tls internal                    # ← Uncomment for self-signed LAN certs

    reverse_proxy ai-ollama:11434 {
        header_up Host {upstream_hostport}
    }
}

searxng.{$DOMAIN} {
    # tls internal                    # ← Uncomment for self-signed LAN certs

    reverse_proxy ai-searxng:8080 {
        header_up Host {upstream_hostport}
    }
}
CADDY_EOF

# ==================================================================
# PHASE 7.6: UFW Firewall Setup Script
# ==================================================================
echo "🛡️ Writing UFW firewall setup script..."

cat << 'UFW_EOF' > ufw_setup.sh
#!/usr/bin/env bash
# ====================================================================
# UFW Firewall Setup — AI Production Fabric Stack
# ====================================================================
# Opens the required ports for the Caddy reverse proxy and services.
# Must be run as root (via sudo).
# ====================================================================

set -e

echo "==============================================================="
echo "🛡️ Configuring UFW firewall rules for AI Stack"
echo "==============================================================="

if ! command -v ufw &>/dev/null; then
    echo "❌ UFW is not installed. Install with: sudo apt install ufw"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Must run as root. Use: sudo bash $0"
    exit 1
fi

echo "📋 Opening required ports..."
ufw allow 22/tcp comment "SSH access" 2>/dev/null || true
ufw allow 80/tcp comment "Caddy HTTP / ACME challenge"
ufw allow 443/tcp comment "Caddy HTTPS / TLS termination"
ufw allow 3000/tcp comment "Open WebUI direct access"
ufw allow 4000/tcp comment "LiteLLM direct API access"
ufw allow 5678/tcp comment "n8n direct access"
ufw allow 6333/tcp comment "Qdrant direct access"

echo ""
echo "📋 Blocking unnecessary ports..."
ufw deny 11434/tcp 2>/dev/null || true
ufw deny 6379/tcp 2>/dev/null || true
ufw deny 5432/tcp 2>/dev/null || true

echo ""
echo "🔒 Enabling UFW..."
echo "y" | ufw enable

echo ""
echo "==============================================================="
echo "✅ UFW rules applied successfully"
echo "==============================================================="
ufw status numbered
echo ""
echo "💡 To switch to Caddy-only access (close direct ports):"
echo "   sudo ufw delete allow 3000/tcp"
echo "   sudo ufw delete allow 4000/tcp"
echo "   sudo ufw delete allow 5678/tcp"
echo "   sudo ufw delete allow 6333/tcp"
echo "==============================================================="
UFW_EOF
chmod +x ufw_setup.sh

# ==================================================================
# PHASE 8: MCP Configuration
# ==================================================================
echo "⚙️ Writing MCP server configuration..."

cat << 'MCP_EOF' > configs/mcp/mcp_config.json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-postgres",
        "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@ai-postgres:5432/${POSTGRES_DB}"
      ]
    }
  }
}
MCP_EOF

# ==================================================================
# PHASE 9: Agent & n8n Config Placeholders
# ==================================================================
echo "📄 Writing agent configuration placeholders..."

cat << 'A0_EOF' > configs/agent-zero/README.md
# Agent-Zero Configuration Placeholder
#
# Agent-Zero reads its configuration from this directory.
# Place your agent-zero config files (e.g., config.yaml, profiles) here.
#
# The container mounts this directory to /app/config inside the container.
# The workspace volume is mounted to /a0/usr (not /) to prevent root erasure.
A0_EOF

cat << 'N8N_EOF' > configs/n8n/README.md
# n8n Configuration Placeholder
#
# n8n reads additional configuration files from this directory.
# Place your n8n config files (e.g., custom.env, credentials) here.
#
# The container mounts this directory to /opt/n8n/configs inside the container.
# Primary n8n configuration is handled via environment variables in docker-compose.yml.
N8N_EOF

# ==================================================================
# PHASE 10: Documentation
# ==================================================================
echo "📚 Assembling structural infrastructure manuals..."

cat << 'DOC_LITELLM_EOF' > documentation/litellm.md
# LiteLLM Operations Manual

* **Internal Alias**: `http://ai-litellm:4000`
* **Gateway Port**: `${LITELLM_PORT}` (Default: `4000`)
* **Authentication**: Bearer token via `${LITELLM_MASTER_KEY}`
* **Configuration**: `configs/litellm/litellm.yml`
* **Networks**: `frontend-net`, `backend-net`, `database-net` (cross-network bridge)

## Morpheus Model Aliases

| Alias | Provider | Fallback Chain |
|---|---|---|
| `morpheus-core` | OpenRouter Gemini 2.5 Pro | → free-fallback → local-processor |
| `morpheus-deep-thought` | DeepSeek Reasoner | → free-fallback → local-processor |
| `morpheus-flash` | Gemini 1.5 Flash | → free-fallback |
| `morpheus-qwen` | Qwen-Max (Dashscope) | → free-fallback |
| `local-processor` | Ollama DeepSeek-R1 8B | N/A (final fallback) |

## Health Check

```bash
curl -f http://localhost:4000/health
```
DOC_LITELLM_EOF

cat << 'DOC_N8N_EOF' > documentation/n8n.md
# n8n Workflow Automation Engine Manual

* **Internal Alias**: `http://ai-n8n:5678`
* **Gateway Port**: `${N8N_PORT}` (Default: `5678`)
* **Storage**: PostgreSQL-backed persistence via `ai-postgres` on `database-net`
* **Networks**: `frontend-net`, `backend-net`, `database-net`

## Accessing LiteLLM from n8n

Use `http://ai-litellm:4000/v1` as the OpenAI-compatible API endpoint within n8n workflows.
DOC_N8N_EOF

cat << 'DOC_PG_EOF' > documentation/postgres.md
# Postgres Database Engine Manual

* **Internal Alias**: `ai-postgres:5432`
* **Network**: `database-net` (strictly isolated)
* **Host Volume**: `./data/postgres`
* **Health Check**: `pg_isready` every 5s

## Access from Other Services

Services on `database-net` (LiteLLM, n8n) connect directly.
Services on other networks cannot reach PostgreSQL by design.
DOC_PG_EOF

cat << 'DOC_WEBUI_EOF' > documentation/openwebui.md
# Open WebUI Frontend Interface Manual

* **Gateway Port**: `${OPENWEBUI_PORT}` (Default: `3000`)
* **Inference Endpoint**: `http://ai-litellm:4000/v1` (via `backend-net`)
* **Redis Cache**: `redis://ai-redis:6379/0` (via `backend-net`)
* **Networks**: `frontend-net`, `backend-net`

## Configuration

Open WebUI uses the LiteLLM gateway as its sole inference provider.
Set the API key to match `${LITELLM_MASTER_KEY}`.
DOC_WEBUI_EOF

cat << 'DOC_QDRANT_EOF' > documentation/qdrant.md
# Qdrant Vector Storage Engine Manual

* **Internal Alias**: `ai-qdrant:6333`
* **Access Key**: `${QDRANT_API_KEY}`
* **Networks**: `database-net`, `backend-net`
* **Host Volume**: `./data/qdrant`

## Usage

Backend services (Agent-Zero, LiteLLM embedding models) query Qdrant for vector similarity search.
Frontend services cannot reach Qdrant directly.
DOC_QDRANT_EOF

# ==================================================================
# PHASE 11: CI/CD Pipeline
# ==================================================================
echo "🔄 Injecting CI/CD automated deployment pipeline..."

cat << 'CICD_EOF' > .github/workflows/deploy.yml
name: Deploy Advanced AI Stack
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout Repository Code
      uses: actions/checkout@v4
    - name: Deploy Infrastructure over SSH
      uses: appleboy/ssh-action@v1.0.3
      with:
        host: ${{ secrets.SERVER_HOST }}
        username: ${{ secrets.SERVER_USER }}
        key: ${{ secrets.SERVER_SSH_KEY }}
        script: |
          TARGET_DIR="/home/${{ secrets.SERVER_USER }}/ai-stack"
          mkdir -p $TARGET_DIR && cd $TARGET_DIR
          mkdir -p configs/{litellm,searxng,n8n,mcp,agent-zero} data/{postgres,redis,qdrant,openwebui,litellm,ollama,agent-zero,openclaw,n8n,mcp} documentation
          cat << 'INNER' > .env
          OPENWEBUI_PORT=${{ secrets.OPENWEBUI_PORT }}
          LITELLM_PORT=${{ secrets.LITELLM_PORT }}
          N8N_PORT=${{ secrets.N8N_PORT }}
          QDRANT_PORT=${{ secrets.QDRANT_PORT }}
          LITELLM_MASTER_KEY=${{ secrets.PROD_LITELLM_MASTER_KEY }}
          N8N_ENCRYPTION_KEY=${{ secrets.PROD_N8N_ENCRYPTION_KEY }}
          BROWSERLESS_TOKEN=${{ secrets.PROD_BROWSERLESS_TOKEN }}
          POSTGRES_DB=${{ secrets.PROD_POSTGRES_DB }}
          POSTGRES_USER=${{ secrets.PROD_POSTGRES_USER }}
          POSTGRES_PASSWORD=${{ secrets.PROD_POSTGRES_PASSWORD }}
          REDIS_PASSWORD=${{ secrets.PROD_REDIS_PASSWORD }}
          QDRANT_API_KEY=${{ secrets.PROD_QDRANT_API_KEY }}
          INNER
          cat << 'INNER' > .secrets
          OPENAI_API_KEY=${{ secrets.PROD_OPENAI_API_KEY }}
          ANTHROPIC_API_KEY=${{ secrets.PROD_ANTHROPIC_API_KEY }}
          INNER
          echo "${{ secrets.LITELLM_YML_CONFIG }}" > configs/litellm/litellm.yml
          echo "${{ secrets.DOCKER_COMPOSE_YML }}" > docker-compose.yml
          docker compose pull && docker compose up -d --remove-orphans
          sleep 10
          curl -f http://localhost:${{ secrets.LITELLM_PORT }}/health || exit 1
CICD_EOF

# ==================================================================
# PHASE 12: README
# ==================================================================
echo "📝 Formatting system documentation matrix (README.md)..."

cat << 'README_EOF' > README.md
# Advanced AI Production Fabric Stack

A high-availability, microservices-based multi-agent swarm architecture with tiered intelligence routing through LiteLLM, isolated network segregation, and automated CI/CD deployment.

## 🏗️ Architecture Overview

| Layer | Services | Network(s) |
|---|---|---|
| **Data** | PostgreSQL 16, Redis 7, Qdrant | `database-net` |
| **Inference** | Ollama (NVIDIA GPU), LiteLLM (gateway) | `backend-net` (+ `frontend-net`, `database-net` for LiteLLM) |
| **Frontend** | Open WebUI, n8n | `frontend-net` (+ `backend-net`) |
| **Agents** | Agent-Zero, OpenClaw, Browserless | `backend-net` |
| **Search** | SearXNG | `backend-net` |

## 🧠 Morpheus Intelligence Tiers

| Tier | Alias | Provider | Fallback |
|---|---|---|---|
| **1 — High IQ** | `morpheus-core` | Gemini 2.5 Pro (OpenRouter) | → free → local |
| **1 — High IQ** | `morpheus-deep-thought` | DeepSeek Reasoner | → free → local |
| **2 — High Speed** | `morpheus-flash` | Gemini 1.5 Flash | → free |
| **2 — High Speed** | `morpheus-qwen` | Qwen-Max (Dashscope) | → free |
| **3 — Free Pool** | `morpheus-free-fallback` | OpenRouter free-tier | — |
| **4 — Local** | `local-processor` | Ollama DeepSeek-R1 8B | — |

## 🚀 Quick Start

1. **Bootstrap** the project structure:
   ```bash
   bash setup.sh
   ```

2. **Configure** credentials (required):
   ```bash
   nano .env      # Set ports, database credentials, access tokens
   nano .secrets  # Add your OpenRouter, DeepSeek, Gemini, Qwen API keys
   ```

3. **Fix permissions** for Agent-Zero (prevents Permission Denied):
   ```bash
   sudo chown -R 1000:1000 data/agent-zero
   ```

4. **Launch** the stack:
   ```bash
   docker compose up -d
   ```

5. **Verify** LiteLLM health:
   ```bash
   curl -f http://localhost:4000/health
   ```

## 🛡️ Network Boundaries

* `frontend-net`: Web-facing interfaces (Open WebUI, n8n)
* `backend-net`: Inference engines, agents, search (LiteLLM, Ollama, Agent-Zero, OpenClaw, Browserless, SearXNG)
* `database-net`: Strictly isolated data storage (PostgreSQL, Redis)

**LiteLLM is the cross-network bridge** — attached to all three networks, routing frontend requests to backend providers.

## ⚠️ Critical Rules

* **Never use `localhost`** for inter-service communication — always use Docker internal hostnames (e.g., `http://ai-litellm:4000/v1`).
* **Never commit** `.env`, `.secrets`, or `data/` to version control.
* **Agent-Zero workspace** maps to `/a0/usr` — never change this to `/` or container root will be erased.
* **`setup.sh` is the single source of truth** — manual edits to generated files are overwritten on re-run.

## 📁 Project Structure

```
├── configs/          # Version-controlled configuration files
│   ├── litellm/      # LiteLLM model routing & tier definitions
│   ├── searxng/      # Agent web search configuration
│   ├── n8n/          # n8n workflow configs
│   ├── mcp/          # MCP server configuration
│   └── agent-zero/   # Agent-Zero workspace configs
├── data/             # Persistent volumes (git-ignored)
├── documentation/    # Per-service operational manuals
├── docker-compose.yml       # Primary stack definition
├── docker-compose-bcp1.yml  # Backup compose file
├── setup.sh                 # Bootstrap script (single source of truth)
├── reset_data.sh            # Destructive cleanup utility
├── .env.example             # Environment template
└── .secrets.example         # API keys template
```
README_EOF

# ==================================================================
# PHASE 13: Permission Normalization
# ==================================================================
echo "🔧 Normalizing file ownership and permissions..."

# Fix ownership on all configs and data directories
sudo chown -R "$(id -u):$(id -g)" configs/ data/ 2>/dev/null || true
chmod -R 755 configs/ data/ 2>/dev/null || true

# ==================================================================
# COMPLETE
# ==================================================================
echo ""
echo "==============================================================="
echo "✅ ARCHITECTURE INFRASTRUCTURE SETUP COMPLETED SUCCESSFULLY!"
echo "==============================================================="
echo "👉 NEXT STEPS TO LAUNCH:"
echo " 1. Edit credentials: 'nano .env' and 'nano .secrets'"
echo "    → Set DOMAIN to your public domain (or LAN hostname)"
echo " 2. Fix Agent-Zero permissions: 'sudo chown -R 1000:1000 data/agent-zero'"
echo " 3. Configure firewall: 'sudo bash ufw_setup.sh'"
echo " 4. Boot your stack: 'docker compose -f docker-compose-bcp1.yml up -d'"
echo " 5. Access via HTTPS: https://\${DOMAIN} (Caddy auto-provisions TLS)"
echo "    → n8n: https://n8n.\${DOMAIN}"
echo "    → LiteLLM: https://litellm.\${DOMAIN}"
echo "    → Qdrant: https://qdrant.\${DOMAIN}"
echo " 6. LAN-only? Uncomment 'tls internal' in configs/caddy/Caddyfile"
echo "==============================================================="
