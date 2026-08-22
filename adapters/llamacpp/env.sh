#!/bin/bash
# env.sh — adapter llama.cpp (llama-server local)
# Uso: source adapters/llamacpp/env.sh
ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="llamacpp"
export LLAMACPP_URL="${LLAMACPP_URL:-http://127.0.0.1:8081}"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"
export DISPATCH_RUNNER_FORMAT_JSON=0
mkdir -p "$LOG_DIR" "$PID_DIR"
