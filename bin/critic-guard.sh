#!/usr/bin/env bash
# critic-guard.sh — write-guard mecânico por PAPEL (v4): critic é read-only
# por código, não por prompt.
#
# Incidente-fonte (falha de CONTRATO): um critic definido como read-only fez
# 3 commits do trabalho do builder e travou 2h04m sem relatório; a separação
# de papéis era 100% prompt e nada falhou fechado — o único ator sem "NÃO
# commite" explícito foi exatamente quem commitou.
# incidents/2026-08-12-godmode-btc-critic-read-only-commitou-o-trabalho-e-travou-2h-sem-relatorio.md
#
# Satélite (falha de PROCESSO): o mesmo dispatch não tinha teto nem vigia e o
# watchdog foi o dono voltando 2h depois. O canal Task do host não passa por
# bin/ — o teto mecânico dos caminhos de dispatch não o alcança.
# incidents/2026-08-12-godmode-btc-dispatch-de-critic-sem-teto-no-host-mode-orquestrador-bloqueado-2h.md
#
# O mecanismo é uma JANELA armada em volta do dispatch de critic:
#   - core.hooksPath do alvo aponta para hooks do guard: pre-commit/pre-push
#     RECUSAM e marcam violação (o hook do ring só age com anel aberto; este
#     age em qualquer alvo, papel critic).
#   - identidade git local vira `oracfit-critic-window(<task>)`: commit que
#     fure o hook (--no-verify) carrega a identidade do papel — atribuição
#     mecânica, não por eliminação.
#   - tripwire: HEAD + `git status --porcelain -uall` antes/depois; drift
#     fora do allowlist (default: só ring/verdicts/, o canal de veredito) =
#     quarentena — commits de autor não-confiável não herdam confiança,
#     gates re-rodam do zero.
#   - canal `run` (dispatch por shell): vigia em voo — 1º write fora do
#     allowlist ou tentativa de commit MATA a árvore do dispatch (exit 5);
#     teto default de ${ORACFIT_CRITIC_BUDGET_S:-900}s via bin/with-timeout.sh
#     (nunca sem teto), estouro = morto + incident automático (exit 124).
#   - canal Task do host (arm/check): `arm --budget` lança vigia em daemon
#     (bin/dispatch-bg.sh, double-fork) que alarma + grava incident na
#     expiração ou no drift, SEM humano. Limite declarado: o vigia não mata
#     uma Task do host (processo do harness) — mata o silêncio, não o processo.
#
# Estado e notas ficam FORA da árvore despachada (~/.oracfit/critic-guard):
# arquivo de controle no workdir do modelo é gravável por acidente
# (incidents/2026-08-10-modelo-despachado-cria-arquivo-de-parada-e-mata-loop.md).
#
# Spec TRANSIENTE de dispatch de critic não nasce em specs/ do oracfit — lá
# ela vira órfã untracked e acumula (noite de 2026-08-13, 5 órfãs). Escreva
# em specs/dispatch-transientes/ (gitignored) ou em $TMPDIR.
#
# Uso:
#   critic-guard.sh arm    --target DIR [--task NOME] [--budget SECS] [--allow PREFIXO]...
#   critic-guard.sh check  --target DIR
#   critic-guard.sh run    --target DIR [--task NOME] [--budget SECS] [--allow PREFIXO]...
#                          [--poll SECS] -- <cmd...>
#   critic-guard.sh watch  --target DIR [--interval SECS]   (uso interno do arm)
#   critic-guard.sh status --target DIR
#
# Exit: 0=ok/limpo · 1=recusado ou dispatch falhou (árvore intacta) ·
#       2=quebrado (janela ausente/estado inválido) · 3=uso ·
#       4=quarentena (drift detectado no check) ·
#       5=violação de escrita (dispatch morto/commit tentado) ·
#       124=teto estourado (morto + incident automático)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORACFIT_ROOT="${ORACFIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GUARD_SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
GUARD_DIR="${ORACFIT_GUARD_DIR:-$HOME/.oracfit/critic-guard}"
CENTRAL_LEDGER="${ORACFIT_CENTRAL_LEDGER:-$ORACFIT_ROOT/ledger/ledger.jsonl}"
DEFAULT_BUDGET="${ORACFIT_CRITIC_BUDGET_S:-900}"

# STATE antes de ENV para o ledger central (2026-08-13, 2ª ocorrência da
# classe no MESMO dia): o daemon do prime-agent é cápsula de env — herdou
# ORACFIT_CENTRAL_LEDGER=/tmp/central-dbg.jsonl do terminal de smoke de
# ontem e desviou guard_armed/guard_clean do teste de campo RING-2 para o
# ledger de debug. Mesma correção do oracfit-ring.sh (satélite do env):
# quando o alvo tem ring/state.json com central_ledger, o STATE vence.
resolve_central_from_state() { # $1=target
  local st="$1/${ORACFIT_RING_DIR:-ring}/state.json" v
  [ -f "$st" ] || return 0
  v=$(python3 -c 'import json,sys;v=json.load(open(sys.argv[1])).get("central_ledger");print(v or "")' "$st" 2>/dev/null) || return 0
  [ -n "$v" ] && CENTRAL_LEDGER="$v"
}

usage() { sed -n '40,53p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 3; }

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift

TARGET=""
TASK="critic"
BUDGET=""
POLL="${ORACFIT_GUARD_POLL_S:-5}"
INTERVAL="${ORACFIT_GUARD_WATCH_INTERVAL:-30}"
ALLOW_LIST="ring/verdicts/"
CMDV=()
seen_dashdash=0
while [ $# -gt 0 ]; do
  if [ "$seen_dashdash" = "1" ]; then CMDV+=("$1"); shift; continue; fi
  case "$1" in
    --target) TARGET="${2:?--target requer dir}"; shift 2 ;;
    --task) TASK="${2:?--task requer nome}"; shift 2 ;;
    --budget) BUDGET="${2:?--budget requer segundos}"; shift 2 ;;
    --allow) ALLOW_LIST="$ALLOW_LIST"$'\n'"${2:?--allow requer prefixo}"; shift 2 ;;
    --poll) POLL="${2:?--poll requer segundos}"; shift 2 ;;
    --interval) INTERVAL="${2:?--interval requer segundos}"; shift 2 ;;
    --) seen_dashdash=1; shift ;;
    *) echo "ERROR: flag desconhecida: $1" >&2; exit 3 ;;
  esac
done

[ -n "$TARGET" ] || { echo "ERROR: --target obrigatório" >&2; exit 3; }
[ -d "$TARGET" ] || { echo "ERROR: target não existe: $TARGET" >&2; exit 3; }
TARGET="$(cd "$TARGET" && pwd)"
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "RECUSADO: $TARGET não é repo git" >&2; exit 1; }
resolve_central_from_state "$TARGET"

WID=$(printf '%s' "$TARGET" | shasum -a 256 | cut -c1-12)
WIN="$GUARD_DIR/$WID"
STATE="$WIN/state.json"

py() { python3 "$@"; }

state_get() { # $1=campo
  py -c 'import json,sys;v=json.load(open(sys.argv[1])).get(sys.argv[2]);print("" if v is None else v)' "$STATE" "$1"
}

# Escopo de config do guard (2026-08-13, débito 6): config --worktree tem
# PRECEDÊNCIA sobre --local, e o ring passou a armar core.hooksPath em escopo
# --worktree em alvo worktree (incidente ring-init-em-worktree-vaza-hook).
# Guard armado em --local nesses alvos ficava MASCARADO: o hook fail-closed
# nunca disparava (só o vigia porcelain/HEAD cobria). O guard arma/lê/restaura
# no MESMO escopo que está ativo no alvo: --worktree quando o alvo é worktree
# COM extensions.worktreeConfig; senão --local (worktree sem worktreeConfig
# não aceita --worktree e o --local funciona, pois nada o mascara).
cfg_scope() {
  local gd cdir
  gd="$(cd "$(git -C "$TARGET" rev-parse --absolute-git-dir)" && pwd -P)"
  cdir="$(git -C "$TARGET" rev-parse --git-common-dir)"
  case "$cdir" in /*) : ;; *) cdir="$TARGET/$cdir" ;; esac
  if [ "$gd" != "$(cd "$cdir" && pwd -P)" ] \
     && [ "$(git -C "$TARGET" config --bool extensions.worktreeConfig 2>/dev/null || true)" = "true" ]; then
    echo "--worktree"
  else
    echo "--local"
  fi
}

cfg_get() { git -C "$TARGET" config "$CFG_SCOPE" --get "$1" 2>/dev/null || echo "<unset>"; }

cfg_restore() { # $1=chave $2=valor gravado no arm
  if [ "$2" = "<unset>" ]; then
    git -C "$TARGET" config "$CFG_SCOPE" --unset "$1" 2>/dev/null || true
  else
    git -C "$TARGET" config "$CFG_SCOPE" "$1" "$2"
  fi
}

# derivação determinística: arm e check recomputam o mesmo escopo do alvo
# (mudar worktreeConfig com janela armada é drift de config, não caso de uso)
CFG_SCOPE="$(cfg_scope)"

head_sha() { git -C "$TARGET" rev-parse HEAD 2>/dev/null || echo "<no-head>"; }

# -uall: untracked arquivo a arquivo — colapsado em `?? dir/`, um write novo
# em ring/verdicts/ inexistente viraria falso positivo no allowlist
porcelain() { git -C "$TARGET" status --porcelain -uall; }

ledger_event() { # $1=event $2=reason
  local line
  line=$(EV="$1" REASON="${2:-}" GTASK="$TASK" GTARGET="$TARGET" GWID="$WID" py -c '
import json, os, datetime
print(json.dumps({
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "schema": "critic-guard-v1", "event": os.environ["EV"],
    "task": os.environ["GTASK"], "target": os.environ["GTARGET"],
    "window": os.environ["GWID"], "reason": os.environ.get("REASON", "")},
    ensure_ascii=False))')
  mkdir -p "$(dirname "$CENTRAL_LEDGER")"
  echo "$line" >> "$CENTRAL_LEDGER"
}

auto_incident() { # $1=motivo curto $2=detalhe multi-linha — alarme que não some
  local title out file
  # task+hora no INÍCIO: o slug do incident.sh corta em 40 chars e motivo
  # igual em tasks diferentes colidiria (new recusa arquivo existente)
  title="critic-guard $TASK $(date +%H%M%S) $1"
  out=$(bash "$SCRIPT_DIR/incident.sh" new "$title" 2>&1) || {
    echo "WARN: incident automático falhou: $out" >&2
    return 0
  }
  file=$(printf '%s\n' "$out" | sed -n 's/^📝 Criado: //p' | head -1)
  if [ -n "$file" ] && [ -f "$file" ]; then
    {
      echo ""
      echo "## Evidência do critic-guard (automática)"
      echo ""
      echo "- alvo: $TARGET"
      echo "- task: $TASK"
      echo "- janela: $WIN"
      echo "- motivo: $1"
      echo "- detalhe:"
      printf '%s\n' "${2:-"(sem detalhe)"}" | sed 's/^/  /'
    } >> "$file"
    echo "incident automático: $file" >&2
  fi
}

# drift fora do allowlist: diferença simétrica de porcelain antes×agora,
# filtrada pelos prefixos permitidos (linha de rename valida os DOIS lados)
drift_lines() {
  porcelain > "$WIN/porcelain.now"
  py -c '
import json, sys
before = set(l.rstrip("\n") for l in open(sys.argv[1]) if l.strip())
after = set(l.rstrip("\n") for l in open(sys.argv[2]) if l.strip())
allow = [a for a in (json.load(open(sys.argv[3])).get("allow") or []) if a]
def allowed(line):
    p = line[3:] if len(line) > 3 else line
    parts = p.split(" -> ") if " -> " in p else [p]
    return all(any(x.strip().strip(chr(34)).startswith(a) for a in allow) for x in parts)
for line in sorted(before ^ after):
    if not allowed(line):
        print(line)
' "$WIN/porcelain.before" "$WIN/porcelain.now" "$STATE"
}

write_hook() { # $1=nome do hook — janela embutida na geração
  cat > "$WIN/hooks/$1" <<EOF
#!/bin/sh
# oracfit-critic-guard — janela de dispatch de critic ATIVA neste repo.
# Critic é READ-ONLY por MECANISMO, não por prompt: commit/push durante a
# janela é violação de contrato de papel; a tentativa fica marcada e o vigia
# do guard mata o dispatch.
# incidents/2026-08-12-godmode-btc-critic-read-only-commitou-o-trabalho-e-travou-2h-sem-relatorio.md
touch "$WIN/violation" 2>/dev/null
echo "BLOQUEADO pelo oracfit-critic-guard ($1): janela de critic ativa (task $TASK)." >&2
echo "Nenhum commit/push em $TARGET até a janela fechar:" >&2
echo "  bin/critic-guard.sh check --target $TARGET" >&2
exit 1
EOF
  chmod +x "$WIN/hooks/$1"
}

do_arm() { # \$SPAWN_WATCH=1 lança vigia em daemon quando há budget
  if [ -f "$STATE" ]; then
    echo "RECUSADO: janela já armada para $TARGET (task $(state_get task), desde $(state_get armed_ts))." >&2
    echo "Feche com: critic-guard.sh check --target $TARGET" >&2
    exit 1
  fi
  mkdir -p "$WIN/hooks" "$WIN/notes"
  rm -f "$WIN/violation"
  porcelain > "$WIN/porcelain.before"

  local head_before orig_hooks orig_name orig_email
  head_before=$(head_sha)
  orig_hooks=$(cfg_get core.hooksPath)
  orig_name=$(cfg_get user.name)
  orig_email=$(cfg_get user.email)

  write_hook pre-commit
  write_hook pre-push
  git -C "$TARGET" config "$CFG_SCOPE" core.hooksPath "$WIN/hooks"
  # identidade de janela: commit que furar o hook carrega o papel no autor
  git -C "$TARGET" config "$CFG_SCOPE" user.name "oracfit-critic-window($TASK)"
  git -C "$TARGET" config "$CFG_SCOPE" user.email "critic-window@oracfit.invalid"

  GTARGET="$TARGET" GTASK="$TASK" GHEAD="$head_before" GBUDGET="${BUDGET:-0}" \
  GALLOW="$ALLOW_LIST" GOHOOKS="$orig_hooks" GONAME="$orig_name" GOEMAIL="$orig_email" \
  py -c '
import json, os, sys, datetime
state = {
    "schema": "critic-guard-v1",
    "target": os.environ["GTARGET"],
    "task": os.environ["GTASK"],
    "head": os.environ["GHEAD"],
    "budget_s": int(os.environ["GBUDGET"] or 0),
    "armed_epoch": int(datetime.datetime.now().timestamp()),
    "armed_ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "allow": [a for a in os.environ["GALLOW"].split("\n") if a],
    "orig_hookspath": os.environ["GOHOOKS"],
    "orig_username": os.environ["GONAME"],
    "orig_useremail": os.environ["GOEMAIL"],
}
json.dump(state, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
' "$STATE"

  ledger_event guard_armed "budget_s=${BUDGET:-0}"
  echo "ARMADO: janela de critic em $TARGET (task $TASK, allow: $(printf '%s' "$ALLOW_LIST" | tr '\n' ' '))"

  if [ "${SPAWN_WATCH:-1}" = "1" ] && [ -n "${BUDGET:-}" ] && [ "${BUDGET:-0}" -gt 0 ]; then
    bash "$SCRIPT_DIR/dispatch-bg.sh" "$WIN/watch.log" \
      bash "$GUARD_SELF" watch --target "$TARGET" --interval "$INTERVAL" >/dev/null
    echo "vigia lançado em daemon (teto ${BUDGET}s): $WIN/watch.log"
  fi
}

restore_window() {
  cfg_restore core.hooksPath "$(state_get orig_hookspath)"
  cfg_restore user.name "$(state_get orig_username)"
  cfg_restore user.email "$(state_get orig_useremail)"
  if [ -f "$WIN/watch.log.pid" ]; then
    local wpid
    wpid=$(head -1 "$WIN/watch.log.pid" | tr -d '[:space:]')
    [ -n "$wpid" ] && kill -TERM "$wpid" 2>/dev/null || true
  fi
}

quarantine() { # $1=motivo $2=drift — fecha a janela E grita
  echo "QUARENTENA ($1): a árvore de $TARGET mudou durante a janela de critic." >&2
  [ -n "${2:-}" ] && printf '%s\n' "$2" | head -20 | sed 's/^/  drift: /' >&2
  echo "Commits/writes de autor não-confiável NÃO herdam confiança: re-rode os gates do zero antes de aproveitar qualquer coisa." >&2
  ledger_event guard_quarantine "$1"
  auto_incident "quarentena ($1)" "${2:-"(HEAD mudou; ver git log do alvo)"}"
  mv "$STATE" "$WIN/state.quarantined.$(date +%s).json" 2>/dev/null || true
  exit 4
}

do_check() {
  [ -f "$STATE" ] || { echo "QUEBRADO: nenhuma janela armada para $TARGET ($STATE ausente)" >&2; exit 2; }
  local head_before head_now drift
  head_before=$(state_get head)
  drift=$(drift_lines)
  head_now=$(head_sha)
  restore_window

  if [ -e "$WIN/violation" ]; then
    echo "VIOLAÇÃO DE ESCRITA: houve tentativa de commit/push durante a janela (hook marcou)." >&2
    ledger_event guard_write_violation "commit_ou_push_tentado"
    auto_incident "violacao de escrita (hook)" "${drift:-"(tentativa bloqueada; árvore sem drift)"}"
    mv "$STATE" "$WIN/state.quarantined.$(date +%s).json" 2>/dev/null || true
    exit 5
  fi
  if [ "$head_now" != "$head_before" ]; then
    quarantine "head_drift ($head_before -> $head_now)" "$drift"
  fi
  if [ -n "$drift" ]; then
    quarantine "tree_drift" "$drift"
  fi

  ledger_event guard_clean ""
  rm -rf "$WIN"
  echo "LIMPO: janela fechada, árvore de $TARGET intacta (HEAD e status idênticos ao arm)."
}

kill_tree() { # mata descendentes primeiro (mesma lição do bin/with-timeout.sh)
  local pid="$1" c
  for c in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$c"; done
  kill -KILL -- -"$pid" 2>/dev/null || true
  kill -KILL "$pid" 2>/dev/null || true
}

do_run() {
  [ "$seen_dashdash" = "1" ] && [ ${#CMDV[@]} -gt 0 ] \
    || { echo "uso: critic-guard.sh run --target DIR [--budget S] -- <cmd...>" >&2; exit 3; }
  # nunca sem teto — o dispatch do incidente ficou 2h04m porque o teto era o dono
  BUDGET="${BUDGET:-$DEFAULT_BUDGET}"
  SPAWN_WATCH=0 do_arm

  (
    export ORACFIT_CRITIC_NOTES_DIR="$WIN/notes"
    export GIT_AUTHOR_NAME="oracfit-critic($TASK)"
    export GIT_AUTHOR_EMAIL="critic@oracfit.invalid"
    export GIT_COMMITTER_NAME="oracfit-critic($TASK)"
    export GIT_COMMITTER_EMAIL="critic@oracfit.invalid"
    exec bash "$SCRIPT_DIR/with-timeout.sh" "$BUDGET" "${CMDV[@]}"
  ) &
  local child=$! violated=0 rc=0 drift=""
  while kill -0 "$child" 2>/dev/null; do
    sleep "$POLL"
    kill -0 "$child" 2>/dev/null || break
    drift=$(drift_lines)
    if [ -e "$WIN/violation" ] || [ -n "$drift" ] || [ "$(head_sha)" != "$(state_get head)" ]; then
      violated=1
      kill_tree "$child"
      break
    fi
  done
  wait "$child" 2>/dev/null; rc=$?

  local final_drift head_before head_now
  final_drift=$(drift_lines)
  head_before=$(state_get head)
  head_now=$(head_sha)
  restore_window

  if [ "$violated" = "1" ]; then
    echo "DISPATCH MORTO (violação de escrita): critic tentou escrever/commitar na árvore de $TARGET." >&2
    [ -n "$final_drift" ] && printf '%s\n' "$final_drift" | head -10 | sed 's/^/  drift: /' >&2
    echo "Re-rode os gates do zero antes de aproveitar qualquer coisa desta janela." >&2
    ledger_event guard_write_violation "morto_em_voo"
    auto_incident "violacao de escrita (morto em voo)" "${final_drift:-"(tentativa de commit marcada pelo hook)"}"
    mv "$STATE" "$WIN/state.quarantined.$(date +%s).json" 2>/dev/null || true
    exit 5
  fi
  if [ "$rc" -eq 124 ]; then
    echo "DISPATCH MORTO (teto ${BUDGET}s estourado): critic sem relatório dentro do orçamento." >&2
    ledger_event guard_timeout "budget_s=$BUDGET"
    auto_incident "teto de ${BUDGET}s estourado" "dispatch morto por bin/with-timeout.sh sem intervenção humana"
    mv "$STATE" "$WIN/state.quarantined.$(date +%s).json" 2>/dev/null || true
    exit 124
  fi
  if [ -e "$WIN/violation" ]; then
    echo "VIOLAÇÃO DE ESCRITA: critic tentou commit/push (bloqueado pelo hook) e terminou sozinho." >&2
    ledger_event guard_write_violation "commit_ou_push_tentado"
    auto_incident "violacao de escrita (hook)" "${final_drift:-"(tentativa bloqueada)"}"
    mv "$STATE" "$WIN/state.quarantined.$(date +%s).json" 2>/dev/null || true
    exit 5
  fi
  if [ "$head_now" != "$head_before" ] || [ -n "$final_drift" ]; then
    quarantine "drift_pos_dispatch" "$final_drift"
  fi
  if [ "$rc" -ne 0 ]; then
    echo "dispatch do critic falhou (rc=$rc) — árvore intacta." >&2
    ledger_event guard_dispatch_failed "rc=$rc"
    rm -rf "$WIN"
    exit 1
  fi
  ledger_event guard_clean "run"
  rm -rf "$WIN"
  echo "LIMPO: dispatch terminou (rc=0), árvore de $TARGET intacta."
}

do_watch() {
  # vigia do canal Task do host: roda em daemon (dispatch-bg). Não consegue
  # matar a Task (processo do harness) — o que ele mata é o SILÊNCIO: drift
  # ou teto viram alarme + incident automático sem humano no loop.
  while true; do
    [ -f "$STATE" ] || exit 0  # janela fechada pelo check — trabalho feito
    local drift budget armed now
    drift=$(drift_lines)
    if [ -e "$WIN/violation" ] || [ -n "$drift" ] || [ "$(head_sha)" != "$(state_get head)" ]; then
      echo "VIGIA: violação/drift na janela de critic de $TARGET" >&2
      ledger_event guard_write_violation "detectado_pelo_vigia"
      auto_incident "violacao detectada pelo vigia (canal Task)" "${drift:-"(HEAD mudou ou hook marcou tentativa)"}"
      exit 5
    fi
    budget=$(state_get budget_s)
    armed=$(state_get armed_epoch)
    now=$(date +%s)
    if [ "${budget:-0}" -gt 0 ] && [ $((now - armed)) -ge "$budget" ]; then
      echo "VIGIA: teto de ${budget}s estourado sem check — dispatch host-mode sem relatório" >&2
      ledger_event guard_timeout "budget_s=$budget canal=task"
      auto_incident "teto de ${budget}s estourado (canal Task)" \
        "janela armada em $(state_get armed_ts) segue aberta; a Task do host não pode ser morta daqui — interrompa-a e rode critic-guard.sh check --target $TARGET"
      exit 124
    fi
    sleep "$INTERVAL"
  done
}

do_status() {
  if [ -f "$STATE" ]; then
    echo "ARMADA: task=$(state_get task) desde $(state_get armed_ts) budget=$(state_get budget_s)s head=$(state_get head | cut -c1-12)"
    [ -e "$WIN/violation" ] && echo "VIOLAÇÃO MARCADA: houve tentativa de commit/push nesta janela" >&2
    exit 0
  fi
  echo "sem janela armada para $TARGET"
  exit 1
}

case "$cmd" in
  arm)    do_arm ;;
  check)  do_check ;;
  run)    do_run ;;
  watch)  do_watch ;;
  status) do_status ;;
  *)      usage ;;
esac
