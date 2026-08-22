#!/usr/bin/env python3
"""Motor de checagem determinística da suíte de verificação.

Spec: core/verify-suite-spec.md. Consumido por bin/verify-models.sh.

Projeto: ZERO LLM-as-judge. Se medir exigisse um modelo julgando outro, a medição
herdaria a incerteza, o custo e o rate limit do juiz. Toda decisão aqui é mecânica,
o que também torna a suíte extensível por modelo leve: adicionar tarefa é
acrescentar um objeto JSON, sem tocar neste arquivo.

Uso:
    lib-check.py <suite.json> <indice_da_task> <arquivo_com_resposta>
Saída:
    linha 1: PASS ou FAIL
    linha 2: motivo curto (vazio se PASS)
Exit: 0 se PASS, 1 se FAIL, 3 se erro de uso/suíte inválida.
"""

import json
import re
import sys


def normaliza(texto: str) -> str:
    """Normalização conservadora para comparação de igualdade.

    Remove cercas de código, espaço nas pontas e pontuação final — nada além
    disso: normalizar demais transforma resposta errada em 'certa'.
    """
    t = texto.replace("\r", "")
    t = re.sub(r"```[a-zA-Z]*", "", t)
    t = t.strip()
    t = re.sub(r"[ \t]+", " ", t)
    return t.rstrip(".!")


def linhas_uteis(texto: str) -> list[str]:
    return [l for l in texto.splitlines() if l.strip()]


def checa(check: dict, resposta: str) -> tuple[bool, str]:
    tipo = check.get("tipo")

    if tipo == "exato":
        esperado = normaliza(str(check["esperado"]))
        obtido = normaliza(resposta)
        # resposta de uma linha pode vir com preâmbulo; compara também a última linha
        if obtido == esperado:
            return True, ""
        ultimas = linhas_uteis(resposta)
        if ultimas and normaliza(ultimas[-1]) == esperado:
            return True, ""
        return False, f"esperado '{esperado}', obtido '{obtido[:60]}'"

    if tipo == "contem_todos":
        baixa = resposta.lower()
        faltando = [t for t in check["termos"] if t.lower() not in baixa]
        if faltando:
            return False, "faltou: " + ", ".join(faltando[:4])
        return True, ""

    if tipo == "nao_contem":
        baixa = resposta.lower()
        achados = [t for t in check["termos"] if t.lower() in baixa]
        if achados:
            return False, "não devia conter: " + ", ".join(achados[:4])
        return True, ""

    if tipo == "regex":
        if re.search(check["padrao"], resposta, re.MULTILINE):
            return True, ""
        return False, f"regex não casou: {check['padrao'][:50]}"

    if tipo == "min_linhas":
        n = int(check["n"])
        tem = len(linhas_uteis(resposta))
        if tem >= n:
            return True, ""
        return False, f"{tem} linhas, mínimo {n}"

    if tipo == "json_igual":
        bruto = re.sub(r"```[a-zA-Z]*", "", resposta).strip()
        # tolera preâmbulo: tenta o primeiro bloco {...} ou [...] equilibrado
        candidatos = [bruto]
        m = re.search(r"[\{\[].*[\}\]]", bruto, re.DOTALL)
        if m:
            candidatos.append(m.group(0))
        for c in candidatos:
            try:
                if json.loads(c) == check["esperado"]:
                    return True, ""
            except Exception:
                continue
        return False, f"JSON diferente ou inválido: '{bruto[:60]}'"

    if tipo == "combinado":
        for sub in check["checks"]:
            ok, motivo = checa(sub, resposta)
            if not ok:
                return False, f"[{sub.get('tipo')}] {motivo}"
        return True, ""

    return False, f"tipo de check desconhecido: {tipo}"


def main() -> int:
    if len(sys.argv) != 4:
        print("FAIL")
        print("uso: lib-check.py <suite.json> <indice> <arquivo_resposta>")
        return 3
    suite_path, idx_raw, resp_path = sys.argv[1:4]
    try:
        suite = json.load(open(suite_path))
        task = suite["tasks"][int(idx_raw)]
    except Exception as e:
        print("FAIL")
        print(f"suíte inválida: {e}")
        return 3

    check = task.get("check")
    if not isinstance(check, dict):
        print("FAIL")
        print(f"task '{task.get('id')}' sem campo check (ver core/verify-suite-spec.md)")
        return 3

    try:
        resposta = open(resp_path, encoding="utf-8", errors="replace").read()
    except Exception as e:
        print("FAIL")
        print(f"resposta ilegível: {e}")
        return 3

    ok, motivo = checa(check, resposta)
    print("PASS" if ok else "FAIL")
    print(motivo)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
