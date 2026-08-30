# ESCALADA-5 v2 — decisões validadas e CONGELADAS (free path)

> Resposta do Fable (2026-08-31). Regra da escalada respeitada: nada
> explorado além do texto; a única conferência permitida
> (`bin/audit-registry-ids.sh | tail -4`) foi tentada e não roda neste
> ambiente (`opencode models` exit 1 no sandbox) — valem os números
> carimbados na escalada, verificados pelo dono na árvore do main.
> Implementação é do dono (M1–M6); aqui só veredito e risco.

## As 5 decisões — veredito em uma linha

- **D1 retire: A.** Registry = só verdade; o git history JÁ é a lista
  retired (remoção em 1 commit citando a saída do audit) — `status:
  retired` é segunda cópia da mesma informação, apodrecendo.
- **D2 feed: A.** JSON estruturado com schema validado no sync; parse de
  README markdown é scraping — quebra silenciosa a cada reformatação.
- **D3 quota: A**, com "runtime" = ler o `data/free-catalog.json` LOCAL
  carimbado pelo M1, nunca HTTP no caminho do dispatch; B (cópia no
  registry) recria a doença que gerou os 46 mortos — duas verdades.
- **D4 credencial: A.** Env herdada é exatamente como o default virou
  pago (118 Bedrock + 36 Copilot sem ninguém pedir); fecha a classe SÓ
  se a lib do M5 for o ÚNICO leitor de credencial do código — grep no
  gate: nenhum outro arquivo lê `*_API_KEY`/`AWS_*` direto.
- **D5 fechado: concordo e APERTO** (dois apertos abaixo).

## D5 apertado — o gate que prova o fim

`test-free-path.sh` como proposto (preflight lint + `resolve-tier
tier:cheap` ≥3 ids vivos + dispatch stub com `provider_efetivo`
registrado), MAIS:

1. **Rodar COM as envs pagas presentes e envenenadas** (`AWS_*`,
   Copilot etc. setadas com valores-isca) e assertar que o caminho free
   fecha com `provider_efetivo` ∈ allowlist free e NENHUMA isca foi
   lida. Ambiente limpo prova ausência; ambiente envenenado prova
   imunidade — a classe do incidente só morre com a segunda.
2. **Assertar `provider_efetivo` ∈ allowlist do run**, não só presente
   na linha — registrado mas fora da lista é o gate mentindo verde.

## Riscos que a escalada não cobre (em ordem de mordida)

- **R1 — "no API key" ≠ "sem credencial paga".** A maioria dos 30
  providers free do feed exige chave (NVIDIA, Groq, Gemini, SiliconFlow
  — cadastro + key free). A promessa do README ("no API key, 2
  minutos") só fecha se o topo do fallback do tier:cheap tiver provider
  genuinamente keyless; senão o cronômetro da definição de pronto
  reprova. D5 precisa de DUAS pernas: perna zero-key (a promessa do
  README) e perna free-key (auth.json com chaves de tier free). Se hoje
  só 2/22 free são alcançáveis, conferir quantos dos 2 são keyless
  ANTES de re-anunciar.
- **R2 — sync nunca sobrescreve bom com ruim.** freellm.net é terceiro
  e ponto único: domínio morre, schema muda, dataset vem truncado. M1
  deve escrever em temp → validar (schema + contagem mínima + amostra
  de ids auditados vivos) → mover; falha = mantém último snapshot bom e
  grita. Senão um feed quebrado mata o caminho default inteiro de uma
  vez — pior que os fantasmas.
- **R3 — "quota-aware" é na verdade limit-aware.** RPM/RPD do feed são
  limites PUBLICADOS do provider, não saldo consumido; M4 não contabiliza
  o que já gastamos. Dois loops concorrentes estouram RPD e o fallback
  thrasha na lista inteira. Ou entra contador local de consumo (ledger
  já existe), ou aceita fallback dirigido por 429 — e a copy pública
  NUNCA diz "quota-aware" sem o mecanismo existir (régua da casa:
  claim depois do mecanismo).
- **R4 — para onde vai o código do dono.** O caminho default passa a
  mandar prompt/código para o primeiro provider free da lista, e termos
  de tier free frequentemente permitem treino sobre o tráfego. M6
  (allowlist por run) é o mecanismo certo — mas a allowlist DEFAULT é
  decisão de política do dono, explícita, não consequência silenciosa
  da ordem do feed.
- **R5 — D1 vs histórico do ledger.** Removido o id do registry, linhas
  antigas de run que o citam precisam continuar consultáveis sem
  re-resolver via registry. M6 torna a linha autossuficiente
  (`provider_efetivo` gravado); confirmar que nenhum consumidor do
  ledger faz lookup de id morto no registry — senão a remoção quebra
  replay/consulta.

## Definição de pronto — validada

6 mecanismos em gates verdes + D5 (apertado: perna envenenada + perna
zero-key) exit 0 + cronômetro de novo na promessa do README. Acrescento
um item barato: o re-anúncio cita o número do audit ANTES e DEPOIS
(46/69 mortos → 0/N) — a mesma régua que abriu o incidente o fecha.

## Congelado

D1=A · D2=A · D3=A (runtime = arquivo local do M1) · D4=A (lib única
leitora, grep no gate) · D5=sim com os 2 apertos. Riscos R1–R5
registrados; R1 e R2 entram no escopo de M1/D5, R3 vira restrição de
copy até existir contador, R4 é dial explícito do dono, R5 é assert do
M6. Não reaberto: S28, S13, S27, ESCALADA-4.
