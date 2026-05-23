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
