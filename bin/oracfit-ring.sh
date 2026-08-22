#!/usr/bin/env bash
# oracfit-ring.sh — runner de anel de god mode (v4): mecanismo, não protocolo.
#
# Promoção do piloto aion/ring.sh (primeiro ledger não-vazio de god mode) para
# o core, com as correções dos incidentes de 2026-08-12:
#   - close TRANSACIONAL: ledger gravado ANTES do commit de checkpoint e
#     INCLUÍDO nele; pós-condição de árvore limpa (satélite aion: linha órfã)
#   - estado em ARQUIVO relido a cada open (ring/state.json) — imune à
#     sumarização de contexto (satélite autarca: schema drift + paráfrase)
#   - preflight mecânico no open (bin/ring-preflight.sh) — pulado 2x no autarca
#   - veredito de ARQUIVO validado fail-closed (bin/check-verdict.py) — canal
#     de prosa falhou 2/3 no autarca; T3/T4 loops de gap vazio
#   - oráculo MONOTÔNICO por sha256: mudar a trave com anel aberto exige
#     DECLARACAO nas notas + oracle_change_approved:true no veredito
#   - retest descorrelacionado de testes novos (flaky verde-2x do autarca)
#   - gate visual por gatilho de diff (3 telas shipped sem nenhum render)
#   - staging guard: pré-staged alheio recusa o close (commit de nascimento
#     do autarca varreu incident de outro agente)
#   - hook pre-commit: com anel aberto, commit só via runner (aion sintoma 4)
#
# Uso:
#   oracfit ring init  --mode <id> [--target DIR] [--oracle-cmd "<cmd>"] [opções]
#   oracfit ring open  RING-N "hipótese" [--target DIR]
#   oracfit ring close RING-N [--target DIR] -- <pathspec...>
#   oracfit ring abort RING-N "motivo" [--target DIR]
#   oracfit ring score RING-N --real N [--target DIR]
#   oracfit ring status [--target DIR]
#   oracfit ring hook-install [--target DIR]
#
# Exit: 0=ok · 1=recusado (motivo no stderr, falha contável) · 2=quebrado · 3=uso
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORACFIT_ROOT="${ORACFIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# predicado visual compartilhado (oracfit_visual_hits) — ring e gauntlet
# decidem "tocou tela?" pelo MESMO código (fase 5 do v4)
# shellcheck source=lib-oracfit-preflight.sh
source "$SCRIPT_DIR/lib-oracfit-preflight.sh"
# testes apontam ORACFIT_CENTRAL_LEDGER para tmpfile — nunca sujar o real
CENTRAL_LEDGER="${ORACFIT_CENTRAL_LEDGER:-$ORACFIT_ROOT/ledger/ledger.jsonl}"

RING_DIR_NAME="${ORACFIT_RING_DIR:-ring}"

py() { python3 "$@"; }

# ms de verdade: date +%s tem granularidade de segundo e gravou duration_s:0
# a noite inteira de 2026-08-13 (débito 12) — suíte sub-segundo é invisível
now_ms() { py -c 'import time;print(int(time.time()*1000))'; }

usage() { sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 3; }

# ── argumentos ────────────────────────────────────────────────────────────────
cmd="${1:-}"
[ -n "$cmd" ] || usage
shift

TARGET="$PWD"
POSITIONAL=()
PATHSPEC=()
MODE_ID=""
ORACLE_CMD=""
CEILING=""
MIN_SCORE=""
REAL_SCORE=""
seen_dashdash=0
while [ $# -gt 0 ]; do
  if [ "$seen_dashdash" = "1" ]; then PATHSPEC+=("$1"); shift; continue; fi
  case "$1" in
    --target) TARGET="${2:?--target requer dir}"; shift 2 ;;
    --mode) MODE_ID="${2:?--mode requer id}"; shift 2 ;;
    --oracle-cmd) ORACLE_CMD="${2:?--oracle-cmd requer comando}"; shift 2 ;;
    --ceiling) CEILING="${2:?--ceiling requer N}"; shift 2 ;;
    --min-score) MIN_SCORE="${2:?--min-score requer N}"; shift 2 ;;
    --real) REAL_SCORE="${2:?--real requer N}"; shift 2 ;;
    --) seen_dashdash=1; shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
TARGET="$(cd "$TARGET" && pwd)"
RING_DIR="$TARGET/$RING_DIR_NAME"
STATE="$RING_DIR/state.json"
LEDGER="$RING_DIR/ledger.jsonl"
OWNER_LOCK="$RING_DIR/owner.lock"
CHECKPOINTS="$TARGET/CHECKPOINTS.md"

state_get() { # $1=campo -> valor (vazio se ausente/null)
  py - "$STATE" "$1" <<'EOF'
import json, sys
v = json.load(open(sys.argv[1])).get(sys.argv[2])
print("" if v is None else v)
EOF
}

state_set() { # $1=campo $2=valor $3=tipo(str|num|null)
  py - "$STATE" "$1" "$2" "${3:-str}" <<'EOF'
import json, sys
path, field, val, typ = sys.argv[1:5]
d = json.load(open(path))
if typ == "null": d[field] = None
elif typ == "num": d[field] = float(val) if "." in val else int(val)
else: d[field] = val
tmp = path + ".tmp"
json.dump(d, open(tmp, "w"), ensure_ascii=False, indent=2)
import os; os.replace(tmp, path)
EOF
}

require_state() {
  [ -f "$STATE" ] || { echo "RECUSADO: $STATE não existe — rode 'oracfit ring init --mode <id> --target $TARGET'" >&2; exit 1; }
  schema=$(state_get schema)
  [ "$schema" = "ring-state-v1" ] || { echo "QUEBRADO: schema de estado desconhecido: '$schema' (fail-closed)" >&2; exit 2; }
  # central resolvido do STATE, não do ambiente: env herdado de shell sujo
  # dividiu o ledger central no teste de campo A-1 (open foi parar no
  # central de uma smoke antiga). Env só vale no init.
  # state SEM a chave (init anterior à feature) mantém o default — e o
  # teste precisa ser if/then: `[ -n ] && ...` como última linha da função
  # devolve rc=1 sob set -e e matava QUALQUER subcomando em silêncio
  # (exit 1 sem stderr no score do HITL, 2026-08-13).
  state_central=$(state_get central_ledger)
  if [ -n "$state_central" ]; then
    CENTRAL_LEDGER="$state_central"
  fi
}

oracle_sha() { shasum -a 256 "$RING_DIR/oracle.sh" | awk '{print $1}'; }

count_events() { # $1=event [$2=ring]
  py - "$LEDGER" "$(state_get run)" "$1" "${2:-}" <<'EOF'
import json, sys, os
path, run, ev, ring = sys.argv[1:5]
n = 0
if os.path.exists(path):
    for line in open(path):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except json.JSONDecodeError: continue
        if e.get("run") == run and e.get("event") == ev and (not ring or e.get("ring") == ring):
            n += 1
print(n)
EOF
}

ring_event() { # $1=ring $2=event -> linha json ou vazio
  py - "$LEDGER" "$(state_get run)" "$1" "$2" <<'EOF'
import json, sys, os
path, run, ring, ev = sys.argv[1:5]
if os.path.exists(path):
    for line in open(path):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except json.JSONDecodeError: continue
        if e.get("run") == run and e.get("ring") == ring and e.get("event") == ev:
            print(line)
EOF
}

append_ledger() { # $1=linha json — workdir E central (schema idêntico)
  echo "$1" >> "$LEDGER"
  mkdir -p "$(dirname "$CENTRAL_LEDGER")"
  echo "$1" >> "$CENTRAL_LEDGER"
}

append_central_only() { echo "$1" >> "$CENTRAL_LEDGER"; }

make_event() { # $1=ring $2=event $3=json extra (objeto) -> linha
  # "target" em TODO evento ring-v1: a colisão de run id de 2026-08-13
  # (ananke-20260813-0347, CanIRunIt × ai-usage-hub) ficou INDESAMBIGUÁVEL no
  # central porque ring-v1 perdeu o workdir que os modos antigos tinham.
  py - "$(state_get mode)" "$(state_get run)" "$TARGET" "$1" "$2" "$3" <<'EOF'
import json, sys, datetime
mode, run, target, ring, ev, extra = sys.argv[1:7]
e = {"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
     "schema": "ring-v1", "mode": mode, "run": run, "target": target,
     "ring": ring, "event": ev}
e.update(json.loads(extra))
print(json.dumps(e, ensure_ascii=False))
EOF
}

git_t() { git -C "$TARGET" "$@"; }

is_worktree() { # git-dir ≠ common-dir → alvo é worktree ligado a um repo principal
  local wt_git_dir wt_common_dir
  wt_git_dir="$(cd "$(git_t rev-parse --absolute-git-dir)" && pwd -P)"
  wt_common_dir="$(git_t rev-parse --git-common-dir)"
  case "$wt_common_dir" in /*) : ;; *) wt_common_dir="$TARGET/$wt_common_dir" ;; esac
  [ "$wt_git_dir" != "$(cd "$wt_common_dir" && pwd -P)" ]
}

# ── lock de dono (incidents/2026-08-13-executor-duplicado-no-mesmo-worktree-ove.md)
# Dois executores no mesmo alvo é falha SILENCIOSA: verdicts sobrescritos,
# close com pathspec misto. Toda transição de posse (claim no init, adoção
# de lock de pid morto) acontece num critical section ÚNICO sob flock de um
# sidecar que nunca é substituído — check-then-write em dois passos deixava
# dois executores adotarem juntos (round 2 do critic do RING-2). Provas de
# posse, na ordem: token de sessão (ORACFIT_RING_OWNER, sobrevive a shell
# efêmero) → ancestralidade de pid VIVO com mesmo start (pid reciclado não
# engana). Dono vivo estrangeiro recusa; pid morto = adoção serializada e
# AUDITADA (evento owner_adopt no ledger); lock ilegível = QUEBRADO (exit 2).

OWNER_FLOCK="$OWNER_LOCK.flock"
OWNER_ADOPT_INFO=""

ensure_owner_exclude() { # owner.lock* é estado de sessão: nunca no porcelain
  local ex
  ex="$(git_t rev-parse --git-path info/exclude)"
  case "$ex" in /*) : ;; *) ex="$TARGET/$ex" ;; esac
  mkdir -p "$(dirname "$ex")"
  grep -qxF "$RING_DIR_NAME/owner.lock*" "$ex" 2>/dev/null \
    || echo "$RING_DIR_NAME/owner.lock*" >> "$ex"
}

owner_guard() { # $1=modo(init|mutate) $2=run_id — decide E transiciona, atômico
  ensure_owner_exclude
  local out rc=0 word rest
  out=$(LOCK="$OWNER_LOCK" FLK="$OWNER_FLOCK" GMODE="$1" RUN="$2" OPID="$PPID" \
        OHOST="$(hostname)" TOKEN="${ORACFIT_RING_OWNER:-}" py - <<'EOF'
import datetime, fcntl, json, os, secrets, subprocess, sys

lock_path = os.environ["LOCK"]
mode = os.environ["GMODE"]
run = os.environ["RUN"]
my_pid = int(os.environ["OPID"])
host = os.environ["OHOST"]
env_token = os.environ.get("TOKEN", "")

def ps_field(field, pid):
    try:
        return subprocess.run(["ps", "-o", field + "=", "-p", str(pid)],
                              capture_output=True, text=True).stdout.strip()
    except Exception:
        return ""

def is_ancestor(target):
    p, hops = os.getpid(), 0
    while p > 1 and hops < 128:
        if p == target:
            return True
        nxt = ps_field("ppid", p)
        if not nxt.isdigit():
            return False
        p, hops = int(nxt), hops + 1
    return False

os.makedirs(os.path.dirname(lock_path), exist_ok=True)
# flock no SIDECAR (nunca substituído): flock no próprio lock seria segurado
# no inode antigo depois do os.replace, e dois critical sections coexistiriam
fl = open(os.environ["FLK"], "a+")
fcntl.flock(fl, fcntl.LOCK_EX)

def write_lock(token):
    data = {"schema": "ring-owner-v1", "host": host, "pid": my_pid,
            "pid_start": ps_field("lstart", my_pid), "token": token,
            "run": run,
            "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
    tmp = lock_path + ".tmp"
    json.dump(data, open(tmp, "w"), ensure_ascii=False, indent=2)
    os.replace(tmp, lock_path)

if not os.path.exists(lock_path):
    tok = env_token or secrets.token_hex(8)
    write_lock(tok)
    print("CLAIMED %s" % tok)
    sys.exit(0)

try:
    cur = json.load(open(lock_path))
    if not isinstance(cur, dict):
        raise ValueError("raiz não é objeto")
except Exception:
    print("BROKEN")
    sys.exit(2)

lpid = cur.get("pid")
lstart = cur.get("pid_start") or ""
ltok = cur.get("token") or ""
desc = "pid %s desde %r, run %s, host %s" % (
    lpid, lstart, cur.get("run") or "?", cur.get("host") or "?")

if env_token and ltok and env_token == ltok:
    print("OWN")                       # posse por token: shell efêmero não perde o ring
    sys.exit(0)
if (cur.get("host") or "") != host:
    print("OTHER-HOST %s" % desc)
    sys.exit(1)
if not isinstance(lpid, int):
    print("BROKEN")
    sys.exit(2)
now_start = ps_field("lstart", lpid)
if now_start and now_start == lstart:
    if is_ancestor(lpid):
        print("OWN")                   # posse por ancestralidade de pid vivo
        sys.exit(0)
    print("LIVE-FOREIGN %s" % desc)
    sys.exit(1)
# dono morto ou pid reciclado (start diverge): adoção DENTRO do flock —
# exatamente um adotante vence uma transição
tok = env_token or secrets.token_hex(8)
write_lock(tok)
print("ADOPTED %s %s" % (lpid, tok))
sys.exit(0)
EOF
) || rc=$?
  word="${out%% *}"; rest="${out#* }"
  case "$rc:$word" in
    0:CLAIMED)
      echo "owner-lock: posse registrada. Para mantê-la entre shells: export ORACFIT_RING_OWNER=$rest" >&2 ;;
    0:ADOPTED)
      OWNER_ADOPT_INFO="$rest"   # "<pid_antigo> <token>" — mutadores auditam no ledger
      echo "owner-lock: dono anterior morto (pid ${rest%% *}) — posse assumida. export ORACFIT_RING_OWNER=${rest#* }" >&2 ;;
    0:OWN) : ;;
    1:LIVE-FOREIGN)
      echo "RECUSADO: ring de $TARGET pertence a OUTRO processo VIVO ($rest)." >&2
      echo "Dois executores no mesmo alvo é o incidente 2026-08-13-executor-duplicado-no-mesmo-worktree-ove: PARE e verifique a sessão dona antes de qualquer escrita. Se o dono está realmente morto, remova $OWNER_LOCK." >&2
      exit 1 ;;
    1:OTHER-HOST)
      echo "RECUSADO: ring de $TARGET tem owner.lock de OUTRO host ($rest) — vida não-verificável daqui (fail-closed). Remova $OWNER_LOCK só se tiver certeza." >&2
      exit 1 ;;
    2:*)
      echo "QUEBRADO: $OWNER_LOCK ilegível (fail-closed) — remova-o à mão se tiver certeza de que não há outra sessão viva." >&2
      exit 2 ;;
    *)
      echo "QUEBRADO: owner_guard devolveu '$out' (rc=$rc)" >&2
      exit 2 ;;
  esac
}

require_owner() { # chamar após require_state, só em comando mutador
  owner_guard mutate "$(state_get run)"
  if [ -n "$OWNER_ADOPT_INFO" ]; then
    # adoção nunca é silenciosa: ping-pong de posse entre sessões de shell
    # efêmero fica VISÍVEL no ledger (workdir + central)
    adopt_extra=$(INFO="$OWNER_ADOPT_INFO" NEWPID="$PPID" py - <<'EOF'
import json, os
old_pid = os.environ["INFO"].split()[0]
print(json.dumps({"old_pid": old_pid, "new_pid": int(os.environ["NEWPID"])}))
EOF
)
    append_ledger "$(make_event "" owner_adopt "$adopt_extra")"
  fi
}

install_hook() {
  local hooks_dir hook chain
  chain=""
  if is_worktree; then
    # worktree: `--git-path hooks` resolve para o hooks COMPARTILHADO do repo
    # principal (common dir) — o guard vazava para todos os checkouts daquele
    # repo e nenhum teardown o removia (run ananke-20260813-0347: hook foi
    # parar em CanIRunIt/.git/hooks/pre-commit). Escopo por-worktree:
    # core.hooksPath --worktree aponta para ring/hooks DENTRO do próprio
    # worktree; `git worktree remove` descarta a config junto.
    hooks_dir="$RING_DIR/hooks"
    mkdir -p "$hooks_dir"
    git_t config extensions.worktreeConfig true
    git_t config --worktree core.hooksPath "$hooks_dir"
    # coexistência com o gate do DONO (débito 13, run ananke-20260813-0412):
    # o hooksPath por-worktree ESCONDE o pre-commit do repo (lefthook etc.)
    # neste worktree. O hook do ring encadeia o original do common dir depois
    # do próprio check, propagando o exit code. Hook vazado NOSSO (noite de
    # 2026-08-13, 16 repos) não é re-executado — grep pela assinatura.
    chain='
# gate do DONO: encadeia o pre-commit original do repo (common dir), que o
# hooksPath por-worktree esconderia. Exit code dele é respeitado.
orig="$(git rev-parse --git-common-dir)/hooks/pre-commit"
case "$orig" in /*) : ;; *) orig="$PWD/$orig" ;; esac
if [ -x "$orig" ] && ! grep -q oracfit-ring-guard "$orig" 2>/dev/null; then
  exec "$orig" "$@"
fi'
  else
    hooks_dir="$(git_t rev-parse --git-path hooks)"
    case "$hooks_dir" in /*) : ;; *) hooks_dir="$TARGET/$hooks_dir" ;; esac
    mkdir -p "$hooks_dir"
  fi
  hook="$hooks_dir/pre-commit"
  if [ -e "$hook" ] && ! grep -q "oracfit-ring-guard" "$hook" 2>/dev/null; then
    echo "RECUSADO: $hook já existe e não é nosso — integre à mão." >&2
    echo "MECANISMO AUSENTE: commit-só-via-runner sem hook — pre-commit alheio presente ($hook)." >&2
    return 1
  fi
  cat > "$hook" <<EOF
#!/bin/sh
# oracfit-ring-guard — com anel aberto, commit só via runner (aion sintoma 4:
# nada impedia commitar por fora do ring.sh). Bypass do bloqueio do RING:
# ORACFIT_RING_COMMIT=1 (setado pelo próprio runner) — o hook do DONO
# encadeado abaixo (se houver) roda mesmo assim. Sem anel aberto, commit livre.
state="\$(git rev-parse --show-toplevel)/$RING_DIR_NAME/state.json"
if [ -f "\$state" ] && [ "\${ORACFIT_RING_COMMIT:-0}" != "1" ]; then
  current=\$(python3 -c "import json;print(json.load(open('\$state')).get('current_ring') or '')" 2>/dev/null)
  if [ -n "\$current" ]; then
    echo "BLOQUEADO pelo oracfit-ring-guard: anel \$current aberto —" >&2
    echo "commit só via 'oracfit ring close \$current -- <pathspec...>'." >&2
    exit 1
  fi
fi
$chain
exit 0
EOF
  chmod +x "$hook"
  echo "hook instalado: $hook"
}

case "$cmd" in

# ── init ─────────────────────────────────────────────────────────────────────
init)
  [ -n "$MODE_ID" ] || { echo "uso: oracfit ring init --mode <id> [--target DIR] [--oracle-cmd \"<cmd>\"] [--ceiling N] [--min-score N]" >&2; exit 3; }
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "RECUSADO: $TARGET não é repo git" >&2; exit 1; }

  # preflight de ignore (incidente 2026-08-13-ring-init-nao-atomico-sobre-ring-gitignored):
  # ring/ coberto por .gitignore do alvo fazia o `git add` do scaffold falhar
  # DEPOIS de mkdir/state/oracle/hook — scaffold pela metade, sem rollback.
  # Recusa ANTES de escrever qualquer coisa (nem run id é reservado no central).
  # Só quando ring/ ainda não existe: alvo com ring/ já commitado segue em frente
  # (a recusa por state já existe adiante).
  if [ ! -e "$RING_DIR" ]; then
    # duas formas porque padrão com barra final ("ring/") NÃO casa caminho
    # inexistente dado sem barra — medido no T27 em 2026-08-22
    ign="$(git -C "$TARGET" check-ignore -v -- "$RING_DIR_NAME" "$RING_DIR_NAME/" 2>/dev/null || true)"
    [ -z "$ign" ] || {
      echo "RECUSADO: $RING_DIR_NAME/ está coberto por ignore do alvo — scaffold não pode ser commitado." >&2
      echo "  regra: $ign" >&2
      echo "  remova a regra do .gitignore (ou negue com !$RING_DIR_NAME/) e re-rode o init." >&2
      exit 1
    }
  fi

  # run id: minuto + slug do alvo + 4 hex aleatórios. Granularidade de minuto
  # sozinha colidiu 2x em 2026-08-13 (runs 0323 scentmatch×RadioStudio e 0347
  # ai-usage-hub×CanIRunIt): sessões paralelas geravam o MESMO id e o histórico
  # dos alvos se entrelaçava no central. O slug torna o alvo legível a olho nu
  # no ledger; o sufixo hex + reserva atômica eliminam a colisão. O prefixo
  # <mode>-YYYYMMDD fica intacto (monitoração filtra por startswith). Runs
  # antigos seguem válidos: close/score/status usam o id do state.json como
  # está, sem validar formato. ORACFIT_RING_RUN_SUFFIX é knob de TESTE.
  # Gerado ANTES do claim de posse: o run consta no owner.lock.
  target_slug="$(basename "$TARGET" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-32)"
  run_suffix="${ORACFIT_RING_RUN_SUFFIX:-$(od -An -tx1 -N2 /dev/urandom | tr -d ' \n')}"
  run_id="${MODE_ID}-$(date +%Y%m%d-%H%M)-${target_slug:-alvo}-${run_suffix}"

  # posse ANTES do check de state: a mensagem certa para executor duplicado
  # é "há uma sessão VIVA neste alvo", não "state já existe" — e o claim
  # atômico (flock) fecha a janela check→write do init: dois inits
  # simultâneos num alvo virgem, exatamente um vence. Ring pré-feature
  # (state sem lock) recusa por state, sem claim.
  if [ -f "$STATE" ] && [ ! -f "$OWNER_LOCK" ]; then
    echo "RECUSADO: $STATE já existe" >&2; exit 1
  fi
  owner_guard init "$run_id"
  [ -f "$STATE" ] && { echo "RECUSADO: $STATE já existe" >&2; exit 1; }

  # reserva ATÔMICA do run id no central: check e append de um evento `init`
  # (com target) no MESMO critical section, sob flock exclusivo do arquivo.
  # Check-then-append em dois passos deixava dois inits CONCORRENTES com o
  # mesmo minuto+sufixo passarem ambos (cada um lê antes do append do outro)
  # — achado do critic do RING-1 (run ananke-20260813-0400). Recusa antes de
  # criar qualquer coisa: init recusado não deixa scaffold pela metade.
  init_line=""
  if ! init_line=$(py - "$CENTRAL_LEDGER" "$run_id" "$MODE_ID" "$TARGET" <<'EOF'
import datetime, fcntl, json, os, sys
central, run_id, mode, target = sys.argv[1:5]
d = os.path.dirname(central)
if d:
    os.makedirs(d, exist_ok=True)
f = open(central, "a+", encoding="utf-8")
fcntl.flock(f, fcntl.LOCK_EX)
f.seek(0)
for line in f:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
    except json.JSONDecodeError:
        continue
    if e.get("run") == run_id:
        print(e.get("target") or "(evento sem target)")
        sys.exit(1)
ev = {"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
      "schema": "ring-v1", "mode": mode, "run": run_id, "ring": "",
      "event": "init", "target": target}
line = json.dumps(ev, ensure_ascii=False)
f.write(line + "\n")
f.flush()
print(line)
EOF
); then
    echo "RECUSADO: run id $run_id já existe no ledger central ($CENTRAL_LEDGER) — alvo do evento existente: ${init_line:-desconhecido}. Rode o init de novo (novo sufixo) ou investigue a colisão." >&2
    exit 1
  fi

  mkdir -p "$RING_DIR/verdicts" "$RING_DIR/notes" "$RING_DIR/screens"
  touch "$LEDGER"
  # cópia do evento init no ledger do workdir (o central já o tem, pela reserva)
  echo "$init_line" >> "$LEDGER"

  if [ -n "$ORACLE_CMD" ]; then
    printf '#!/usr/bin/env bash\n# oráculo mecânico do alvo — MONOTÔNICO (sha256 vigiado pelo runner)\nset -uo pipefail\n%s\n' "$ORACLE_CMD" > "$RING_DIR/oracle.sh"
  else
    cat > "$RING_DIR/oracle.sh" <<'EOF'
#!/usr/bin/env bash
# oráculo mecânico do alvo — EDITE antes do primeiro anel.
# Enquanto não editado, falha fechado (exit 2 = oráculo quebrado, não
# "falta trabalho" — regra da casa).
echo "EDITE ${BASH_SOURCE[0]}: defina o oráculo mecânico do alvo (suíte/typecheck)" >&2
exit 2
EOF
  fi
  chmod +x "$RING_DIR/oracle.sh"

  py - "$STATE" "$MODE_ID" "$run_id" "${CEILING:-5}" "${MIN_SCORE:-4.5}" "$(oracle_sha)" "$CENTRAL_LEDGER" <<'EOF'
import json, sys
path, mode, run, ceiling, min_score, sha, central = sys.argv[1:8]
state = {
    "schema": "ring-state-v1",
    "mode": mode,
    "run": run,
    "ceiling": int(ceiling),
    "close_attempt_ceiling": 5,
    "min_score": float(min_score),
    "score_field": "owner_score_pred",
    "max_critical": 0,
    "required_fields": [],
    "retest_runs": 2,
    "visual_globs": ["*.html", "*.css", "public/*", "*.svelte", "*.vue", "*.jsx", "*.tsx"],
    "min_disk_gb": 10,
    "preflight_cmd": "",
    "oracle_sha256": sha,
    "central_ledger": central,
    "current_ring": None,
    "contract": "close exige: verdicts/<RING>.json APPROVED com biggest_gap + "
                "owner_score_pred, notes/<RING>.md, oráculo verde, pathspec explícito",
}
json.dump(state, open(path, "w"), ensure_ascii=False, indent=2)
EOF
  install_hook || true
  # identidade efetiva vazia: o preflight só AVISAVA (débito 3 do run
  # ananke-20260813-0347) e o commit de scaffold saía com autoria default de
  # host — ou falhava. Identidade LOCAL do run: por-worktree quando
  # worktreeConfig está ligada, senão local; o global do dono nunca é tocado.
  if [ -z "$(git_t config user.name || true)" ] || [ -z "$(git_t config user.email || true)" ]; then
    id_scope="--local"
    if is_worktree && [ "$(git_t config --bool extensions.worktreeConfig 2>/dev/null || true)" = "true" ]; then
      id_scope="--worktree"
    fi
    [ -n "$(git_t config user.name || true)" ] || git_t config "$id_scope" user.name "oracfit-ring"
    [ -n "$(git_t config user.email || true)" ] || git_t config "$id_scope" user.email "ring@oracfit.local"
    echo "init: identidade git efetiva incompleta — completada com identidade do run ($id_scope): oracfit-ring <ring@oracfit.local>"
  fi
  # scaffold commitado já no init: oracle.sh fora do commit viraria órfão
  # permanente na pós-condição do close (árvore nunca limpa)
  git_t add -- "$RING_DIR_NAME/state.json" "$RING_DIR_NAME/oracle.sh" "$RING_DIR_NAME/ledger.jsonl"
  # hook por-worktree mora DENTRO da árvore (ring/hooks) — entra no commit de
  # scaffold, senão a pós-condição de árvore limpa do close quebraria
  if [ -f "$RING_DIR/hooks/pre-commit" ]; then
    git_t add -- "$RING_DIR_NAME/hooks/pre-commit"
  fi
  if ! ORACFIT_RING_COMMIT=1 git_t commit -q -m "ring: init (mode=$MODE_ID run=$run_id)"; then
    # fail-closed (débito 11, run ananke-20260813-0412, leadher): o `|| true`
    # engolia a recusa do hook do alvo (commitlint recusa type "ring") e o
    # scaffold ficava staged-mas-não-commitado — o PRIMEIRO close recusava
    # por staging_com_resto_alheio, longe da causa. Sem --no-verify: o hook
    # do alvo é gate do DONO, não obstáculo.
    git_t reset -q -- "$RING_DIR_NAME" 2>/dev/null || true
    hooks_eff="$(git_t config core.hooksPath 2>/dev/null || true)"
    [ -n "$hooks_eff" ] || hooks_eff="$(git_t rev-parse --git-path hooks)"
    case "$hooks_eff" in /*) : ;; *) hooks_eff="$TARGET/$hooks_eff" ;; esac
    common_hooks="$(git_t rev-parse --git-common-dir)/hooks"
    case "$common_hooks" in /*) : ;; *) common_hooks="$TARGET/$common_hooks" ;; esac
    hook_note=""
    for hd in "$hooks_eff" "$common_hooks"; do
      for hname in commit-msg pre-commit; do
        if [ -x "$hd/$hname" ] && ! grep -q oracfit-ring-guard "$hd/$hname" 2>/dev/null; then
          hook_note=" hipótese: hook do repo recusou a mensagem 'ring: …' — commitlint/lefthook? ($hd/$hname)"
          break 2
        fi
      done
    done
    echo "QUEBRADO: commit do scaffold do init FALHOU (erro do hook acima).$hook_note" >&2
    echo "scaffold DESFEITO do staging (nada fica staged em silêncio); os arquivos seguem em $RING_DIR." >&2
    echo "resolva o gate do dono e re-rode o init depois de remover $RING_DIR." >&2
    exit 2
  fi
  echo "init: $RING_DIR pronto (mode=$MODE_ID run=$run_id ceiling=${CEILING:-5})"
  echo "next: edite $RING_DIR/oracle.sh e rode: oracfit ring open RING-1 \"hipótese\" --target $TARGET"
  ;;

# ── open ─────────────────────────────────────────────────────────────────────
open)
  ring="${POSITIONAL[0]:-}"; hypothesis="${POSITIONAL[1]:-}"
  [ -n "$ring" ] && [ -n "$hypothesis" ] || { echo "uso: oracfit ring open RING-N \"hipótese\" [--target DIR]" >&2; exit 3; }
  require_state
  require_owner

  current="$(state_get current_ring)"
  [ -z "$current" ] || { echo "RECUSADO: anel $current ainda aberto. Um anel por vez." >&2; exit 1; }

  opened=$(count_events open)
  ceiling=$(state_get ceiling)
  if [ "$opened" -ge "$ceiling" ]; then
    echo "RECUSADO: teto de $ceiling anéis no run $(state_get run) já atingido ($opened abertos)." >&2
    exit 1
  fi
  if [ -n "$(ring_event "$ring" open)" ]; then
    echo "RECUSADO: $ring já existe no run $(state_get run)." >&2
    exit 1
  fi

  # validação do modo (talos: mode validate FAIL no próprio yaml; aion: claim
  # sem mecanismo). Modo declarado precisa validar E passar no lint.
  mode_id="$(state_get mode)"
  mode_yaml="$TARGET/core/modes/${mode_id}.yaml"
  [ -f "$mode_yaml" ] || mode_yaml="$ORACFIT_ROOT/core/modes/${mode_id}.yaml"
  if [ -f "$mode_yaml" ]; then
    py "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$mode_yaml" >/dev/null \
      || { echo "RECUSADO: modo $mode_id não valida no schema ($mode_yaml)" >&2; exit 1; }
    py "$SCRIPT_DIR/lib-oracfit-mode-loader.py" lint "$mode_yaml" --root "$ORACFIT_ROOT" \
      || { echo "RECUSADO: modo $mode_id reprovou no lint claims→mecanismos" >&2; exit 1; }
  else
    echo "open WARN: core/modes/${mode_id}.yaml não existe — sem validação de modo" >&2
  fi

  # preflight mecânico (pulado 2x no autarca — agora é o open que roda)
  preflight_args=(--min-disk-gb "$(state_get min_disk_gb)" --require-clean --ignore "$RING_DIR_NAME")
  pcmd="$(state_get preflight_cmd)"
  [ -n "$pcmd" ] && preflight_args+=(--custom "$pcmd")
  bash "$SCRIPT_DIR/ring-preflight.sh" "$TARGET" "${preflight_args[@]}" || exit 1

  # trave congelada: sha do oráculo gravado no open
  [ -x "$RING_DIR/oracle.sh" ] || { echo "RECUSADO: $RING_DIR/oracle.sh ausente ou não-executável" >&2; exit 1; }
  sha="$(oracle_sha)"
  state_set oracle_sha256 "$sha"

  # bash 3.2 do macOS mangle `py -c` com {} aninhado em $() — sempre heredoc+env
  open_extra=$(HYP="$hypothesis" SHA="$sha" py - <<'EOF'
import json, os
print(json.dumps({"hypothesis": os.environ["HYP"],
                  "oracle_sha256": os.environ["SHA"],
                  "preflight": "pass"}, ensure_ascii=False))
EOF
)
  append_ledger "$(make_event "$ring" open "$open_extra")"
  state_set current_ring "$ring"
  state_set open_ts "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

  echo "ABERTO: $ring (anel $((opened + 1))/$ceiling do run $(state_get run))"
  echo "contrato do close: $(state_get contract)"
  ;;

# ── close ────────────────────────────────────────────────────────────────────
close)
  ring="${POSITIONAL[0]:-}"
  [ -n "$ring" ] || { echo "uso: oracfit ring close RING-N [--target DIR] -- <pathspec...>" >&2; exit 3; }
  require_state
  require_owner
  [ "$seen_dashdash" = "1" ] || { echo "RECUSADO: pathspec explícito obrigatório após '--' (nunca add -A)." >&2; exit 1; }
  [ ${#PATHSPEC[@]} -gt 0 ] || { echo "RECUSADO: nenhum pathspec informado." >&2; exit 1; }
  [ "$(state_get current_ring)" = "$ring" ] || { echo "RECUSADO: $ring não é o anel aberto (aberto: '$(state_get current_ring)')." >&2; exit 1; }

  refuse_attempt() { # $1=reason — falha contável, anel segue aberto
    append_ledger "$(make_event "$ring" close_attempt "{\"reason\": \"$1\"}")"
    attempts=$(count_events close_attempt "$ring")
    att_ceiling=$(state_get close_attempt_ceiling)
    echo "RECUSADO ($1): anel $ring continua aberto — tentativa $attempts/$att_ceiling." >&2
    if [ "$attempts" -ge "$att_ceiling" ]; then
      echo "TETO DE TENTATIVAS ATINGIDO: pare, registre pendência de dono, ou 'oracfit ring abort $ring \"motivo\"'." >&2
    fi
    exit 1
  }

  attempts=$(count_events close_attempt "$ring")
  att_ceiling=$(state_get close_attempt_ceiling)
  verdict_file="$RING_DIR/verdicts/$ring.json"
  notes_file="$RING_DIR/notes/$ring.md"

  # (0) histórico de vereditos: TODO veredito que o close vê é preservado
  # ANTES de qualquer recusa — inclusive a do TETO de tentativas — via
  # snapshot round-K + evento `verdict` no ledger (workdir + central).
  # Sem isto, REJECTED sobrescrito por APPROVED entre rounds do critic
  # apagava o round 1 de fato (gap ACEITO do close do A-3, run
  # ananke-20260813-0011: verdict untracked e ledger sem evento de
  # veredito). O snapshot não conta tentativa: preservar é sempre seguro.
  # Dedupe por conteúdo: recusa repetida do MESMO veredito não multiplica
  # arquivo nem evento.
  if [ -f "$verdict_file" ]; then
    # round = próximo número LIVRE (não tentativa+1): acima do teto,
    # attempts congela e tentativa+1 reusaria o número — segundo veredito
    # distinto sobrescreveria o snapshot anterior (achado do critic, round 3)
    round=1
    round_dup=0
    for f in "$RING_DIR/verdicts/$ring".round-*.json; do
      [ -f "$f" ] || continue
      cmp -s "$f" "$verdict_file" && { round_dup=1; break; }
      n="${f##*round-}"; n="${n%.json}"
      case "$n" in *[!0-9]*|'') continue ;; esac
      [ "$n" -ge "$round" ] && round=$((n + 1))
    done
    if [ "$round_dup" -eq 0 ]; then
      cp "$verdict_file" "$RING_DIR/verdicts/$ring.round-$round.json"
      verdict_extra=$(py - "$verdict_file" "$round" "$(state_get score_field)" <<'EOF'
import hashlib, json, sys
vf, rnd, score_field = sys.argv[1:4]
raw = open(vf, "rb").read()
ev = {"round": int(rnd), "sha256": hashlib.sha256(raw).hexdigest()}
try:
    v = json.loads(raw)
    if not isinstance(v, dict):
        raise ValueError("raiz não é objeto")
    ev["verdict"] = v.get("verdict")
    ev[score_field] = v.get(score_field)
    ev["biggest_gap"] = v.get("biggest_gap")
except Exception:
    ev["verdict"] = "(ilegível)"   # sha256 preserva a prova mesmo assim
print(json.dumps(ev, ensure_ascii=False))
EOF
)
      append_ledger "$(make_event "$ring" verdict "$verdict_extra")"
    fi
  fi

  if [ "$attempts" -ge "$att_ceiling" ]; then
    echo "RECUSADO: teto de $att_ceiling tentativas de close no $ring já atingido — abort ou dono." >&2
    exit 1
  fi
  [ -f "$verdict_file" ] || refuse_attempt "verdict_ausente"
  [ -f "$notes_file" ] || refuse_attempt "notes_ausentes"

  # (1) contrato do veredito — fail-closed (lib compartilhada)
  verdict_args=(--min-score "$(state_get min_score)" --score-field "$(state_get score_field)" --max-critical "$(state_get max_critical)")
  req_fields=$(py -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('required_fields') or []))" "$STATE")
  for f in $req_fields; do verdict_args+=(--require-field "$f"); done
  vrc=0
  py "$SCRIPT_DIR/check-verdict.py" "$verdict_file" "${verdict_args[@]}" || vrc=$?
  if [ "$vrc" -eq 2 ]; then refuse_attempt "verdict_quebrado"; fi
  if [ "$vrc" -ne 0 ]; then refuse_attempt "verdict_recusado"; fi

  # (2) guarda monotônica da trave: sha divergente do open exige DECLARACAO
  # nas notas + oracle_change_approved:true no veredito (critic aprovou).
  open_sha=$(ring_event "$ring" open | py -c "import json,sys;print(json.load(sys.stdin).get('oracle_sha256',''))")
  now_sha="$(oracle_sha)"
  if [ "$open_sha" != "$now_sha" ]; then
    # heading markdown também vale (débito 14, run ananke-20260813-0412:
    # "## DECLARACAO-ORACULO:" custou 1 tentativa contável ao leadher)
    if ! grep -qE '^(DECLARACAO-ORACULO:|#{1,6}[[:space:]]*DECLARACAO-ORACULO)' "$notes_file"; then
      echo "formato esperado em $RING_DIR_NAME/notes/$ring.md: linha 'DECLARACAO-ORACULO: <motivo da mudança da trave>' (heading markdown '# DECLARACAO-ORACULO: …' também vale)." >&2
      refuse_attempt "oraculo_mudou_sem_declaracao"
    fi
    approved=$(py -c "import json,sys;print(json.load(open(sys.argv[1])).get('oracle_change_approved') is True)" "$verdict_file")
    [ "$approved" = "True" ] || refuse_attempt "oraculo_mudou_sem_aprovacao_do_critic"
    echo "close: trave mudou COM declaração + aprovação do critic — registrado."
  fi

  # (3) staging guard: pré-staged alheio recusa (commit de nascimento do autarca)
  prestaged=$(git_t diff --cached --name-only)
  if [ -n "$prestaged" ]; then
    echo "staging já continha (NÃO é deste anel?):" >&2
    echo "$prestaged" | head -10 >&2
    refuse_attempt "staging_com_resto_alheio"
  fi

  # (4) oráculo mecânico (a trave congelada) — exit + duração medidos AQUI,
  # em MILISSEGUNDOS por rodada (débito 12: duration_s inteiro gravou 0 a
  # noite inteira e escondeu a rodada-espelho de 77ms do leadher)
  echo "== oráculo: $RING_DIR_NAME/oracle.sh =="
  t0=$(now_ms); oracle_exit=0
  ( cd "$TARGET" && bash "$RING_DIR/oracle.sh" ) || oracle_exit=$?
  t1=$(now_ms)
  oracle_ms_list=$((t1 - t0))
  oracle_total_ms=$((t1 - t0))
  if [ "$oracle_exit" -ne 0 ]; then
    refuse_attempt "oraculo_vermelho_exit_$oracle_exit"
  fi

  # (5) stage do build + detecção de testes novos p/ retest descorrelacionado
  git_t add -- "${PATHSPEC[@]}" 2>/dev/null || refuse_attempt "pathspec_invalido"
  staged_files=$(git_t diff --cached --name-only)
  # `(^|/)test_` cobre a convenção python test_*.py — achado do teste de
  # campo A-1 (2026-08-13): sem ele o retest não disparou em test_fifoq.py
  new_tests=$(echo "$staged_files" | grep -E '(^|/)tests?/|(^|/)__tests__/|(^|/)test_|\.(test|spec)\.|_test\.|-test\.' || true)
  oracle_runs=1
  if [ -n "$new_tests" ]; then
    retest_runs=$(state_get retest_runs)
    echo "== retest descorrelacionado: testes novos/tocados detectados, re-rodando oráculo $((retest_runs - 1))x =="
    i=1
    while [ "$i" -lt "$retest_runs" ]; do
      sleep 2
      rexit=0
      rt0=$(now_ms)
      ( cd "$TARGET" && bash "$RING_DIR/oracle.sh" ) || rexit=$?
      rt1=$(now_ms)
      oracle_ms_list="$oracle_ms_list $((rt1 - rt0))"
      oracle_total_ms=$((oracle_total_ms + rt1 - rt0))
      oracle_runs=$((oracle_runs + 1))
      if [ "$rexit" -ne 0 ]; then
        git_t reset -- "${PATHSPEC[@]}" >/dev/null 2>&1 || true
        refuse_attempt "retest_vermelho_run${oracle_runs}_exit_$rexit"
      fi
      i=$((i + 1))
    done
  fi

  # (5.5) rodada-espelho (débito 12, run ananke-20260813-0412): a 2ª rodada
  # do oráculo do leadher foi "FULL TURBO" em 77ms — cache do runner de teste
  # transforma o retest anti-flake num no-op. NÃO bloqueia (suíte legítima
  # rápida nas duas rodadas seria falso positivo): a evidência vai pro ledger
  # (retest_suspeito) e pro stderr.
  retest_suspeito=false
  if [ "$oracle_runs" -ge 2 ]; then
    r1_ms=$(echo "$oracle_ms_list" | awk '{print $1}')
    r2_ms=$(echo "$oracle_ms_list" | awk '{print $2}')
    if [ "$r1_ms" -ge 5000 ] && [ $((r2_ms * 10)) -lt "$r1_ms" ]; then
      retest_suspeito=true
      echo "WARN: retest descorrelacionado SUSPEITO — rodada 1 ${r1_ms}ms, rodada 2 ${r2_ms}ms (<10% da 1ª)." >&2
      echo "causa provável: CACHE do runner de teste (turbo/jest — desative o cache no ring/oracle.sh, ex.: turbo run test --force). O close segue; a evidência fica no ledger (retest_suspeito)." >&2
    fi
  fi
  oracle_s=$(py -c "print(round($oracle_total_ms / 1000, 3))")

  # (6) gate visual por gatilho de diff: tocou tela → exige screenshot novo.
  # Predicado vem da lib de gates (oracfit_visual_hits) — mesmo código que o
  # gauntlet do escalate usa; globs continuam configuráveis pelo state.json.
  visual_globs=$(py -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('visual_globs') or []))" "$STATE")
  visual_hit=$(printf '%s\n' "$staged_files" | oracfit_visual_hits "$visual_globs")
  visual_note="n/a"
  if [ -n "$visual_hit" ]; then
    screens="$RING_DIR/screens/$ring"
    # pipefail: find em dir inexistente mataria o script em silêncio
    nshots=0
    [ -d "$screens" ] && nshots=$(find "$screens" -type f | wc -l | tr -d ' ')
    if [ "$nshots" -eq 0 ]; then
      git_t reset -- "${PATHSPEC[@]}" >/dev/null 2>&1 || true
      echo "diff tocou artefato visual:" >&2
      echo "$visual_hit" | head -5 >&2
      echo "gate visual: coloque >=1 screenshot em $screens/ (renderize a tela de verdade)." >&2
      refuse_attempt "visual_sem_screenshot"
    fi
    visual_note="$RING_DIR_NAME/screens/$ring ($nshots arquivo(s))"
  fi

  # (7) build commit (pathspec explícito; bypass do hook via env do runner)
  build_commit=""
  if ! git_t diff --cached --quiet; then
    ORACFIT_RING_COMMIT=1 git_t commit -q -m "ring($ring): build" || refuse_attempt "build_commit_falhou"
    build_commit=$(git_t rev-parse --short HEAD)
  fi

  # (8) checkpoint com números MEDIDOS por este script (claims-check: quem
  # escreve os números é o runner; prosa do executor vai em notes)
  n_files=$(echo "$staged_files" | grep -c . || true)
  n_new_tests=$(echo "$new_tests" | grep -c . || true)
  hypothesis=$(ring_event "$ring" open | py -c "import json,sys;print(json.load(sys.stdin).get('hypothesis',''))")
  py - "$verdict_file" "$CHECKPOINTS" "$ring" "$(state_get run)" "$hypothesis" \
       "$build_commit" "$oracle_exit" "$oracle_s" "$oracle_runs" "$n_files" "$n_new_tests" \
       "$visual_note" "$notes_file" "$(state_get score_field)" <<'EOF'
import json, sys, datetime
(vf, cp, ring, run, hyp, commit, o_exit, o_s, o_runs,
 n_files, n_tests, visual, notes_file, score_field) = sys.argv[1:15]
v = json.load(open(vf))
notes = open(notes_file, encoding="utf-8").read().strip()
now = datetime.datetime.now().astimezone().isoformat(timespec="minutes")
entry = f"""
## {ring} — {now} (run {run})

**Hipótese:** {hyp}

**Oráculo (medido pelo runner):** exit {o_exit} ({o_s}s), {o_runs} rodada(s)
**Arquivos no anel (medido):** {n_files} staged, {n_tests} de teste
**Gate visual:** {visual}
**Critic:** {v['verdict']} · {score_field}={v.get(score_field)}
**Maior lacuna (biggest_gap):** {v['biggest_gap']}
**Commit do build:** {commit or "(sem diff staged — anel de infra/doc)"}

{notes}
"""
open(cp, "a", encoding="utf-8").write(entry)
EOF

  # (9) TRANSAÇÃO: linha de close no ledger ANTES do commit de checkpoint,
  # estado atualizado, e o commit INCLUI ledger+estado (satélite aion).
  close_extra=$(py - "$verdict_file" "$oracle_exit" "$oracle_s" "$oracle_runs" "$build_commit" "$n_files" "$n_new_tests" "$(state_get score_field)" "$oracle_ms_list" "$retest_suspeito" <<'EOF'
import json, sys
(vf, o_exit, o_s, o_runs, commit, n_files, n_tests,
 score_field, ms_list, suspeito) = sys.argv[1:11]
v = json.load(open(vf))
print(json.dumps({
    "oracle": {"exit": int(o_exit), "duration_s": float(o_s), "runs": int(o_runs),
               "durations_ms": [int(x) for x in ms_list.split()]},
    "retest_suspeito": suspeito == "true",
    "verdict": v["verdict"], score_field: v.get(score_field),
    "biggest_gap": v["biggest_gap"], "build_commit": commit,
    "files_staged": int(n_files), "test_files": int(n_tests),
}, ensure_ascii=False))
EOF
)
  append_ledger "$(make_event "$ring" close "$close_extra")"
  state_set current_ring "" null
  state_set oracle_sha256 "$now_sha"

  git_t add -- "$RING_DIR_NAME/ledger.jsonl" "$RING_DIR_NAME/state.json" \
    "$RING_DIR_NAME/oracle.sh" "$RING_DIR_NAME/verdicts/$ring.json" \
    "$RING_DIR_NAME/notes/$ring.md" CHECKPOINTS.md
  # rounds preservados entram TRACKED junto do veredito final (RING-3)
  for f in "$RING_DIR/verdicts/$ring".round-*.json; do
    [ -f "$f" ] && git_t add -- "$RING_DIR_NAME/verdicts/$(basename "$f")" || true
  done
  [ -d "$RING_DIR/screens/$ring" ] && git_t add -- "$RING_DIR_NAME/screens/$ring" 2>/dev/null || true
  ORACFIT_RING_COMMIT=1 git_t commit -q -m "ring($ring): checkpoint" \
    || { echo "QUEBRADO: commit de checkpoint falhou — ledger tem close sem commit, corrija a árvore" >&2; exit 2; }
  cp_commit=$(git_t rev-parse --short HEAD)

  # hash do checkpoint vai só ao ledger CENTRAL (fora da árvore do alvo:
  # não suja a pós-condição e continua contabilizado mecanicamente)
  append_central_only "$(make_event "$ring" checkpoint_commit "{\"commit\": \"$cp_commit\"}")"

  # (10) pós-condição: árvore limpa nos paths do anel
  leftover=$(git_t status --porcelain -- "$RING_DIR_NAME" CHECKPOINTS.md "${PATHSPEC[@]}" 2>/dev/null || true)
  if [ -n "$leftover" ]; then
    echo "QUEBRADO: pós-condição violada — árvore suja depois do close:" >&2
    echo "$leftover" >&2
    exit 2
  fi

  closed=$(count_events close)
  echo "FECHADO: $ring ($closed/$(state_get ceiling) anéis no run $(state_get run))"
  echo "build=$build_commit checkpoint=$cp_commit oracle=exit0/${oracle_s}s/${oracle_runs}x"
  ;;

# ── abort ────────────────────────────────────────────────────────────────────
abort)
  ring="${POSITIONAL[0]:-}"; reason="${POSITIONAL[1]:-}"
  [ -n "$ring" ] || { echo "uso: oracfit ring abort RING-N \"motivo\" [--target DIR]" >&2; exit 3; }
  require_state
  require_owner
  [ "$(state_get current_ring)" = "$ring" ] || { echo "RECUSADO: $ring não é o anel aberto." >&2; exit 1; }
  # auditoria do abort (débito 10, run ananke-20260813-0421): o close exige
  # notes/<RING>.md, mas o abort aceitava anel sem nota nenhuma — abort mudo
  # é buraco de auditoria. Exige motivo não-vazio OU notes/<RING>.md
  # existente (aí o reason do ledger aponta para as notas). Aborts já
  # gravados não são revalidados.
  if [ -z "$(printf '%s' "$reason" | tr -d '[:space:]')" ]; then
    if [ -f "$RING_DIR/notes/$ring.md" ]; then
      reason="ver $RING_DIR_NAME/notes/$ring.md"
    else
      echo "RECUSADO: abort sem motivo — passe \"motivo\" não-vazio ou escreva $RING_DIR_NAME/notes/$ring.md antes (abort mudo é buraco de auditoria)." >&2
      exit 1
    fi
  fi
  abort_extra=$(REASON="$reason" py - <<'EOF'
import json, os
print(json.dumps({"reason": os.environ["REASON"]}, ensure_ascii=False))
EOF
)
  append_ledger "$(make_event "$ring" abort "$abort_extra")"
  state_set current_ring "" null
  echo "ABORTADO: $ring (motivo registrado no ledger; o open dele segue contando no teto)"
  ;;

# ── score ────────────────────────────────────────────────────────────────────
score)
  ring="${POSITIONAL[0]:-}"
  [ -n "$ring" ] && [ -n "$REAL_SCORE" ] || { echo "uso: oracfit ring score RING-N --real N [--target DIR]" >&2; exit 3; }
  require_state
  close_line=$(ring_event "$ring" close)
  [ -n "$close_line" ] || { echo "RECUSADO: $ring não tem close no run $(state_get run)." >&2; exit 1; }
  score_field="$(state_get score_field)"
  pred=$(echo "$close_line" | py -c "import json,sys;print(json.load(sys.stdin).get('$score_field',''))")
  [ -n "$pred" ] || { echo "QUEBRADO: close de $ring sem campo $score_field no ledger" >&2; exit 2; }
  score_extra=$(REAL="$REAL_SCORE" PRED="$pred" py - <<'EOF'
import json, os
real, pred = float(os.environ["REAL"]), float(os.environ["PRED"])
print(json.dumps({"real": real, "pred": pred, "delta": round(real - pred, 2)}))
EOF
)
  delta=$(echo "$score_extra" | py -c "import json,sys;print(json.load(sys.stdin)['delta'])")
  append_ledger "$(make_event "$ring" owner_score "$score_extra")"
  echo "CALIBRAÇÃO $ring: previsto=$pred real=$REAL_SCORE delta=$delta"
  echo "(delta acumulado do critic: rg owner_score $LEDGER)"
  echo "lembrete: commite $RING_DIR_NAME/ledger.jsonl no próximo anel (linha de score fora de commit até lá)"
  ;;

# ── status ───────────────────────────────────────────────────────────────────
status)
  require_state
  echo "mode: $(state_get mode) · run: $(state_get run) · teto: $(state_get ceiling)"
  echo "abertos: $(count_events open) · fechados: $(count_events close) · aborts: $(count_events abort) · anel aberto: $(state_get current_ring)"
  echo "trave: $RING_DIR/oracle.sh sha256=$(oracle_sha | cut -c1-12)…"
  tail -5 "$LEDGER" 2>/dev/null || true
  ;;

# ── hook-install ─────────────────────────────────────────────────────────────
hook-install)
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "RECUSADO: $TARGET não é repo git" >&2; exit 1; }
  install_hook
  ;;

*)
  usage
  ;;
esac
