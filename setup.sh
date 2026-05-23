#!/usr/bin/env bash

# Exit immediately if any command structural block fails
set -e

echo "==============================================================="
echo "🚀 INITIALIZING ADVANCED AI SYSTEM OPERATING FABRIC ARCHITECTURE"
echo "==============================================================="

# 1. GENERATE UNIFORM LOGICAL STRUCTURE TREE
echo "📁 Structuring directory spaces..."
mkdir -p data/{postgres,redis,qdrant,openwebui,litellm,ollama,agent-zero,openclaw,n8n,mcp}
mkdir -p configs/{litellm,searxng,n8n,mcp,agent-zero}
mkdir -p documentation
mkdir -p .github/workflows

# 2. GENERATE AND BIND CORE INFRASTRUCTURE CONFIGURATION (docker-compose.yml)
echo "📄 Writing container configuration matrix (docker-compose.yml)..."
cat << 'EOF' > docker-compose.yml
version: '3.8'

networks:
  frontend-net:
    driver: bridge
  backend-net:
    driver: bridge
  database-net:
    driver: bridge

services:
  # --- CORE UTILITY DATA LAYER ---
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
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  # --- WEB SEARCH FOR AGENTS ---
  searxng:
    image: searxng/searxng:latest
    container_name: ai-searxng
    restart: always
    volumes:
      - ./configs/searxng:/etc/searxng
    networks:
      - backend-net

  # --- INFERENCE ENGINE LAYER ---
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

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ai-litellm
    restart: always
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    env_file:
      - .env
      - .secrets
    volumes:
      - ./configs/litellm/litellm.yml:/app/config.yaml
      - ./data/litellm:/app/data
    command: [ "--config", "/app/config.yaml" ]
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - database-net
      - backend-net

  # --- FRONTEND INTERFACE ---
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
        condition: service_started
    networks:
      - frontend-net
      - database-net
      - backend-net

  # --- WORKFLOW AUTOMATION ---
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: ai-n8n
    restart: always
    ports:
      - "${N8N_PORT:-5678}:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=ai-postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    volumes:
      - ./data/n8n:/home/node/.n8n
      - ./configs/n8n:/opt/n8n/configs
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - frontend-net
      - database-net
      - backend-net

  # --- WEB BROWSER AUTOMATION ---
  browserless:
    image: browserless/chrome:latest
    container_name: ai-browserless
    restart: always
    environment:
      - MAX_CONCURRENT_SESSIONS=5
      - TOKEN=${BROWSERLESS_TOKEN}
    networks:
      - backend-net

  # --- AUTONOMOUS WORKERS ---
  agent-zero:
    image: agent0ai/agent-zero:latest
    container_name: ai-agent-zero
    restart: always
    volumes:
      - ./data/agent-zero:/app/workspace
      - ./configs/agent-zero:/app/config
    environment:
      - OPENAI_API_BASE=http://ai-litellm:4000/v1
      - OPENAI_API_KEY=${LITELLM_MASTER_KEY}
      - SEARXNG_URL=http://ai-searxng:8080
    networks:
      - backend-net

  openclaw:
    image: openclaw/openclaw:latest
    container_name: ai-openclaw
    restart: always
    env_file:
      - .env
      - .secrets
    volumes:
      - ./data/openclaw:/app/data
    environment:
      - OPENAI_BASE_URL=http://ai-litellm:4000/v1
    networks:
      - backend-net
EOF

# 3. WRITE RESET SCRIPT UTIL (reset_data.sh)
echo "📄 Generating development teardown tool (reset_data.sh)..."
cat << 'EOF' > reset_data.sh
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
find data -mindepth 2 -delete
echo "✨ System cleanup completed."
EOF
chmod +x reset_data.sh

# 4. GENERATE BASE SYSTEM TEMPLATES (.env, .secrets, .gitignore)
echo "🔒 Preparing baseline secret environments and tracking exclusion protocols..."
cat << 'EOF' > .env.example
# --- EXT GATEWAY PORTS ---
OPENWEBUI_PORT=3000
LITELLM_PORT=4000
N8N_PORT=5678
QDRANT_PORT=6333

# --- SYSTEM ACCESS STRINGS ---
LITELLM_MASTER_KEY=sk-master-key-replace-me-12345
N8N_ENCRYPTION_KEY=generate-a-random-string-here-64chars
BROWSERLESS_TOKEN=your-secure-browser-token-here

# --- CORE TRANSACTIONAL STORAGE ACCESS ---
POSTGRES_DB=ai_stack
POSTGRES_USER=db_admin_user
POSTGRES_PASSWORD=choose-a-strong-postgres-password
REDIS_PASSWORD=choose-a-strong-redis-password
QDRANT_API_KEY=choose-a-strong-qdrant-password
EOF

cat << 'EOF' > .secrets.example
# --- THIRD-PARTY MODEL AUTH ENTRIES ---
OPENAI_API_KEY=sk-proj-PASTE_YOUR_OPENAI_KEY_HERE
ANTHROPIC_API_KEY=sk-ant-PASTE_YOUR_ANTHROPIC_KEY_HERE
EOF

cat << 'EOF' > .gitignore
data/
.env
.secrets
.env.*
.secrets.*
.DS_Store
Thumbs.db
EOF

# 5. STREAM SYSTEM APPLICATION DESCRIPTIONS (litellm.yml, mcp_config.json)
echo "⚙️ Configuring LiteLLM gateway routers and unified MCP server parameters..."
cat << 'EOF' > configs/litellm/litellm.yml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: "os.environ/OPENAI_API_KEY"

  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: "os.environ/ANTHROPIC_API_KEY"

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
EOF

cat << 'EOF' > configs/mcp/mcp_config.json
{
  "mcpServers": {
    "postgres": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--network", "database-net", "mcp/postgres-server:latest"]
    }
  }
}
EOF

# 6. COMPILE SYSTEM MANUALS (documentation/)
echo "📚 Assembling structural infrastructure manuals..."
cat << 'EOF' > documentation/litellm.md
# LiteLLM Operations Manual
* Internal Alias: `http://ai-litellm:4000`
* Gateway Port: `${LITELLM_PORT}` (Default: `4000`)
* Authentication: Bearer token access via `${LITELLM_MASTER_KEY}`
* Configuration Scope: `configs/litellm/litellm.yml`
EOF

cat << 'EOF' > documentation/n8n.md
# n8n Workflow Automation Engine Manual
* Internal Alias: `http://ai-n8n:5678`
* Gateway Port: `${N8N_PORT}` (Default: `5678`)
* Storage Connection: Native clustering handled through `ai-postgres` on `database-net`.
EOF

cat << 'EOF' > documentation/postgres.md
# Postgres Database Engine Manual
* Internal Alias: `ai-postgres:5432`
* Storage Isolation: Bounded strictly inside `database-net`.
* Host Volume Binding: `./data/postgres`
EOF

cat << 'EOF' > documentation/openwebui.md
# Open WebUI Frontend Interface Manual
* Gateway Port: `${OPENWEBUI_PORT}` (Default: `3000`)
* Inference Endpoint: Targets `http://ai-litellm:4000/v1` via user-defined network spaces.
EOF

cat << 'EOF' > documentation/qdrant.md
# Qdrant Vector Storage Engine Manual
* Internal Alias: `ai-qdrant:6333`
* Access Key Protection: Authenticated via `${QDRANT_API_KEY}` configuration.
EOF

# 7. ASSEMBLE PRODUCTION PIPELINE ENGINE (.github/workflows/deploy.yml)
echo "🔄 Injecting CI/CD automated system runner deployment pipelines..."
cat << 'EOF' > .github/workflows/deploy.yml
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
EOF

# 8. CONSTRUCT PRODUCTION MASTER INFRASTRUCTURE README (README.md)
echo "📝 Formatting system documentation matrix (README.md)..."
cat << 'EOF' > README.md
# Advanced AI Production Fabric Stack

An enterprise-ready orchestration layout containing segregated network parameters, persistent storage engines, workflow configurations, and automated continuous deployment logic.

## 🏗️ System Blueprint Overview
* **`configs/`**: Clean, modular configuration directories (version controlled).
* **`data/`**: Centralized persistent volume attachments (Git ignored).
* **`documentation/`**: Individual service operation blueprints and reference architecture specs.

## 🚀 Rapid Implementation Execution Blueprint

1. **Populate System Variables**:
   ```bash
   cp .env.example .env
   cp .secrets.example .secrets
   ```
2. **Modify Environment Entries**: Open `.env` and `.secrets` to change placeholder strings, select strong database root access credentials, and insert your functional external inference engine authentication hashes.
3. **Execute Cluster Ingress**: Launch the container group in safe background detachment:
   ```bash
   docker compose up -d
   ```

## 🛡️ Structural Network Boundaries
* `frontend-net`: Access vector parameters for web interactions (`openwebui`, `n8n`).
* `backend-net`: Execution spaces for parsing commands and loading agents (`litellm`, `agent-zero`, `openclaw`, `browserless`).
* `database-net`: Completely isolated storage environments (`postgres`, `redis`, `qdrant`).
EOF

# 9. UTILITY COPIES FOR IMMEDIATE USER TRANSITION
cp .env.example .env
cp .secrets.example .secrets

echo "==============================================================="
echo "✅ ARCHITECTURE INFRASTRUCTURE SETUP COMPLETED SUCCESSFULLY!"
echo "==============================================================="
echo "👉 FINAL ACTIONS TO LAUNCH:"
echo " 1. Nano/Edit your configuration states: 'nano .env' and 'nano .secrets'"
echo " 2. Boot your stack: 'docker compose up -d'"
echo "==============================================================="
