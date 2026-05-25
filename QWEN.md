# Advanced AI Production Fabric Stack — QWEN.md

## Project Vision

This is a **high-availability, microservices-based multi-agent swarm architecture** designed for enterprise-grade AI orchestration. The system operates a **tiered intelligence routing framework** through LiteLLM as the central gateway, with autonomous agents (Agent-Zero, OpenClaw, Morpheus) consuming routed inference across isolated network boundaries.

### Core Objective

Establish a production-ready AI fabric where:
1. **Morpheus** serves as the primary intelligence layer, receiving routed requests through LiteLLM's tiered fallback chains.
2. **Autonomous agents** (Agent-Zero, OpenClaw) operate on the backend network, consuming Morpheus-tier models via internal Docker DNS.
3. **Frontend interfaces** (Open WebUI, n8n) provide human interaction surfaces, bridging to the backend inference engine through cross-network attachments.
4. **Local inference** (Ollama with NVIDIA GPU passthrough) provides a hardware-backed fallback when cloud providers are unavailable.

---

## Tiered Intelligence Routing Framework

All model requests flow through **LiteLLM** (`ai-litellm:4000`), which implements a four-tier routing strategy with automatic fallback:

| Tier | Designation | Providers | Purpose |
|---|---|---|---|
| **Tier 1** | **High IQ (Premium)** | OpenRouter Gemini 2.5 Pro, DeepSeek Reasoner | Supreme reasoning, complex analysis, deep-thought chains |
| **Tier 2** | **High Speed (Flash)** | Gemini 1.5 Flash, Qwen-Max (Dashscope) | Fast operational execution, high-throughput tasks |
| **Tier 3** | **Free Fallback Pool** | OpenRouter free-tier models | Zero-cost continuity when premium keys are exhausted |
| **Tier 4** | **Local Fallback** | Ollama DeepSeek-R1 8B (NVIDIA GPU) | Hardware-backed inference when all cloud providers fail |

### Morpheus Model Aliases

Clients (Open WebUI, Agent-Zero, n8n) reference these model names — LiteLLM resolves them to actual providers:

| Alias | Tier(s) | Fallback Chain |
|---|---|---|
| `morpheus-core` | Tier 1 (Gemini 2.5 Pro) | → `morpheus-free-fallback` → `local-processor` |
| `morpheus-deep-thought` | Tier 1 (DeepSeek Reasoner) | → `morpheus-free-fallback` → `local-processor` |
| `morpheus-flash` | Tier 2 (Gemini 1.5 Flash) | → `morpheus-free-fallback` |
| `morpheus-qwen` | Tier 2 (Qwen-Max) | → `morpheus-free-fallback` |
| `local-processor` | Tier 4 (Ollama) | N/A (final fallback) |
| `nomic-embed-text` | Embedding | N/A (RAG vector embeddings) |

---

## Isolated Triple-Network Segregation

The architecture enforces strict network boundaries using three Docker bridge networks. Services are attached to only the networks they require — no service has blanket access.

| Network | Purpose | Services |
|---|---|---|
| **`frontend-net`** | Web-facing user interfaces | Open WebUI, n8n |
| **`backend-net`** | Inference engines, autonomous agents, search | LiteLLM, Ollama, Agent-Zero, OpenClaw, Browserless, SearXNG, Qdrant |
| **`database-net`** | Strictly isolated data storage | PostgreSQL, Redis, LiteLLM (for PG-backed config) |

### Cross-Network Bridge: LiteLLM

LiteLLM (`ai-litellm`) is the **only service attached to both `frontend-net` and `backend-net`** (plus `database-net`). This makes it the mandatory bridge for all inference traffic:

```
Open WebUI ──(frontend-net)──► ai-litellm ──(backend-net)──► Ollama
n8n          ──(frontend-net)──► ai-litellm ──(backend-net)──► Agent-Zero
Agent-Zero   ──────────────────(backend-net)──► ai-litellm ──(backend-net)──► providers
```

### Critical DNS Rule

**All inter-service communication MUST use internal Docker service hostnames** (container names), NEVER `localhost` or `127.0.0.1` or host IPs. Docker's embedded DNS resolves container names within shared networks.

| Correct | Incorrect |
|---|---|
| `http://ai-litellm:4000/v1` | `http://localhost:4000/v1` |
| `http://ai-ollama:11434` | `http://127.0.0.1:11434` |
| `redis://ai-redis:6379` | `redis://localhost:6379` |
| `http://ai-searxng:8080` | `http://192.168.1.x:8080` |

---

## Core Services

| Layer | Services | Network(s) |
|---|---|---|
| **Data** | PostgreSQL 16, Redis 7, Qdrant (vector DB) | `database-net` (Qdrant also on `backend-net`) |
| **Inference** | Ollama (NVIDIA GPU), LiteLLM (gateway) | `backend-net` (+ `frontend-net`, `database-net` for LiteLLM) |
| **Frontend** | Open WebUI, n8n | `frontend-net` (+ `backend-net` for LiteLLM access) |
| **Agents** | Agent-Zero, OpenClaw, Browserless | `backend-net` |
| **Search** | SearXNG (agent web search) | `backend-net` |

---

## Key Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Primary stack definition with health checks and network segregation |
| `docker-compose-bcp1.yml` | Alternate/backup compose file |
| `setup.sh` | Idempotent bootstrap script — single source of truth for project structure |
| `reset_data.sh` | Destructive cleanup utility |
| `.env` / `.secrets` | Runtime configuration and third-party API keys (git-ignored) |
| `.env.example` / `.secrets.example` | Templates (committed) |
| `configs/litellm/litellm.yml` | LiteLLM model routing, tier definitions, fallback chains |
| `configs/searxng/settings.yml` | SearXNG lean agent-focused configuration |
| `configs/mcp/mcp_config.json` | MCP server configuration for Postgres integration |
| `documentation/*.md` | Per-service operational manuals |

---

## Building and Running

### Initial Setup

```bash
# 1. Run the setup script (generates full project structure)
bash setup.sh

# 2. Edit environment variables (required — set real credentials)
nano .env
nano .secrets

# 3. Fix host-side permissions for Agent-Zero (prevents silent Permission Denied)
sudo chown -R 1000:1000 data/agent-zero

# 4. Launch the stack
docker compose up -d
```

### Common Commands

```bash
# View running services
docker compose ps

# View logs for all services
docker compose logs -f

# View logs for a specific service
docker compose logs -f ai-litellm

# Stop the stack (preserves data)
docker compose down

# Stop the stack and wipe all persistent data
bash reset_data.sh
```

### Default Ports

| Service | Port | URL |
|---|---|---|
| Open WebUI | 3000 | http://localhost:3000 |
| LiteLLM | 4000 | http://localhost:4000 |
| n8n | 5678 | http://localhost:5678 |
| Qdrant | 6333 | http://localhost:6333 |

### GPU Support

Ollama is configured with NVIDIA GPU passthrough (`deploy.resources.reservations.devices`). Requires the NVIDIA Container Toolkit installed on the host. Verify with:

```bash
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

---

## Environment Configuration

### `.env` — Core settings

| Variable | Purpose |
|---|---|
| `OPENWEBUI_PORT`, `LITELLM_PORT`, `N8N_PORT`, `QDRANT_PORT` | External port mappings |
| `LITELLM_MASTER_KEY` | Bearer token for LiteLLM gateway |
| `N8N_ENCRYPTION_KEY` | n8n encryption key (minimum 32 chars) |
| `BROWSERLESS_TOKEN` | Browserless auth token |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | PostgreSQL credentials |
| `REDIS_PASSWORD` | Redis authentication |
| `QDRANT_API_KEY` | Qdrant API key (required, non-empty) |

### `.secrets` — Third-party provider keys

| Variable | Provider |
|---|---|
| `OPENROUTER_KEY_1`–`6` | OpenRouter API keys (load-balanced) |
| `DEEPSEEK_KEY_1`–`5` | DeepSeek API keys |
| `GEMINI_API_KEY_1`–`5` | Google Gemini API keys |
| `ALIBABA_MODELSTUDIO_KEY_1`–`5` | Dashscope/Qwen API keys |
| `GROK_KEY_1`–`5` | Grok/X.AI API keys |
| `OPENAI_API_KEY` | OpenAI (legacy fallback) |
| `ANTHROPIC_API_KEY` | Anthropic Claude (legacy fallback) |

### `configs/litellm/litellm.yml` — Model routing

Defines Morpheus model aliases mapped to actual providers with load balancing, retry logic, and automatic fallback chains. See the **Tiered Intelligence Routing Framework** section above for the full routing table.

---

## Agent-Zero Volume & Permission Notes

- **Workspace mapping**: `./data/agent-zero:/a0/usr` — targets `/a0/usr` inside the container to prevent root directory runtime erasure.
- **Host permissions**: Run `sudo chown -R 1000:1000 data/agent-zero` after first container start to prevent silent Permission Denied errors (Agent-Zero runs as UID 1000).

---

## CI/CD

A GitHub Actions workflow (`.github/workflows/deploy.yml`) handles automated deployment over SSH on every push to `main`. Required repository secrets: `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`, and all `PROD_*` environment secrets.

---

## Development Conventions

- **Configuration files** (`configs/`) are version-controlled; **data** (`data/`) is git-ignored.
- The `setup.sh` script is the **single source of truth** — it regenerates the entire project structure. Manual edits to `docker-compose.yml` will be overwritten if `setup.sh` is re-run.
- The `reset_data.sh` script is destructive — it confirms before wiping data and brings down all containers.
- **Never commit** `.env`, `.secrets`, or any file under `data/`.
- All inter-service URLs must use Docker internal hostnames (e.g., `ai-litellm`, `ai-ollama`), never `localhost`.
