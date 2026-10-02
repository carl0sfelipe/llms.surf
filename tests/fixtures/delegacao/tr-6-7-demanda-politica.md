EXECUTE A ESPEC ABAIXO por completo (o cabeçalho YAML e as seções são contrato, não comentário).

---
id: "tr-6-7-demanda-politica"
schema: 1
status: ready
owner: "claude-opus (orquestrador)"
modelo: "claude-sonnet-5"
tentativas: 3
bloqueio: false
evidencia: "/opt/inference/specs/06-trocador.md"
---

# TR-6 + TR-7 — fila de demanda e política de troca (python puro, stdlib)

REGRAS DE OURO (violar qualquer uma = reprovação imediata):
- Workdir: /opt/inference. Escreva SÓ os arquivos listados em ENTREGÁVEIS. Não edite nenhum outro arquivo.
- NUNCA rode systemctl, docker, nvidia-smi, curl, ollama, bin/cutover-*.sh, bin/rollback-gemma.sh ou qualquer
  coisa que suba/derrube modelo. O rig está servindo agora (Qwen + Whisper). É código puro + testes. Nada de rede.
- NUNCA git commit, git push, git reset, git checkout, git switch, git stash, rm -rf.
- stdlib only. Nenhum pip install.
- Nao invente numero, campo, regra, prazo ou fonte alem dos listados nesta espec. Valor nao decidido = [A DEFINIR].
- NUNCA use declare const, stub vazio ou `pass` como workaround para passar teste — implemente de verdade e importe de verdade.
- Em tests/test_trocador.py: ACRESCENTE as classes TestDemanda e TestPolitica no fim. Não altere TestCatalogo nem
  TestPlano nem os imports que elas usam (pode acrescentar imports novos).
- Não edite stories/*.json, SPEC.md, specs/, trocador/catalogo.py, trocador/plano.py, modelos/.

## Dados verificados (copie SEM ALTERAR)
- Spec de referência: specs/06-trocador.md §4 (política) e §5 (caminhos de pedido). Leia antes.
- Módulos já verdes para imitar o estilo e reusar: trocador/catalogo.py (`medido`), trocador/plano.py.
- Formato de pedido: specs/02-agente-md.md (frontmatter entre linhas `---`). Pedidos ficam em pedidos/*.md;
  arquivos que começam com `_` são documentação e não são pedido.
- Stories: stories/TR-6.json (trocador/demanda.py, tests.test_trocador.TestDemanda) e stories/TR-7.json
  (trocador/politica.py, tests.test_trocador.TestPolitica).

## Objetivo

### 1. `trocador/demanda.py` (TR-6, ≤ 60 linhas)
```python
def registrar(caminho, modelo: str, origem: str, agora: float, pedido_id: str | None = None) -> None:
    """Acrescenta uma linha JSON {"t": agora, "modelo": modelo, "origem": origem, "id": pedido_id} em `caminho`
    (cria a pasta-mãe se faltar). origem é "http" ou "pedido"; outro valor → ValueError."""

def ler(caminho, agora: float, janela_s: float = 1800) -> dict[str, list[float]]:
    """{modelo: [t, ...] ordenados} só com linhas de t > agora - janela_s. Arquivo ausente → {}.
    Linha que não é JSON ou sem "t"/"modelo" é ignorada (nunca levanta)."""

def pedidos_pendentes(pasta) -> dict[str, list[float]]:
    """{modelo: [mtime, ...] ordenados} dos pedidos/*.md cujo frontmatter (entre a 1ª e a 2ª linha "---") tem
    "modelo: <id>". Ignora arquivos que começam com "_", sem frontmatter ou sem modelo. Pasta ausente → {}.
    Só lê o diretório de topo (não entra em .em-curso/, feito/, falhou/)."""

def juntar(*filas: dict[str, list[float]]) -> dict[str, list[float]]:
    """Uma fila só: concatena as listas por modelo e ordena cada uma."""
```

### 2. `trocador/politica.py` (TR-7, ≤ 90 linhas)
```python
OCIOSO_S = 120   # carregado parado há tanto tempo → pode trocar se outro tem fila
FATOR = 3        # custo de espera do outro > FATOR × carga_s dele → pode trocar (passada a trava)
TRAVA_S = 600    # carregado de pé há menos que isso não é trocado por custo (anti-vaivém)

def custo(fila: list[float], agora: float) -> float:
    """Σ (agora - t) — a espera acumulada de quem está na fila."""

def decidir(estado: dict, filas: dict[str, list[float]], catalogo: dict[str, dict], agora: float,
            forcar: str | None = None) -> str | None:
    """Qual modelo subir agora, ou None. Função pura.
    estado = {"carregados": [ids], "desde": {id: t_subiu}, "ultimo_uso": {id: t}, "em_curso": bool, "util_gb": float}
    principal = o 1º de carregados com coabita=False (None se não houver).
    score(m) = custo(filas[m], agora) / catalogo[m]["carga_s"]; empate → menor id em ordem alfabética.
    Regras, nesta ordem (a primeira que decide, decide):
    1. forcar ("trocar agora" do dono): fora do catálogo ou não medido → ValueError; já em carregados → None;
       em_curso e forcar NÃO coabita → None (espera a geração terminar); senão → forcar. Ignora trava e filas.
    2. Coabitante cabe ao lado: entre m fora de carregados, medido, coabita=True, com fila não-vazia e
       vram_gb(m) + Σ vram_gb(carregados no catálogo) <= util_gb → o de maior score. (Não derruba ninguém.)
    3. em_curso → None.
    4. principal com fila não-vazia → None (esvazia o lote dele primeiro).
    5. candidatos = m fora de carregados, no catálogo, medido, com fila não-vazia. Nenhum → None.
    6. escolhido = maior score entre candidatos.
    7. principal None → escolhido.
    8. agora - estado["ultimo_uso"].get(principal, estado["desde"][principal]) >= OCIOSO_S → escolhido.
    9. agora - estado["desde"][principal] >= TRAVA_S e custo(filas[escolhido]) > FATOR × carga_s(escolhido) → escolhido.
    10. senão → None."""
```

### 3. Testes — classes novas no fim de `tests/test_trocador.py`
`TestDemanda`: registrar+ler ida e volta (pasta temporária); janela corta antigos; origem inválida → ValueError;
linhas lixo ignoradas; arquivo ausente → {}; pedidos_pendentes com frontmatter válido, sem modelo, arquivo "_LEIA-ME.md",
subpasta feito/ ignorada; juntar ordena.
`TestPolitica` (catálogo sintético com números medidos; relógio = números fixos): uma regra por teste, de 1 a 10,
incluindo: forcar ignora trava; forcar espera geração em curso; forcar de coabitante não espera; whisper sobe ao lado
do LLM ocupado quando cabe e NÃO sobe por esta regra quando não cabe; lote do principal bloqueia troca; ocioso troca;
trava impede troca por custo antes de 600 s e permite depois; score prefere carga rápida; empate alfabético;
modelo não medido nunca é candidato.

## Barra
- nome: tests.test_trocador inteiro verde (as 4 classes); gates portáveis verdes
- como fetchar: cd /opt/inference && python3 -m unittest tests.test_trocador -v
- como comparar: todos passam; git status mostra só os ENTREGÁVEIS como novos/alterados

## Passos
1. Leia specs/06-trocador.md, trocador/catalogo.py, trocador/plano.py, tests/test_trocador.py, stories/TR-6.json, stories/TR-7.json.
2. Escreva os testes primeiro, depois trocador/demanda.py e trocador/politica.py.
3. Rode a VERIFICAÇÃO até verde.

## ENTREGÁVEIS
- trocador/demanda.py (≤ 60 linhas)
- trocador/politica.py (≤ 90 linhas)
- tests/test_trocador.py (só ACRÉSCIMO de TestDemanda e TestPolitica)

## VERIFICAÇÃO
- cd /opt/inference && python3 -m unittest tests.test_trocador -v
- cd /opt/inference && bin/gates.sh --local

## Oráculo
- comando: cd /opt/inference && python3 -m unittest tests.test_trocador.TestDemanda tests.test_trocador.TestPolitica tests.test_trocador.TestCatalogo tests.test_trocador.TestPlano -q && bin/gates.sh --local && test $(wc -l < trocador/demanda.py) -le 60 && test $(wc -l < trocador/politica.py) -le 90
