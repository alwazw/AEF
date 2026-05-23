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

# Check if UFW is installed
if ! command -v ufw &>/dev/null; then
    echo "❌ UFW is not installed. Install with: sudo apt install ufw"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Must run as root. Use: sudo bash $0"
    exit 1
fi

echo "📋 Opening required ports..."

# SSH — never lock yourself out
echo "  ✅ SSH (22/tcp) — preserving existing access"
ufw allow 22/tcp comment "SSH access" 2>/dev/null || true

# Caddy — HTTP + HTTPS (the only public-facing ports)
echo "  ✅ HTTP (80/tcp) — Caddy reverse proxy + Let's Encrypt ACME"
ufw allow 80/tcp comment "Caddy HTTP / ACME challenge"

echo "  ✅ HTTPS (443/tcp) — Caddy reverse proxy with TLS"
ufw allow 443/tcp comment "Caddy HTTPS / TLS termination"

# Direct-access ports (optional — comment out if using Caddy only)
echo "  ✅ Open WebUI (3000/tcp) — direct access fallback"
ufw allow 3000/tcp comment "Open WebUI direct access"

echo "  ✅ LiteLLM (4000/tcp) — direct API access fallback"
ufw allow 4000/tcp comment "LiteLLM direct API access"

echo "  ✅ n8n (5678/tcp) — direct access fallback"
ufw allow 5678/tcp comment "n8n direct access"

echo "  ✅ Qdrant (6333/tcp) — vector DB direct access"
ufw allow 6333/tcp comment "Qdrant direct access"

echo ""
echo "📋 Blocking unnecessary ports..."
echo "  🚫 Ollama (11434/tcp) — internal only, not exposed"
ufw deny 11434/tcp 2>/dev/null || true
echo "  🚫 Redis (6379/tcp) — internal only, not exposed"
ufw deny 6379/tcp 2>/dev/null || true
echo "  🚫 Postgres (5432/tcp) — internal only, not exposed"
ufw deny 5432/tcp 2>/dev/null || true

echo ""
echo "🔒 Enabling UFW..."
echo "y" | ufw enable

echo ""
echo "==============================================================="
echo "✅ UFW rules applied successfully"
echo "==============================================================="
echo ""
echo "📊 Current firewall status:"
ufw status numbered
echo ""
echo "💡 To switch to Caddy-only access (close direct ports):"
echo "   sudo ufw delete allow 3000/tcp"
echo "   sudo ufw delete allow 4000/tcp"
echo "   sudo ufw delete allow 5678/tcp"
echo "   sudo ufw delete allow 6333/tcp"
echo "==============================================================="
