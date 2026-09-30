#!/usr/bin/env bash
# tests/test-gui-ajuda.sh — Story GUI-3 (docs/stories/gui-3-nao-to-achando.md)
#
#  T1  CLI v2: link+copy juntos, --step, recusas (sem link, step longo, 7 steps, href ruim)
#  T2  ordem: prioridade alta primeiro
#  T3  steps: asked_at/asked_ago, steps, href+command, artifact ok/velho/sumiu
#  T4  POST /api/gui/ajuda com modelo fake: resposta, gravação, prompt tem a ação
#  T5  recusas do ajuda (id fechado, sem imagem, imagem grande) não gravam
#  T6  modelo fora → 502 legível, print gravado mesmo assim
#  T7  passos.html tem Não tô achando + colar print; pipeline doc tem a regra do link

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORACFIT="$REPO_ROOT/bin/oracfit"
# shellcheck source=lib-gui-http.sh
source "$REPO_ROOT/tests/lib-gui-http.sh"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); gui_dump_log "${SRV_LOG:-}"; }

WORK=$(mktemp -d /tmp/test-gui-ajuda.XXXXXX)
export ORACFIT_OWNER_ACTIONS="$WORK/acoes.jsonl"
PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT
lines() { [ -f "$ORACFIT_OWNER_ACTIONS" ] && wc -l < "$ORACFIT_OWNER_ACTIONS" || echo 0; }
J() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

echo "=== test-gui-ajuda ==="

echo "--- T1: CLI v2 ---"
"$ORACFIT" acao add dns-criar --title "Criar o endereço now" --plain "Abra o link e crie o CNAME." \
  --href "https://dash.cloudflare.com/?to=/:account/orbe.live/dns/records" --command "abc.cfargotunnel.com" \
  --step "Clique em Add record" --step "Tipo CNAME, nome now|copy=now" --step "Destino|copy=abc.cfargotunnel.com" \
  --source "teste" >/dev/null 2>&1 && ok "link + copy + 3 steps aceito" || not "add v2 recusado"
N=$(lines)
"$ORACFIT" acao add sem-link --title "Faça algo" --plain "Sem link nenhum." >/dev/null 2>&1; [ $? -eq 2 ] && ok "sem link/cópia/step exit 2" || not "ação sem link aceita"
"$ORACFIT" acao add step-longo --title x --plain y --step "$(printf 'a%.0s' $(seq 1 91))" >/dev/null 2>&1; [ $? -eq 2 ] && ok "step >90 exit 2" || not "step longo aceito"
SEVEN=(); for i in 1 2 3 4 5 6 7; do SEVEN+=(--step "passo $i"); done
"$ORACFIT" acao add muitos --title x --plain y "${SEVEN[@]}" >/dev/null 2>&1; [ $? -eq 2 ] && ok "7 steps exit 2" || not "7 steps aceito"
"$ORACFIT" acao add href-ruim --title x --plain y --href "javascript:alert(1)" >/dev/null 2>&1; [ $? -eq 2 ] && ok "href não-https exit 2" || not "href ruim aceito"
[ "$(lines)" = "$N" ] && ok "recusas não gravaram" || not "recusa gravou"
"$ORACFIT" acao add decidir-preco --title "Decidir o preço" --plain "Diga um número." --decisao >/dev/null 2>&1 && ok "--decisao sem link aceito" || not "--decisao recusado"

echo "--- T2: prioridade ---"
ART="$WORK/script.js"; CTX="$WORK/contexto.md"
echo ctx > "$CTX"; sleep 1; echo "gerado" > "$ART"
"$ORACFIT" acao add rodar-script --title "Rodar o script" --plain "Rode o script gerado." \
  --command "node $ART" --artifact "$ART" --context "$CTX" --prioridade alta >/dev/null 2>&1 \
  && ok "add com artifact/context/prioridade" || not "add com artifact recusado"
"$ORACFIT" acao list | head -1 | cut -f1 | grep -qx rodar-script && ok "alta vem primeiro no list" || not "list: $("$ORACFIT" acao list)"

echo "--- sobe fake de visão + servidor ---"
FAKE_LOG="$WORK/fake.log"; REQ="$WORK/req.json"
cat > "$WORK/fake.py" <<'EOF'
import json, sys, http.server
req_path = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        open(req_path, "wb").write(body)
        out = json.dumps({"choices": [{"message": {"content": "1. Clique no botão azul Add record no canto direito."}}]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
EOF
python3 "$WORK/fake.py" "$REQ" > "$FAKE_LOG" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 25); do [ -s "$FAKE_LOG" ] && break; sleep 0.2; done
FPORT=$(head -1 "$FAKE_LOG")

WD="$WORK/wd"; LOGS="$WD/.dispatch/logs"; mkdir -p "$LOGS"
ROOT="$WORK/root"; mkdir -p "$ROOT/ledger" "$ROOT/core"
printf '{"version":1,"models":[{"id":"m-vivo","provider":"stub","tier":"free"}]}' > "$ROOT/model-registry.json"
printf '{"providers":{}}' > "$ROOT/core/usage-limits.json"
start() { # $1=vision url $2=log
  ORACFIT_VISION_URL="$1" ORACFIT_VISION_MODEL="fake-vision" python3 "$REPO_ROOT/bin/oracfit-panel-server.py" \
    --panel-dir "$REPO_ROOT/panel" --logs-dir "$LOGS" --oracfit-root "$ROOT" --port 0 --bind 127.0.0.1 > "$2" 2>&1 &
  PIDS+=($!)
}
SRV_LOG="$WORK/server.log"
start "http://127.0.0.1:$FPORT/v1" "$SRV_LOG"
PORT=$(gui_wait_port "$SRV_LOG" passos.html || true)
BASE="http://127.0.0.1:$PORT"
dono() { gui_get "$BASE/api/gui/steps" | J "print(json.dumps([s for s in d['steps'] if s['id']=='dono'][0]))"; }

echo "--- T3: campos do passo ---"
D=$(dono)
echo "$D" | J "i=d['item']; assert i['id']=='rodar-script' and i['asked_at'] and i['asked_ago'].startswith('há')" 2>/dev/null \
  && ok "alta primeiro + asked_at/asked_ago" || not "item: $D"
echo "$D" | J "a=d['item']['artifact']; assert a['status']=='ok' and a['exists'] and a['generated_at'] and a['generated_ago'].startswith('há')" 2>/dev/null \
  && ok "artifact ok com data de geração" || not "artifact: $D"
sleep 1; echo "mudou" >> "$CTX"
dono | J "a=d['item']['artifact']; assert a['status']=='velho' and a['stale_because'].endswith('contexto.md')" 2>/dev/null \
  && ok "context mudou depois → velho" || not "velho: $(dono)"
rm -f "$ART"
dono | J "assert d['item']['artifact']['status']=='sumiu'" 2>/dev/null && ok "arquivo apagado → sumiu" || not "sumiu: $(dono)"
"$ORACFIT" acao done rodar-script >/dev/null 2>&1
D=$(dono)
echo "$D" | J "i=d['item']; a=d['action']; assert i['id']=='dns-criar' and len(i['steps'])==3 and i['steps'][1]['copy']=='now' and a['href'].startswith('https://dash.cloudflare.com') and a['command']=='abc.cfargotunnel.com'" 2>/dev/null \
  && ok "steps + href + command juntos" || not "dns-criar: $D"

echo "--- T4: ajuda com modelo fake ---"
IMG="data:image/png;base64,$(printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')"
post() { curl -s -o "$WORK/resp" -w '%{http_code}' -H 'Content-Type: application/json' -d @"$1" "$BASE/api/gui/ajuda"; }
printf '{"id":"dns-criar","image":"%s","note":"não acho o botão"}' "$IMG" > "$WORK/b1.json"
[ "$(post "$WORK/b1.json")" = 200 ] && ok "ajuda 200" || not "ajuda: $(cat "$WORK/resp")"
J "assert 'Add record' in d['answer'] and d['model']=='fake-vision'" < "$WORK/resp" 2>/dev/null && ok "resposta do modelo volta" || not "resp: $(cat "$WORK/resp")"
J "m=d['messages']; txt=json.dumps(m, ensure_ascii=False); assert d['model']=='fake-vision' and 'Criar o endereço now' in txt and 'não acho o botão' in txt and 'image_url' in txt and 'TDAH' in txt" < "$REQ" 2>/dev/null \
  && ok "prompt leva ação, nota, imagem e regra TDAH" || not "prompt: $(head -c 400 "$REQ")"
ls "$LOGS"/ajuda/*-dns-criar.png >/dev/null 2>&1 && ls "$LOGS"/ajuda/*-dns-criar.json >/dev/null 2>&1 && ok "print + json gravados" || not "ajuda/ sem arquivos"
[ "$(wc -l < "$LOGS/ajuda.jsonl" 2>/dev/null)" = 1 ] && ok "1 linha em ajuda.jsonl" || not "ajuda.jsonl"

echo "--- T5: recusas ---"
printf '{"id":"rodar-script","image":"%s"}' "$IMG" > "$WORK/b2.json"
printf '{"id":"dns-criar"}' > "$WORK/b3.json"
python3 -c "import base64;print('{\"id\":\"dns-criar\",\"image\":\"data:image/png;base64,'+base64.b64encode(b'x'*(4*1024*1024+10)).decode()+'\"}')" > "$WORK/b4.json"
[ "$(post "$WORK/b2.json")" = 400 ] && ok "ação fechada 400" || not "fechada aceita"
[ "$(post "$WORK/b3.json")" = 400 ] && ok "sem imagem 400" || not "sem imagem aceito"
[ "$(post "$WORK/b4.json")" = 400 ] && ok "imagem >4MB 400" || not "grande aceita"
[ "$(wc -l < "$LOGS/ajuda.jsonl")" = 1 ] && ok "recusas não gravaram" || not "recusa gravou"

echo "--- T6: modelo fora ---"
SRV2="$WORK/server2.log"
start "http://127.0.0.1:9/v1" "$SRV2"
P2=$(gui_wait_port "$SRV2" passos.html || true)
code=$(curl -s -o "$WORK/resp2" -w '%{http_code}' -H 'Content-Type: application/json' -d @"$WORK/b1.json" "http://127.0.0.1:$P2/api/gui/ajuda")
[ "$code" = 502 ] && J "assert d['ok'] is False and 'Traceback' not in d['error'] and len(d['error'])>10" < "$WORK/resp2" 2>/dev/null \
  && ok "502 com mensagem legível" || not "modelo fora: $code $(cat "$WORK/resp2")"
[ "$(ls "$LOGS"/ajuda/*-dns-criar.png | wc -l)" = 2 ] && ok "print gravado mesmo com modelo fora" || not "print perdido"

echo "--- T7: UI + doc ---"
H=$(gui_get "$BASE/passos.html")
echo "$H" | grep -q 'Não tô achando' && ok "botão Não tô achando" || not "sem Não tô achando"
echo "$H" | grep -q 'paste' && echo "$H" | grep -q 'image/\*' && ok "colar print + input de imagem" || not "sem paste/input image"
echo "$H" | grep -q '/api/gui/ajuda' && ok "UI chama /api/gui/ajuda" || not "UI não chama ajuda"
grep -qi 'link direto' "$REPO_ROOT/docs/gui-pipeline.md" && grep -q -- '--artifact' "$REPO_ROOT/docs/gui-pipeline.md" && ok "pipeline com regra do link e artifact" || not "pipeline doc"

echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
