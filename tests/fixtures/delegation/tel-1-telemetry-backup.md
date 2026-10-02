EXECUTE A ESPEC ABAIXO por completo (o cabeçalho YAML e as seções são contrato, não comentário).

---
id: "tel-1-telemetria-backup"
schema: 1
status: ready
owner: "claude-opus (orquestrador)"
modelo: "claude-sonnet-5"
tentativas: 3
bloqueio: false
evidencia: "/opt/inference/SPEC.md (ADR-034)"
---

# TEL-1 — telemetria no HD /data (fora do git) + backup diário do banco do gateway

REGRAS DE OURO (violar qualquer uma = reprovação imediata):
- Workdir: /opt/inference. Escreva SÓ os arquivos listados em ENTREGÁVEIS. Não edite nenhum outro arquivo.
- O rig está SERVINDO agora. NUNCA rode systemctl, docker, nvidia-smi, pg_dump, curl, sudo, nem os scripts de
  bin/ fora dos testes. Nos testes, `docker`, `nvidia-smi` e afins são FAKES em um PATH temporário.
- NUNCA escreva em /data, em ~/.local/state nem em report/ — nos testes use só diretórios temporários
  (RIG_TELEMETRIA, RIG_BACKUP e XDG_STATE_HOME apontando para tempfile).
- NUNCA git commit, push, reset, checkout, switch, stash, rm --cached; nada de rm -rf.
- Nao invente numero, caminho, usuário, container ou flag alem dos listados nesta espec. Valor nao decidido = [A DEFINIR].
- NUNCA use declare const, stub vazio ou `true` como workaround para passar teste — implemente de verdade.
- Nunca leia secrets/ nem gateway/.env. O backup não precisa de senha (pg_dump roda DENTRO do container).

## Dados verificados (copie SEM ALTERAR)
- ADR-034 em SPEC.md (leia). Story: stories/TEL-1.json.
- Escritores de telemetria hoje (3): bin/gpu-telemetry.sh (`>> /opt/inference/report/gpu.csv`),
  bin/health-passive.sh (`CSV=$BASE/report/health-passive.csv`), bin/healthcheck.sh (`CSV=$BASE/report/health.csv`,
  `FAILFILE=$BASE/report/health-fail-streak`, `LOG=$BASE/report/health-events.log`).
- Banco: container `gemma-gateway-db`, imagem postgres:18-alpine, POSTGRES_USER=litellm, POSTGRES_DB=litellm
  (gateway/docker-compose.yml). Comando de dump: `docker exec gemma-gateway-db pg_dump -U litellm -d litellm --no-owner`.
- Diretórios: telemetria `/data/inference/telemetria`, backup `/data/inference/backup`. Hoje `/data` é do root e
  `/data/inference` ainda NÃO existe (o dono vai criar com sudo) — o código tem de lidar com isso.
- Docs que citam os caminhos antigos: docs/1-arquitetura.md, docs/3-observabilidade.md, docs/4-diagnostico.md.

## Objetivo

1. `bin/lib-telemetria.sh` (para `source`): função `telemetria_dir` que imprime o diretório a usar:
   `$RIG_TELEMETRIA` se definido, senão `/data/inference/telemetria`; faz `mkdir -p`; se não conseguir criar ou não
   for gravável → usa `${XDG_STATE_HOME:-$HOME/.local/state}/rig/telemetria` (mkdir -p) e escreve no **stderr**
   uma linha `rig-telemetria: sem acesso a <dir>; usando <fallback>`. Nunca devolve report/.
2. `bin/telemetria-dir` (executável): `source` da lib e imprime `telemetria_dir` — para docs e humanos
   (`tail "$(/opt/inference/bin/telemetria-dir)/gpu.csv"`).
3. `bin/gpu-telemetry.sh`, `bin/health-passive.sh`, `bin/healthcheck.sh`: passam a gravar `gpu.csv`,
   `health-passive.csv`, `health.csv`, `health-fail-streak`, `health-events.log` em `$(telemetria_dir)`.
   Nada mais muda no comportamento deles.
4. `bin/backup-gateway-db.sh [--dry-run]`:
   - destino `${RIG_BACKUP:-/data/inference/backup}`; `mkdir -p`; sem acesso → mensagem clara no stderr com o comando
     do dono `sudo install -d -o carlos -g carlos /data/inference` e **exit 1** (sem fallback — ADR-034);
   - `--dry-run`: imprime destino, arquivo que seria criado e quais seriam apagados; não roda docker; exit 0;
   - dump: `${DOCKER:-docker} exec gemma-gateway-db pg_dump -U litellm -d litellm --no-owner | gzip` para
     `gateway-db-AAAAMMDD-HHMMSS.sql.gz.tmp`; falha do pipe (use `set -o pipefail`) → apaga o .tmp, exit 1;
   - verifica `gzip -t` e tamanho > 0 antes do `mv` para o nome final (atômico); falha → apaga, exit 1;
   - retenção: mantém os `${RIG_BACKUP_KEEP:-14}` mais novos `gateway-db-*.sql.gz` (ordem por nome), apaga o resto;
   - acrescenta `data_iso,arquivo,bytes,ok` em `$(telemetria_dir)/backup.csv`.
5. `systemd/rig-backup.service` (oneshot, `ExecStart=/opt/inference/bin/backup-gateway-db.sh`) e
   `systemd/rig-backup.timer` (`OnCalendar=*-*-* 04:30:00`, `Persistent=true`, `RandomizedDelaySec=10min`).
   Primeira linha do .timer: `# PENDENTE TEL-1: instalar no rig depois do OK do dono` (pending_marker).
6. Docs: nas 3 docs listadas, troque `report/gpu.csv`, `report/health.csv`, `report/health-passive.csv` e
   `/opt/inference/report/...` por `$(bin/telemetria-dir)/<arquivo>` (ou `/opt/inference/bin/telemetria-dir` nos
   comandos absolutos) e cite ADR-034 uma vez em cada doc. Não reescreva mais nada nas docs.
7. `tests/test_telemetria.py` (unittest, stdlib, subprocess):
   - lib: RIG_TELEMETRIA gravável → usa ele; RIG_TELEMETRIA impossível (ex.: dentro de um arquivo comum) → usa
     XDG_STATE_HOME/rig/telemetria e avisa no stderr;
   - gpu-telemetry.sh com `nvidia-smi` fake no PATH → linha nova em `$RIG_TELEMETRIA/gpu.csv`;
   - health-passive.sh e healthcheck.sh: não contêm mais `report/` e fazem `source` da lib (checagem de texto);
   - backup: `docker` fake (imprime SQL e sai 0) → arquivo .sql.gz válido, sem .tmp, linha em backup.csv;
     `docker` fake que sai 1 → exit 1 e nenhum arquivo; 16 backups antigos + KEEP=14 → sobram 14 (+ o novo cortado
     corretamente: total final = 14); destino impossível → exit 1 com "sudo install -d" no stderr; `--dry-run`
     não chama docker (fake que cria um arquivo-marcador se for chamado).

## Barra
- nome: tests.test_telemetria verde; gates portáveis verdes; suíte do trocador intacta
- como fetchar: cd /opt/inference && python3 -m unittest tests.test_telemetria -v
- como comparar: todos passam; git status mostra só ENTREGÁVEIS

## Passos
1. Leia SPEC.md (ADR-010, ADR-020, ADR-034), os 3 scripts, gateway/docker-compose.yml, as 3 docs.
2. Testes primeiro; depois lib, scripts, backup, units, docs.
3. Rode a VERIFICAÇÃO até verde.

## ENTREGÁVEIS
- bin/lib-telemetria.sh, bin/telemetria-dir, bin/backup-gateway-db.sh (novos, executáveis os dois últimos)
- bin/gpu-telemetry.sh, bin/health-passive.sh, bin/healthcheck.sh (editados)
- systemd/rig-backup.service, systemd/rig-backup.timer (novos)
- docs/1-arquitetura.md, docs/3-observabilidade.md, docs/4-diagnostico.md (só os caminhos + 1 citação de ADR-034)
- tests/test_telemetria.py (novo)

## VERIFICAÇÃO
- cd /opt/inference && python3 -m unittest tests.test_telemetria -v
- cd /opt/inference && python3 -m unittest tests.test_trocador -q
- cd /opt/inference && bin/gates.sh --local

## Oráculo
- comando: cd /opt/inference && python3 -m unittest tests.test_telemetria tests.test_trocador -q && bin/gates.sh --local && ! grep -n "report/" bin/gpu-telemetry.sh bin/health-passive.sh bin/healthcheck.sh && test -x bin/backup-gateway-db.sh && test -x bin/telemetria-dir && head -1 systemd/rig-backup.timer | grep -q "PENDENTE TEL-1"
