# AGENTS.md — prime-agent como substrato de perpetuidade (v4)

Fonte: `core/runner-contract.md`, `adapters/prime-agent/DISCOVERY.md`,
plano v4 (`docs/v4-plan.md`). O prime-agent tem dois papéis distintos:

1. **Runner do contrato** (como opencode): `runner.sh <model_id> <spec_file>`
   para dispatch one-shot. Papel secundário — exige `cli_hints."prime-agent"`
   no registry, que só existe após `/login` (dono) + verificação medida.
2. **Substrato de god mode v4**: daemon + autonomous gate + schedule mantêm a
   cadeia de anéis VIVA fora da sessão do IDE, com `oracfit ring close` como
   gate que segura o término. Este é o papel principal.

## Setup

```
source adapters/prime-agent/env.sh
```

Exporta `DISPATCH_RUNNER` → `adapters/prime-agent/runner.sh`,
`DISPATCH_RUNNER_NAME=prime-agent`, `MODEL_REGISTRY`, `CAPABILITIES_FILE`.

Primeira vez: `prime-agent` interativo + `/login` (ação de DONO — escolhe
provider/assinatura). Sem isso, todo run falha fechado com 401 claro.

## Capacidades (TOOLS)

`TOOLS=1` — laço agêntico com IPython persistente, file ops, shell e
subagentes `rlm(...)`. Ver `capabilities.env`: o que está medido e o que
segue NÃO-MEDIDO (gate segurando término, schedule disparando) está
separado — capacidade não medida não é promessa.

## Forma de execução do god mode v4

```bash
cd ~/worktrees/<projeto>-god          # worktree POR AGENTE (classe 8)
prime-agent --autonomous \
  --autonomous-gate "$ORACFIT_ROOT/bin/oracfit ring close $RING --target . -- <pathspec>" \
  --autonomous-max-turns 40 --autonomous-timeout-ms 14400000 \
  "Esgotar o backlog anel a anel; parar em decisão de dono"
```

- O harness se recusa a terminar enquanto o gate (`ring close`) não passar;
  gate vermelho devolve o output do runner (motivo mecânico) para retry
  DENTRO do teto (`--autonomous-gate-retries`, default 3).
- Wake entre anéis: `prime-agent schedule add <agent> "<cron>" -- "<msg>"` —
  nunca `sleep` em terminal do IDE (matou o despertador do aion aos 102s).
- Critic fresco por anel: subagent `rlm(...)` grava veredito em
  `ring/verdicts/<RING>.json`; quem valida é `bin/check-verdict.py`
  (canal = arquivo, nunca prosa — falhou 2/3 no autarca).

## Ressalvas codificadas (não são opinião, são incidente)

- **`/refine` e memórias são PROTOCOLO.** No Factorio o refine construiu
  skills de trapaça; o autarca provou que cláusula degrada na mesma sessão.
  Proteção de verdade passa no `oracfit mode lint` (claims→mecanismos).
  `/refine` NUNCA edita `ring/oracle.sh` nem critic-profile — a guarda
  monotônica do ring recusa close com trave alterada sem declaração+critic.
- **prime-agent NÃO é sandbox** (aviso do próprio README). Alvo roda em
  worktree por agente; `ring open` recusa árvore suja.
- Budget interno ≤ externo: `--autonomous-max-*` do prime-agent é o teto
  EXTERNO; o teto de anéis do ledger (`ring open`) conta por baixo dele.
