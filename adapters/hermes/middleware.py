#!/usr/bin/env python3
"""Esqueleto do smart dispatcher para o Hermes Agent (RF-02.2).

Portado das seções 2-5 de specs/free-model-ecosystem.md. NÃO é implementação
pronta: cada função marcada `NotImplementedError` é um ponto de extensão.
O que já está implementado aqui é só o que pode ser derivado do
model-registry.json sem inventar dado (PRD seção 11, regra 2).

Uso pretendido (quando completo): middleware que intercepta a chamada de LLM,
classifica a tarefa, escolhe o modelo e executa com fallback em cascata.

    from middleware import select_model, fallback_chain
    model = select_model(task_type="code", prompt_tokens=3000)
    for candidate in fallback_chain(model):
        ...
"""

from __future__ import annotations

import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = Path(os.environ.get("MODEL_REGISTRY", REPO_ROOT / "model-registry.json"))

CLI = "hermes"


def load_registry(path: Path = REGISTRY_PATH) -> list[dict]:
    """Carrega model-registry.json. Única fonte de model ids (regra 11.2)."""
    with open(path) as fh:
        return json.load(fh)["models"]


def available_for_cli(models: list[dict] | None = None, cli: str = CLI) -> list[dict]:
    """Modelos com cli_hint para este CLI.

    Ausência de hint = modelo indisponível aqui (PRD 4.3). Não presumir
    cobertura, não derivar hint por concatenação de prefixo.
    """
    models = models if models is not None else load_registry()
    return [m for m in models if m.get("cli_hints", {}).get(cli)]


def fallback_chain(model_id: str, models: list[dict] | None = None) -> list[str]:
    """Cadeia de fallback do modelo, conforme campo `fallback` do registry (RF-08).

    Retorna [model_id, *fallbacks]. Consumidor tenta em ordem quando o runner
    devolve exit 2 (rate limit) ou exit 4 (quota exausta).
    """
    models = models if models is not None else load_registry()
    for m in models:
        if m["id"] == model_id:
            return [model_id, *m.get("fallback", [])]
    raise KeyError(f"modelo {model_id} ausente do model-registry.json")


def classify(prompt: str) -> str:
    """Classifica o prompt em code/reasoning/text/vision/audio/agentic/long_context.

    Especificado em specs/free-model-ecosystem.md seção 3. Fora do escopo desta
    reformulação (PRD seção 10: classificador é PRD futuro).
    """
    raise NotImplementedError(
        "classificador é fase futura — ver specs/free-model-ecosystem.md seção 3"
    )


def select_model(task_type: str, prompt_tokens: int) -> str:
    """Escolhe o melhor modelo para (tipo, tamanho), preferindo tier free.

    Tabela de decisão em specs/free-model-ecosystem.md seção 5.1. Depende de
    `best_for` e `context_window` do registry — ambos já presentes com campo
    `source` rastreável.
    """
    raise NotImplementedError(
        "selector é fase futura — regras em specs/free-model-ecosystem.md seção 5.1"
    )


if __name__ == "__main__":
    disponiveis = available_for_cli()
    print(f"modelos com cli_hint para {CLI}: {len(disponiveis)}")
    for m in disponiveis:
        print(f"  {m['id']} -> {m['cli_hints'][CLI]}")
