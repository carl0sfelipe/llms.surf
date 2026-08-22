#!/bin/bash
# check-output-invencao.sh — mecanismo de DETECÇÃO do incidente incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md (nível 5 da
# apostila 2). Roda DEPOIS do despacho: lista todo número presente no output que
# não estava na spec.
#
# Uso: bin/check-output-invencao.sh <spec_file> <output_file> [output_file...]
#
# Por que existe: bin/check-spec.sh olha a spec ANTES e só detecta ausência de
# defesa — a spec `docs-plano-e-adr.md` tinha cláusula anti-invenção e mesmo
# assim gerou "5.000 anúncios" e "2 GB de RAM", porque a cláusula era estreita.
# Este aqui olha o resultado, onde o defeito de fato aparece.
#
# Medido em 2026-07-26 contra o ADR 0001 original: recall de 100% sobre as
# invenções numéricas (pegou `2 GB` e `5.000`), com ~15 falsos positivos de
# data, numeração de lista e formatação. Escanear a lista leva segundos; deixar
# passar custa um refinamento.
#
# LIMITE DECLARADO (regra 32): só pega invenção NUMÉRICA. Não pega afirmação
# inventada em prosa — nesta mesma sessão o modelo atribuiu termos de serviço a
# Flickr e PostImage sem nenhum número envolvido, e isso passa aqui ileso.
# Para esse caso, ver a nota sobre RAGAS/faithfulness em specs/benchmark-survey.md
# secao 12.
#
# Exit: 0=nada suspeito, 1=há candidatos a revisar, 3=erro de uso

set -uo pipefail

# <spec_file> aceita lista separada por vírgula, MAS o uso correto é UMA spec,
# rodada logo depois do despacho dela.
#
# ARMADILHA MEDIDA EM 2026-07-26: incluir a spec de refinamento na comparação
# ESCONDE o defeito. A instrução de refinamento cita o texto errado para mandar
# corrigi-lo ("troque o limiar inventado de 5.000 anúncios"), então `5.000` e
# `2 GB` entram no conjunto permitido e somem do relatório — justamente os dois
# defeitos reais. Rodar tarde, contra specs acumuladas, cega a ferramenta.
#
# Protocolo: um despacho, uma spec, uma checagem, imediatamente.
# A lista por vírgula existe só para o caso de um documento ter sido escrito por
# dois despachos de CRIAÇÃO (ex.: prd-parte1 + prd-parte2), nunca de refinamento.
SPEC="${1:?Uso: check-output-invencao.sh <spec[,spec2,...]> <output_file> [...]}"
shift
[ $# -gt 0 ] || { echo "Uso: check-output-invencao.sh <spec[,spec2,...]> <output_file> [...]" >&2; exit 3; }
IFS=',' read -ra SPECS <<< "$SPEC"
for s in "${SPECS[@]}"; do [ -f "$s" ] || { echo "spec não encontrada: $s" >&2; exit 3; }; done
for f in "$@"; do [ -f "$f" ] || { echo "output não encontrado: $f" >&2; exit 3; }; done

SPEC="$SPEC" python3 - "$@" <<'PY'
import re, sys, os

# Normaliza para comparar "14MB" com "14 MB" e "1.400" com "1400".
def normalizar(s):
    return re.sub(r'[ .,]', '', s).lower()

def numeros(texto):
    achados = {}
    for m in re.finditer(r'\b(\d[\d.,]*)\s*(%|GB|MB|KB|TB|k|mil|milh[oõ]es?)?\b', texto, re.I):
        bruto = m.group(0).strip()
        achados.setdefault(normalizar(bruto), bruto)
    return achados

RUIDO = re.compile(
    r'^('
    r'\d{4}-\d{2}-\d{2}'          # data ISO
    r'|20\d{2}'                   # ano
    r'|[0-9]{1,2}'                # numeração de lista, versão curta, item
    r'|\d+\.\d+\.\d+'             # semver
    r')$'
)

spec = {}
for caminho_spec in os.environ["SPEC"].split(","):
    spec.update(numeros(open(caminho_spec).read()))
total_suspeitos = 0

for caminho in sys.argv[1:]:
    saida = numeros(open(caminho).read())
    novos = {k: v for k, v in saida.items() if k not in spec}
    # tira o ruído previsível
    novos = {k: v for k, v in novos.items() if not RUIDO.match(normalizar(v))}
    if not novos:
        print(f"OK  {caminho} — nenhum numero fora da spec")
        continue
    total_suspeitos += len(novos)
    print(f"REVISAR  {caminho} — {len(novos)} numero(s) que nao estavam na spec:")
    for v in sorted(novos.values(), key=lambda x: (len(x), x)):
        for linha_n, linha in enumerate(open(caminho), 1):
            if v in linha:
                print(f"    {v!r}  linha {linha_n}: {linha.strip()[:90]}")
                break

sys.exit(1 if total_suspeitos else 0)
PY
