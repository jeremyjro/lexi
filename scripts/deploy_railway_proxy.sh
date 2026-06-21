#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v railway >/dev/null 2>&1; then
  echo "Railway CLI is not installed. Install it first: https://docs.railway.app/guides/cli"
  exit 1
fi

if ! railway whoami >/dev/null 2>&1; then
  echo "Railway CLI is not authenticated. Run: railway login"
  exit 1
fi

cd "$ROOT_DIR"

if ! railway status >/dev/null 2>&1; then
  echo "This repo is not linked to a Railway project. Run: railway link"
  exit 1
fi

npm run typecheck --prefix "$ROOT_DIR/proxy"
npm run build --prefix "$ROOT_DIR/proxy"
railway up
