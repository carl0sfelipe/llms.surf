---
id: 2026-07-29-spec-com-dado-inventado-passou-no-gate
titulo: spec com dado inventado passou no gate
data: 2026-07-29
recorrivel: sim
regra: 37
status: promovido
---

# spec com dado inventado passou no gate

## Sintoma

O orquestrador (Claude) escreveu a spec `specs/dedupe-observability-leadher.md` para migrar o `observability` local do repo `leadher.living`. O passo 3 da spec dizia, em prosa: em `apps/backend/vitest.config.ts` existe o glob `src/observability` mais `__tests__`, e mandava remover. Esse glob **não existe** no `leadher.living` — o `vitest.config.ts` dele tem `include` com apenas `src/modules` e `src/admin`. O glob de `observability` está no **outro** repo, `<repo-cliente>.live-imports`, na linha 11 do `vitest.config.ts` dele. A spec passou nos 5 checks de `bin/check-spec.sh` e foi despachada. O modelo executor (`deepseek-v4-flash`) fez os dois passos válidos, foi olhar o `vitest.config.ts`, não achou o glob, **não inventou**, e reportou no log: o glob não existe no arquivo.

## Causa

`bin/check-spec.sh` detecta **ausência de cláusula anti-invenção** — ele confere que a spec PROÍBE o modelo de inventar. Não confere se o bloco `## Dados verificados` é verdade. O bloco é aceito por fé. A assimetria: a cláusula anti-invenção protege contra invenção de quem **lê** a spec — foi o que motivou o incidente `2026-07-26-spec-sem-clausula-anti-invencao-gera-num` e a criação do `check-spec.sh`. Não havia nada protegendo contra invenção de quem a **escreve**.

## Correção aplicada

Criado `bin/check-spec-facts.py`, que coleta cada literal entre backticks do bloco `## Dados verificados` **e** de qualquer frase que afirme existência em qualquer seção, e exige que cada literal exista no workdir. `bin/dispatch-batch.sh` passou a chamá-lo no gate, junto do `check-spec.sh`. A **primeira** versão do `check-spec-facts.py` deu VERDE na spec defeituosa, por dois motivos: (1) só olhava a seção `## Dados verificados`, e a frase falsa estava sob `## O que fazer`; (2) o split de frases quebrava na dobra de linha do markdown, separando o verbo "existe" do literal que vinha na linha seguinte. Ambos corrigidos. Medição sobre as 4 specs deste dia: as 3 factualmente corretas passam, a defeituosa reprova apontando o literal e a frase exatos. Precisão 4/4 num conjunto de **4** specs — amostra pequena, declarada.

## Pode acontecer de novo?

Sim. O script prova que o literal existe **em algum lugar** do workdir, não que esteja no arquivo e na linha que a spec afirma. Um orquestrador pode citar um literal real mas no contexto errado (outro repositório, outro arquivo, outro diretório), e o script passa. Essa verificação continua sendo trabalho humano.
interage_com: **reforça** a 35 (que a 37 promove de passo a código) e a 26
(ausência só se provada — aqui era o inverso: PRESENÇA afirmada sem prova).
**Restringe** a 1: o orquestrador escreve pouco, e justamente por isso o pouco
que escreve concentra risco — bloco de dados verificados é o output dele.
**Não supera nenhuma.** O que a combinação 37 + 1 pode quebrar: spec de CRIAÇÃO
cita literal que ainda não existe. O `check-spec-facts.py` só cobra existência
do bloco de dados verificados e de frases que AFIRMAM presente; literal em frase
imperativa fica livre. Se essa distinção for perdida, toda spec de criação
reprova.
