---
status: aberto
---
# gui-tunnel: link público dá 404 e depois "conexão recusada"

Dono tentou abrir a GUI de outro PC pela internet (`oracfit gui-tunnel`) e deu erro.

1. O quick tunnel (`cloudflared tunnel --url …`) herda `~/.cloudflared/config.yml` de outro
   túnel da máquina; o ingress de lá termina em `http_status:404` → todo pedido 404.
2. Ao matar esse cloudflared para corrigir, o `oracfit-gui-tunnel.sh` derrubou a GUI junto;
   o túnel novo apontava para uma porta vazia ("connection refused").

## Proposta do lado do serviço
- `oracfit-gui-tunnel.sh` roda o quick tunnel com `--config <arquivo vazio temporário>`
  (nunca herda config de túnel nomeado).
- Smoke depois de subir: `curl <url>/login` tem que dar 200; senão imprime o motivo em
  português ("o cloudflared está usando a config de outro túnel") em vez de só a URL.
- GUI e túnel com ciclo de vida independente; se um cair, o script avisa e sobe de novo.
- Opcional: hostname fixo (`gui.<zona>`) + Cloudflare Access, para a URL não mudar.
