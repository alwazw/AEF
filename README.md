# Advanced AI Production Fabric Stack

A high-availability, microservices-based multi-agent swarm architecture with Caddy TLS reverse proxy, isolated network segregation, and automated CI/CD deployment.

## 🏗️ System Blueprint Overview
* **`configs/`**: Clean, modular configuration directories (version controlled).
* **`data/`**: Centralized persistent volume attachments (Git ignored).
* **`documentation/`**: Individual service operation blueprints and reference architecture specs.

## 🚀 Rapid Implementation Execution Blueprint

### Quick Start (Direct Access — ports exposed)
```bash
bash setup.sh
nano .env          # Set credentials + DOMAIN
nano .secrets      # Add API keys
sudo chown -R 1000:1000 data/agent-zero
docker compose up -d
```

### Production Start (Caddy TLS — HTTPS only)
```bash
bash setup.sh
nano .env          # Set DOMAIN=your-domain.com
nano .secrets      # Add API keys
sudo chown -R 1000:1000 data/agent-zero
sudo bash ufw_setup.sh                       # Open ports 80, 443
docker compose -f docker-compose-bcp1.yml up -d   # Caddy proxy stack
```

## 🔒 Caddy Reverse Proxy + Automatic TLS

When using `docker-compose-bcp1.yml`, all traffic flows through Caddy on ports 80/443:

| Subdomain | Backend Service | Purpose |
|---|---|---|
| `${DOMAIN}` | Open WebUI (`:8080`) | Chat interface |
| `n8n.${DOMAIN}` | n8n (`:5678`) | Workflow automation |
| `litellm.${DOMAIN}` | LiteLLM (`:4000`) | AI gateway / Morpheus |
| `qdrant.${DOMAIN}` | Qdrant (`:6333`) | Vector database |
| `ollama.${DOMAIN}` | Ollama (`:11434`) | Local inference |
| `searxng.${DOMAIN}` | SearXNG (`:8080`) | Agent web search |

Caddy automatically provisions and renews Let's Encrypt TLS certificates. Access `https://n8n.your-domain.com` — no more secure cookie errors.

### LAN-Only Setup (No Public DNS)
1. Set `DOMAIN=ai-stack.local` in `.env`
2. Uncomment `# tls internal` lines in `configs/caddy/Caddyfile`
3. Caddy generates self-signed certs — add the CA to your trust store

## 🛡️ UFW Firewall Rules

Run `sudo bash ufw_setup.sh` to configure:

| Port | Protocol | Service | Notes |
|---|---|---|---|
| 80 | TCP | Caddy HTTP | Required for Let's Encrypt ACME |
| 443 | TCP | Caddy HTTPS | Primary public access |
| 3000 | TCP | Open WebUI | Direct access fallback |
| 4000 | TCP | LiteLLM | Direct API access fallback |
| 5678 | TCP | n8n | Direct access fallback |
| 6333 | TCP | Qdrant | Direct access fallback |

Internal-only (blocked from external access): 11434 (Ollama), 6379 (Redis), 5432 (PostgreSQL).

## 🧠 Morpheus Intelligence Tiers

| Tier | Alias | Provider | Fallback |
|---|---|---|---|
| **1 — High IQ** | `morpheus-core` | Gemini 2.5 Pro (OpenRouter) | → free → local |
| **1 — High IQ** | `morpheus-deep-thought` | DeepSeek Reasoner | → free → local |
| **2 — High Speed** | `morpheus-flash` | Gemini 1.5 Flash | → free |
| **2 — High Speed** | `morpheus-qwen` | Qwen-Max (Dashscope) | → free |
| **3 — Free Pool** | `morpheus-free-fallback` | OpenRouter free-tier | — |
| **4 — Local** | `local-processor` | Ollama DeepSeek-R1 8B | — |

## 🛡️ Structural Network Boundaries

| Network | Services |
|---|---|
| `frontend-net` | Caddy, Open WebUI, LiteLLM, n8n |
| `backend-net` | LiteLLM, Ollama, Agent-Zero, OpenClaw, Browserless, SearXNG, Qdrant |
| `database-net` | PostgreSQL, Redis, LiteLLM, Qdrant, n8n |

**Caddy** is the only public-facing service (ports 80/443). **LiteLLM** is the cross-network bridge for all inference traffic.

## 📁 Project Structure

```
├── configs/
│   ├── caddy/           # Caddyfile — reverse proxy + TLS
│   ├── litellm/         # LiteLLM model routing & tier definitions
│   ├── searxng/         # Agent web search configuration
│   ├── n8n/             # n8n workflow configs
│   ├── mcp/             # MCP server configuration
│   └── agent-zero/      # Agent-Zero workspace configs
├── data/
│   ├── caddy/           # TLS certificates (auto-managed)
│   └── ...
├── documentation/       # Per-service operational manuals
├── docker-compose.yml          # Direct-access stack (ports exposed)
├── docker-compose-bcp1.yml     # Caddy TLS proxy stack (HTTPS only)
├── setup.sh                    # Bootstrap script (single source of truth)
├── reset_data.sh               # Destructive cleanup utility
├── ufw_setup.sh                # UFW firewall configuration
├── .env.example                # Environment template (includes DOMAIN)
└── .secrets.example            # API keys template
```

## ⚠️ Critical Rules

* **Never use `localhost`** for inter-service communication — always use Docker internal hostnames (e.g., `http://ai-litellm:4000/v1`).
* **Never commit** `.env`, `.secrets`, or `data/` to version control.
* **Agent-Zero workspace** maps to `/a0/usr` — never change this to `/` or container root will be erased.
* **`setup.sh` is the single source of truth** — manual edits to generated files are overwritten on re-run.
* **n8n secure cookie**: set `N8N_SECURE_COOKIE=false` for direct HTTP access; set `true` behind Caddy HTTPS.
