#!/bin/bash
# with-timeout.sh — teto de tempo para qualquer comando (substituto de timeout(1))
# Uso: bin/with-timeout.sh <segundos> <comando> [args...]
#
# macOS não traz `timeout(1)` nem `gtimeout` (sem coreutils). Sem teto, um
# comando que trava fica invisível — foi o que custou 52min em 2026-07-24
# (lessons/2026-07-24-dispatch-travado.md).
#
# Exit codes: o do comando, ou 124 se estourou o tempo (mesma convenção do
# timeout(1) do GNU).

set -uo pipefail

SECS="${1:?Uso: with-timeout.sh <segundos> <comando> [args...]}"
shift
[ $# -gt 0 ] || { echo "Uso: with-timeout.sh <segundos> <comando> [args...]" >&2; exit 3; }

# O filho vira líder do próprio grupo de processos (setpgrp) e o timeout mata o
# GRUPO inteiro (kill -PID), não só o filho.
#
# Por que isso importa: `runner.sh` é um wrapper que spawna o CLI (ex.: `opencode
# run`). Matar só o filho direto deixa o NETO vivo segurando o pipe de stdout —
# o chamador continua bloqueado e o teto não vale nada. Bug real observado em
# 2026-07-24: tarefa presa 7min apesar de `with-timeout 300`
# (incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md).
perl -e '
  my $secs = shift;
  my $pid = fork();
  die "fork falhou: $!" unless defined $pid;
  if ($pid == 0) {
      setpgrp(0, 0);
      # stdin de /dev/null por padrão. CLI agêntico (opencode, claude) herda o
      # stdin do terminal e FICA ESPERANDO ENTRADA que nunca vem — pendura com a
      # resposta já pronta, sem erro em lugar nenhum. Foi a causa real de todos
      # os travamentos "modo 2" de 2026-07-24/25, que eu atribuí a rate limit,
      # concorrência, banco, TLS e credencial — todas erradas.
      # RUN_WITH_STDIN=1 preserva o stdin quando o comando REALMENTE precisa ler.
      unless ($ENV{RUN_WITH_STDIN}) {
          open(STDIN, "<", "/dev/null") or die "sem stdin: $!";
      }
      exec @ARGV or exit 127;
  }
  # Mata a ÁRVORE inteira, não só o grupo. Grupo não basta: se um wrapper
  # intermediário fizer `set -m` (job control), o neto vira líder do PRÓPRIO
  # grupo e escapa do `kill -PID`. Foi o que deixou 9 processos `opencode run`
  # órfãos por até 16min em 2026-07-25, apesar do incidente incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md.
  my $matar_arvore;
  $matar_arvore = sub {
      my $alvo = shift;
      # descendentes diretos via pgrep -P, recursivamente (filhos antes do pai)
      my @filhos = split /\s+/, `pgrep -P $alvo 2>/dev/null` // "";
      for my $f (@filhos) { $matar_arvore->($f) if $f =~ /^\d+$/ }
      kill "KILL", -$alvo;   # grupo, se ele for líder
      kill "KILL", $alvo;    # e o processo em si
  };
  local $SIG{ALRM} = sub {
      $matar_arvore->($pid);
      waitpid($pid, 0);
      print STDERR "\n⏱️  TIMEOUT: comando excedeu ${secs}s — árvore de processos morta.\n";
      exit 124;
  };
  alarm $secs;
  waitpid($pid, 0);
  alarm 0;
  exit($? >> 8);
' "$SECS" "$@"
