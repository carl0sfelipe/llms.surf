# Paralelismo no desenvolvimento de software: a forma Bend, em Rust hoje

Fable, 2026-09-19. Provocado pela bateria P1: 17 agentes em paralelo,
uma integração em série, uma decisão (L3) bloqueando 3 specs. Pergunta do
dono: como resolver o paralelismo *no desenvolvimento*, como o Bend 2
ajuda, e o que fazer em Rust agora para estar pronto quando a geração de
código ficar barata e abundante.

## 1. O diagnóstico é o do Bend: estado mutável compartilhado

O Bend não tem threads nem locks porque o modelo de dados **proíbe
alias de coisa mutável**: computações se dividem, rodam, se juntam; o
resultado é único independente da ordem (confluência). Um codebase é o
oposto: um heap mutável gigante (arquivos) que N agentes escrevem ao
mesmo tempo. As colisões da onda 2 (T14/T15/T16 no mesmo `src/lib.rs`),
o `cases.json` como array único, o lock por `.git` — tudo é *data race*
com outro nome. A integração T11 é o lock global. L3 é a seção crítica.

Lei de Amdahl: com geração barata, o speedup é limitado pela fração
serial — **verificação, integração e decisão**. Foi exatamente o que
medimos: gerar 17 relatórios foi paralelo; decidir L3 e fundir foi
serial e dominou o wall-clock.

## 2. Tradução das quatro ideias do Bend para desenvolvimento

| Bend (computação) | Desenvolvimento (agentes) | Mecanismo concreto |
|---|---|---|
| Afinidade: um recurso, um dono | **Footprint declarado**: cada tarefa lista `writes:` e `reads:`; dois writes iguais nunca rodam juntos (condições de Bernstein) | frontmatter na spec + orquestrador que computa o grafo de conflito antes de spawnar |
| Split recursivo pela forma dos dados | **Forma do repo determina o paralelismo**: um crate por pilar, um módulo por função com lei, **um arquivo por vetor**, um arquivo por decisão (conjuntos grow-only não colidem) | `vectors/p1/cases/*.json`; `laws/decisions/*.md` |
| Join determinístico (confluência) | **Merge confluente**: footprints disjuntos + leis verdes ⇒ qualquer ordem de merge dá a mesma árvore e o mesmo veredito | teste de confluência no CI: fundir em duas ordens, exigir hash de árvore idêntico + oráculo verde |
| Type checker sub-segundo | **Juiz rápido no join**: se o oráculo de integração custa segundos, integra-se por tarefa e não por onda | orçamento duro: `cargo test` < 10 s; violar é incidente |

E a quinta, a mais importante: **`LAWS` é o único estado compartilhado, e
é imutável durante a rodada.** Agentes paralelos não conversam; cada um
satisfaz as leis. Estado compartilhado *só de leitura* não causa corrida.
Quem escreve leis (intenção) é a fração serial legítima — o 1 %.

## 3. O que fazer em Rust agora (pronto para o Bend, útil sem ele)

1. **Footprint nas specs** (`writes`, `reads`, `oracle`) e um
   `footprint-check`: após o commit da tarefa, o diff só pode tocar
   `writes`; violou = tarefa reprovada, sem olhar conteúdo. É o borrow
   checker de tarefas. Teria impedido a colisão T14/15/16 *antes* de
   spawnar (o orquestrador vê a interseção) e detectado depois.
2. **Refatorar a forma**: `src/lib.rs` monolítico vira `catalog.rs`
   (ordem+dedup, L3/L8), `gates.rs` (L2/L4/L5), `chain.rs` (L1/L6/L7),
   `tiers.rs`, `direct.rs`; `cases.json` vira diretório; Decisions viram
   arquivos. Depois disso, T14/T15/T16 teriam footprints disjuntos.
3. **Teste de confluência** no CI do kernel (T12): dadas as branches
   `p1-*` abertas, `merge A B` e `merge B A` em worktrees temporários;
   exigir mesmo `git rev-parse HEAD^{tree}` e `cargo test` verde. Falha =
   footprint mentiu ou conflito semântico ⇒ vira lei.
4. **Fila de decisões medida**: toda vez que um agente para em "decisão
   do dono", entra no ledger com timestamp; o tempo bloqueado é a fração
   serial. Meta: toda decisão recorrente vira lei ou Decisions row em
   < 1 ciclo. Decisão que se repete é lei que falta.
5. **Juiz < 10 s** como lei operacional do kernel (o bestmodel já tem a
   regra "gate em minutos de um dígito"; aqui o número é menor porque o
   join é por tarefa).
6. **Orquestrador escalona por grafo, não por onda**: conjuntos
   independentes de tarefas (coloração do grafo de conflito) rodam
   juntos; o join de cada uma acontece assim que seu oráculo fecha, não
   quando a onda inteira termina.

Nada disso exige Bend. Tudo isso é o que o Bend vai *comprar mais barato*.

## 4. O que o Bend 2 muda quando provado (E1/E2 verdes)

- **Join por prova**: `bend PROOF.bend` em sub-segundo no ponto de merge
  torna viável integrar centenas de tarefas pequenas por hora — a fração
  serial de verificação tende a zero.
- **Leis formais eliminam a interpretação**: dois agentes não podem
  "entender diferente" um enunciado dependente-tipado como podem com
  prosa ou até com `proptest`. Menos conflito semântico com footprints
  disjuntos.
- **O juiz escala em GPU**: baterias de vetores, harness diferenciais,
  buscas de contraexemplo rodam no runtime paralelo do próprio Bend — o
  verificador cresce com a geração, em vez de ser o gargalo.
- **Especulativo, para o lab**: programas Bend são redes de interação
  confluentes; a *composição* de duas mudanças pode ser analisada como
  redução — "o merge é seguro" como teorema, não como teste de duas
  ordens. Se isso funcionar, o teste de confluência do §3.3 vira prova.

## 5. O que sobra serial de qualquer jeito

Escrever a lei certa. Todo o resto — código, prova, teste, merge — vira
paralelo. A "explosão" não elimina o dono; muda o que ele escreve: de
código para leis, de revisão para decisão registrada. O llms.surf já tem
a forma disso (`tow` escreve intenção, `paddle` executa, ledger assina); o
kernel P1 é a primeira peça construída assim; o Bend é o juiz que torna
o join barato o bastante para a forma valer a pena.

## 6. Riscos

- Footprint declarado errado — o `footprint-check` pega depois, o grafo
  não pega antes. Aceitável: reprovação mecânica.
- Sobre-decomposição: mil arquivos de dez linhas. Regra: divide-se pela
  lei, não pelo tamanho.
- Confluência passa com semântica errada — leis incompletas. É o mesmo
  limite do Bend: lei errada é o novo bug.
- Teatro de prova: "provado" sem lei que importe. O teste de honestidade
  do site continua valendo para o kernel.

## 7. Ordem

§3.1 e §3.2 entram na branch `p1-integrate` logo após D-MERGE (footprint
nas specs T18–T20 já; forma do `lib.rs` antes de P2). §3.3 e §3.5 no T12.
§3.4 e §3.6 no orquestrador (uma spec curta). §4 espera E1/E2.
