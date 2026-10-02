EXECUTE A ESPEC ABAIXO por completo (o cabeçalho YAML e as seções são contrato, não comentário).

---
id: "tr-1-3-catalogo-plano"
schema: 1
status: ready
owner: "claude-opus (orquestrador)"
modelo: "claude-sonnet-5"
tentativas: 3
bloqueio: false
evidencia: "/opt/inference/specs/06-trocador.md"
---

# TR-1 + TR-3 — catálogo de modelos e plano de troca (python puro, stdlib)

REGRAS DE OURO (violar qualquer uma = reprovação imediata):
- Workdir: /opt/inference. Escreva SÓ os arquivos listados em ENTREGÁVEIS. Não edite nenhum outro arquivo.
- NUNCA rode systemctl, docker, nvidia-smi, curl, ollama, bin/cutover-*.sh, bin/rollback-gemma.sh ou qualquer
  coisa que suba/derrube modelo. É código puro + testes. Nada de rede.
- NUNCA git commit, git push, git reset, git checkout, git stash, rm -rf.
- stdlib only (Python 3.11+: `tomllib`). Nenhum pip install.
- Nao invente numero, porta, campo, prazo ou fonte alem dos listados nesta espec. Valor nao decidido = [A DEFINIR].
- NUNCA use declare const, stub vazio ou `pass` como workaround para passar teste — implemente de verdade e importe de verdade.
- A suíte completa já tem 2 vermelhos ANTES desta tarefa (test_gates.TestRig G-HEALTH e G-REBOOT: o rig está sem modelo de pé, incidente 2026-10-02). Não tente consertá-los e não rode nada que suba modelo.
- Não edite testes existentes em tests/ nem stories/*.json nem SPEC.md nem specs/.
- Identificadores, código e comentários em inglês ou português como o repo já faz (o repo usa nomes em
  português: `vivos`, `retry_after`, `ajustar_max_tokens`) — siga o português dos contratos abaixo.

## Dados verificados (copie SEM ALTERAR)
- Spec de referência: specs/06-trocador.md §1 (catálogo) e §3 (plano). Leia antes.
- Estilo de módulo puro a imitar: gateway/ocupacao.py e gateway/politica.py (docstring de contrato, funções puras).
- Estilo de teste a imitar: tests/test_ocupacao.py (unittest, sem rede).
- Stories: stories/TR-1.json (alvo trocador/catalogo.py, teste tests.test_trocador.TestCatalogo) e
  stories/TR-3.json (alvo trocador/plano.py, teste tests.test_trocador.TestPlano).

## Objetivo

### 1. `trocador/__init__.py` (vazio) e `trocador/catalogo.py`
```python
TIPOS = {"chat", "visao", "audio", "asr", "tts", "imagem", "video", "3d", "embed"}
BACKENDS = {"exllamav3", "vllm-docker", "comfyui", "whisper", "llamacpp", "ollama"}
ROTAS = {"openai", "nenhuma"}
CAMPOS = ("id", "tipo", "backend", "porta", "saude", "rota", "vram_gb", "carga_s", "coabita", "comando")

class CatalogoInvalido(ValueError): ...

def validar(doc: dict, nome_arquivo: str) -> list[str]:
    """Lista de problemas (vazia = válido): campo faltando; id != stem do nome_arquivo; tipo não-lista,
    vazia ou com valor fora de TIPOS; backend fora de BACKENDS; rota fora de ROTAS; porta int fora de
    1..65535; saude str começando com "/"; vram_gb número >= 0; carga_s número >= 0; coabita bool;
    comando str não-vazia. Cada problema começa com f"{nome_arquivo}: "."""

def carregar(pasta) -> dict[str, dict]:
    """Lê pasta/*.toml (ordem alfabética) com tomllib; junta TODOS os problemas de todos os arquivos
    (validar + id duplicado + TOML inválido) e levanta CatalogoInvalido com eles em linhas; pasta vazia
    ou inexistente também é inválida. Sem problemas: {id: doc}."""

def medido(doc: dict) -> bool:
    """vram_gb > 0 e carga_s > 0 (0 = não medido)."""
```

### 2. `trocador/plano.py`
```python
def plano(carregados: list[str], alvo: str, catalogo: dict[str, dict],
          vram_total_gb: float, reserva_gb: float) -> list[tuple[str, str]]:
    """Ações ordenadas para deixar `alvo` de pé. Função pura.
    - alvo fora do catálogo, ou não medido(), ou vram_gb do alvo > vram_total_gb - reserva_gb → ValueError
      (mensagem diz qual dos três).
    - alvo já em carregados → [].
    - Modelos com coabita=False são mutuamente exclusivos; coabita=True dividem a placa se a VRAM couber.
    - Algoritmo: parar = [m for m in carregados if not coabita(m)] se o alvo NÃO coabita, senão [];
      restantes = carregados sem os de parar (ordem original); enquanto soma(vram restantes) + vram(alvo)
      > vram_total_gb - reserva_gb: tire o ÚLTIMO de restantes e acrescente em parar.
    - Retorno: [("parar", m) para m em carregados que estão em parar, na ordem de carregados] + [("subir", alvo)].
    - Modelo carregado que não está no catálogo conta como coabita=False e vram 0 (é parado se o alvo não coabita)."""
```

### 3. `modelos/*.toml` — 4 entradas iniciais (vram_gb = 0.0 e carga_s = 0: ainda não medidos)
| arquivo | tipo | backend | porta | saude | rota | coabita |
|---|---|---|---|---|---|---|
| qwen-3.8-27b.toml | ["chat"] | exllamav3 | 8888 | /v1/models | openai | false |
| gemma-4-12b.toml | ["chat","visao","audio"] | vllm-docker | 8000 | /v1/models | openai | false |
| whisper-turbo.toml | ["asr"] | whisper | 8890 | /v1/models | openai | true |
| qwen-image.toml | ["imagem"] | comfyui | 8188 | /system_stats | nenhuma | false |
`comando = "bin/modelo-serve.sh <id>"` em todos.

### 4. `tests/test_trocador.py`
`TestCatalogo`: carrega o modelos/ real (4 ids); cada regra de validar() tem um caso inválido (pasta temporária);
id duplicado; TOML quebrado; pasta vazia; medido().
`TestPlano`: alvo já carregado → []; LLM → outro LLM (para o 1º, sobe o 2º); whisper (coabita) fica ao lado de LLM
quando cabe; whisper é parado quando não cabe; alvo coabita ao lado de LLM sem parar nada; não medido → ValueError;
não cabe sozinho → ValueError; fora do catálogo → ValueError; carregado desconhecido é parado; ordem do retorno.
Use catálogos sintéticos com números medidos nos testes de plano (não dependa de modelos/).

## Barra
- nome: tests.test_trocador verde; gates portáveis verdes (bin/gates.sh --local); nenhum teste novo vermelho
- como fetchar: cd /opt/inference && python3 -m unittest tests.test_trocador -v
- como comparar: todos os testes passam; nenhum arquivo fora de ENTREGÁVEIS alterado (git status)

## Passos
1. Leia specs/06-trocador.md, gateway/ocupacao.py, tests/test_ocupacao.py, stories/TR-1.json, stories/TR-3.json.
2. Escreva os testes primeiro (devem falhar), depois trocador/catalogo.py e trocador/plano.py, depois modelos/*.toml.
3. Rode a VERIFICAÇÃO até verde.

## ENTREGÁVEIS
- trocador/__init__.py
- trocador/catalogo.py (≤ 90 linhas)
- trocador/plano.py (≤ 70 linhas)
- modelos/qwen-3.8-27b.toml, modelos/gemma-4-12b.toml, modelos/whisper-turbo.toml, modelos/qwen-image.toml
- tests/test_trocador.py

## VERIFICAÇÃO
- cd /opt/inference && python3 -m unittest tests.test_trocador -v
- cd /opt/inference && bin/gates.sh --local
- cd /opt/inference && python3 -m unittest discover tests 2>&1 | grep -E '^(FAIL|ERROR):' (só G-HEALTH e G-REBOOT podem aparecer)

## Oráculo
- comando: cd /opt/inference && python3 -m unittest tests.test_trocador -q && bin/gates.sh --local && python3 -c "import sys; sys.path.insert(0,'.'); from trocador.catalogo import carregar; c=carregar('modelos'); assert sorted(c)==['gemma-4-12b','qwen-3.8-27b','qwen-image','whisper-turbo'], sorted(c)"
