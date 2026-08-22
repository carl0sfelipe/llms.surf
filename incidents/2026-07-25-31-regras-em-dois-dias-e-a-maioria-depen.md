---
id: 2026-07-25-31-regras-em-dois-dias-e-a-maioria-depen
titulo: 31 regras em dois dias, e 58% delas só existem como texto
data: 2026-07-25
recorrivel: sim
interage_com: 16 e 23 (são as que produzem regra — este incidente questiona o RITMO e a EFICÁCIA do que elas produzem); 1 (exemplo de regra-texto que induziu decisão errada); 22, 26, 31 (regras que eu violei DEPOIS de escrevê-las). RISCO: lido como "criar menos regras", vira desculpa para não registrar incidente — o problema não é o número, é regra sem mecanismo.
regra: 32
status: promovido
---

# 31 regras em dois dias, e 58% delas só existem como texto

## Sintoma

Em dois dias: **16 incidentes registrados, 31 regras** — 20 delas criadas neste
período. O ritmo é o sintoma. Uma base de regras que cresce 180% em dois dias ou
descreve um domínio excepcionalmente traiçoeiro, ou está sendo usada como
substituto de correção estrutural.

Pior: **eu violei regras que eu mesmo havia escrito horas antes.**

| Regra | Violada por mim depois de escrita |
|---|---|
| 9 (cheque log antes de escalar) | escalei ao Sonnet sem abrir o log → virou regra 22 |
| 16/23 (problema recorrente vira regra, por default) | descrevi a lição e não registrei — **duas vezes**, ambas cobradas pelo usuário |
| 24 (medição errada vira dado) | caí em `$?` depois de pipe **duas vezes depois** de escrever a regra |
| 12 (nada sem teto) | rodei teste sem teto no próprio teste da regra |

## Causa

Contagem objetiva das 31 regras, por existir mecanismo que as faça valer:

- **13 têm código que impõe**: 12, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30
  (`with-timeout.sh`, `incident.sh audit`, `pre-dispatch-check.sh`, sandbox do
  `verify-models.sh`, `diagnose-hang.sh`, `run-check.sh`…)
- **18 são só texto**: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 22, 26, 29, 31

**58% depende de disciplina do operador.** E todas as violações listadas acima
são de regras desse grupo. As que têm mecanismo não foram violadas nenhuma vez —
não por virtude, mas porque o código não deixa.

Segundo achado: a regra que mais custou hoje foi a **1** ("nunca escreva bulk,
despache"), que é texto puro. Ela me levou a despachar transformação
determinística a um modelo, que devolveu exit 0 sem fazer nada. Regra-texto não
só falha em impedir erro — ela pode **induzir** erro quando não distingue
contexto.

Terceiro: o `bin/incident.sh audit` verifica dívida de incidente **registrado**.
Não detecta incidente que nunca foi criado, nem regra violada. O mecanismo de
auditoria não cobre justamente o modo de falha mais frequente.

## Correção aplicada

Nenhuma ainda. As direções, em ordem de valor:

1. **Toda regra nova declara seu mecanismo** — ou o código que a impõe, ou
   explicitamente "sem mecanismo, depende de disciplina". Sem esse campo, não se
   sabe quais regras são reais e quais são intenção.
2. **Regra sem mecanismo é dívida**, não entrega. Deveria aparecer no `audit`.
3. **Consolidar antes de acrescentar**: 31 regras é mais do que qualquer agente lê
   antes de agir. Regra que ninguém lê não protege — a regra 23 já diz isso e foi
   ignorada por mim mesmo ao criar 20 em dois dias.

## Pode acontecer de novo?

**Está acontecendo agora.** Este incidente é o 16º, e vai gerar a regra 32 — em
texto, sem mecanismo, exatamente o padrão que ele critica.
