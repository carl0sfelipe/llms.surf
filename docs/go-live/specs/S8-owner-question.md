# S8 — a pergunta do dono no unlock_plan (uma pergunta, garfo anexado)

Padrão capturado (medição real da sessão de 2026-08-29): quando o estágio
caro está bloqueado por um fato que só o dono tem, UMA pergunta com o garfo
de consequências já anexado — "se A → faço X; se B → faço Y" — custa uma
fração de uma tentativa cara preenchendo o buraco com invenção, e destrava
na primeira resposta. O contrário também foi medido: sem a pergunta, o
estágio caro queima tentativas adivinhando (a cláusula anti-invenção reprova
o chute, mas cada reprovação custou o token caro).

## Contrato executável

1. Um stage declara `owner_question: once` no YAML do modo. O loader valida
   o campo (bool true ou string não-vazia); o runtime do multi-stage
   (bin/dispatch-stages.sh) injeta na spec do stage o contrato da pergunta.
2. O modelo, bloqueado em fato que só o dono tem, escreve
   `owner-question.md` no SEU diretório de artifacts com o formato exato:

       pergunta: <uma pergunta única, o fato que só o dono tem>
       se <resposta A> -> <o que eu faço se A>
       se <resposta B> -> <o que eu faço se B>

   O garfo é obrigatório: no mínimo DUAS linhas "se ... -> ...". Pergunta
   sem garfo não pausa nada — é reprovação comum.
3. O runtime detecta o arquivo DEPOIS do runner e ANTES do oráculo: pergunta
   válida ⇒ o run PAUSA com status `owner_question` (exit 7), a pergunta é
   copiada para o inbox (`<run_id>.question.md`) e o evento
   `owner_question` é emitido. Nenhuma tentativa cara adicional é queimada.
4. O dono responde uma vez: `oracfit resume <run_id> "<resposta>"`. O resume
   injeta a resposta na spec do próximo attempt (mesma maquinaria de inbox
   do HITL) e o run retoma do estágio onde parou.
5. UMA pergunta por run_id: se o inbox já tem `<run_id>.question.md`, um
   novo owner-question.md é IGNORADO (o oráculo governa). A pergunta não é
   escape do oráculo — é atalho para a informação que ele não pode inferir.
6. Arquivo malformado (sem `pergunta:` ou com menos de 2 linhas de garfo) é
   ignorado com aviso — o oráculo decide como sempre.
7. `core/modes/unlock_plan.yaml` passa a declarar `owner_question: once` no
   estágio unlock (o caro). Modos que não declaram não mudam em nada.

## Regras

Nao invente numero, prazo, fonte ou comportamento alem dos listados.
Nao use declare const como workaround — o contrato é arquivo no disco lido
pelo runtime, não promessa no prompt.

## Dados verificados

- Existe `bin/dispatch-stages.sh` neste tree.
- Existe `bin/lib-oracfit-mode-loader.py` neste tree.
- Existe `core/modes/unlock_plan.yaml` neste tree.
- Existe `bin/oracfit` neste tree.

## Verificação

O loop inteiro provado por teste mecânico com stub, sem rede:

VERIFICACAO: test -f tests/test-owner-question.sh && bash tests/test-owner-question.sh

## Oráculo

- comando: test -f tests/test-owner-question.sh && bash tests/test-owner-question.sh
- exit esperado: 0 = pausa na pergunta (exit 7, status owner_question,
  pergunta no inbox), resposta via oracfit resume completa o run verde, a
  segunda pergunta no mesmo run_id é ignorada, e pergunta malformada não
  pausa. Antes da implementação este comando falha com exit 1 limpo (o teste
  não existe) — falta de trabalho, não oráculo quebrado.

## Barra

Referência nomeada: bin/dispatch-stages.sh (runtime que executa o unlock_plan)
e o par pergunta/resposta medido na sessão de 2026-08-29 (a pergunta que
destravou o merge custou uma fração das tentativas que a ausência de resposta
estava queimando). Passar na barra é o unlock_plan dogfooding o próprio
produto: o estágio caro pergunta barato em vez de inventar caro.
