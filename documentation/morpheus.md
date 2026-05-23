# Morpheus — Primary Intelligence Layer Operations Manual

## Overview

**Morpheus** is the primary intelligence routing layer of the AI Production Fabric Stack. It is not a standalone service — rather, it is the collective identity of the model aliases defined in `configs/litellm/litellm.yml`, routed through the LiteLLM gateway (`ai-litellm:4000`).

When any agent or frontend references `morpheus-core`, `morpheus-deep-thought`, `morpheus-flash`, or `morpheus-qwen` as the model name, LiteLLM resolves these to the appropriate cloud provider with automatic load balancing, retry logic, and multi-tier fallback chains.

---

## Activation Checklist

Before Morpheus can take runtime leadership, the following conditions must be met:

### 1. Infrastructure Healthy
```bash
docker compose ps
# All services should show "running" with healthy status
```

### 2. LiteLLM Gateway Responsive
```bash
curl -f http://localhost:4000/health
# Expected: {"status":"healthy"} or HTTP 200
```

### 3. Provider API Keys Loaded
```bash
# Verify LiteLLM loaded env vars from .secrets:
docker compose logs ai-litellm 2>&1 | grep -i "loaded\|key\|error"
```

### 4. Model Routing Table Active
```bash
# List all registered models:
curl -s http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY" | python3 -m json.tool
# Expected: morpheus-core, morpheus-deep-thought, morpheus-flash, morpheus-qwen,
#           morpheus-free-fallback, local-processor, nomic-embed-text
```

### 5. Local Fallback (Ollama) Ready
```bash
# Verify Ollama is accessible from LiteLLM:
docker compose exec ai-litellm curl -sf http://ai-ollama:11434 && echo "Ollama reachable"

# Verify DeepSeek-R1 model is pulled:
docker compose exec ai-ollama ollama list | grep deepseek-r1
# If not pulled: docker compose exec ai-ollama ollama pull deepseek-r1:8b
```

---

## Querying Morpheus

### Via OpenAI-Compatible Endpoint

```bash
# Using morpheus-core (Tier 1 - Gemini 2.5 Pro):
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "morpheus-core",
    "messages": [{"role": "user", "content": "What is the meaning of life?"}],
    "max_tokens": 512
  }'
```

### Via Agent Configuration

**Agent-Zero** (`docker-compose.yml`):
```yaml
environment:
  - OPENAI_API_BASE=http://ai-litellm:4000/v1
  - OPENAI_API_KEY=${LITELLM_MASTER_KEY}
```

Set the model to `morpheus-core` in Agent-Zero's config file at `configs/agent-zero/`.

**n8n Workflows**:
- Use the OpenAI node with:
  - Base URL: `http://ai-litellm:4000/v1`
  - API Key: `${LITELLM_MASTER_KEY}`
  - Model: `morpheus-core` (or any Morpheus alias)

---

## Fallback Chain Behavior

When a Tier 1 or Tier 2 model fails (rate limit, API error, key exhaustion), LiteLLM automatically routes to the next tier:

```
morpheus-core (Gemini 2.5 Pro)
  └─→ morpheus-free-fallback (OpenRouter free Gemini)
       └─→ local-processor (Ollama DeepSeek-R1 8B on NVIDIA GPU)
```

**Retry parameters** (from `litellm.yml`):
- `num_retries: 3` — Each model attempt retries 3 times before falling back
- `cooldown_time: 30` — 30-second cooldown on failed providers
- `routing_strategy: round-robin` — Load-balances across duplicate model entries

---

## Monitoring Morpheus Health

### Quick Health Dashboard
```bash
echo "=== Morpheus Health Dashboard ==="
echo "LiteLLM: $(curl -sf http://localhost:4000/health > /dev/null && echo '✅ UP' || echo '❌ DOWN')"
echo "Ollama:  $(curl -sf http://localhost:11434 > /dev/null && echo '✅ UP' || echo '❌ DOWN')"
echo "SearXNG: $(curl -sf http://localhost:8080/healthz > /dev/null && echo '✅ UP' || echo '❌ DOWN')"
echo "Postgres: $(docker compose exec ai-postgres pg_isready 2>/dev/null | grep -c 'accepting' || echo '❌ DOWN')"
```

### Model-Specific Test
```bash
# Test each Morpheus alias:
for model in morpheus-core morpheus-deep-thought morpheus-flash morpheus-qwen local-processor; do
  echo -n "Testing $model... "
  status=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:4000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}")
  echo "$status"
done
```

---

## Morpheus Parameter Reference

| Parameter | Value | Description |
|---|---|---|
| **Gateway URL** | `http://ai-litellm:4000/v1` | Internal Docker DNS for all Morpheus queries |
| **External URL** | `http://localhost:4000/v1` | Host-accessible endpoint |
| **Auth** | `Bearer $LITELLM_MASTER_KEY` | Bearer token authentication |
| **Routing Strategy** | `round-robin` | Load balancing across duplicate model entries |
| **Max Retries** | `3` | Per-model retry count before fallback |
| **Cooldown** | `30s` | Failed provider cooldown period |
| **Drop Params** | `true` | Ignore unsupported parameters rather than error |

---

## Morpheus Model Matrix

| Alias | Tier | Provider | Load Balanced | Fallback Chain |
|---|---|---|---|---|
| `morpheus-core` | 1 (Premium) | OpenRouter → Gemini 2.5 Pro | Yes (2 keys) | free-fallback → local-processor |
| `morpheus-deep-thought` | 1 (Premium) | DeepSeek Reasoner | Yes (2 keys) | free-fallback → local-processor |
| `morpheus-flash` | 2 (Premium) | Gemini 1.5 Flash | Yes (1 key) | free-fallback |
| `morpheus-qwen` | 2 (Premium) | Qwen-Max (Dashscope) | Yes (2 keys) | free-fallback |
| `morpheus-free-fallback` | 3 (Free) | OpenRouter free Gemini | Yes (2 keys) | — |
| `local-processor` | 4 (Local) | Ollama DeepSeek-R1 8B | No | — |
| `nomic-embed-text` | Embedding | Ollama nomic-embed-text | No | — |

---

## Emergency Procedures

### LiteLLM Container Unhealthy
```bash
docker compose restart ai-litellm
docker compose logs -f ai-litellm  # Watch for API key or config errors
```

### All Cloud Providers Exhausted
Morpheus automatically falls back to `local-processor` (Ollama DeepSeek-R1 8B).
Ensure the model is pulled:
```bash
docker compose exec ai-ollama ollama pull deepseek-r1:8b
```

### Reset Morpheus Routing
```bash
# Re-read litellm.yml config:
docker compose restart ai-litellm

# Verify routing table reloaded:
curl -s http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```
