# Entradas `tuned/` no model-registry.json (formato — S10/E2-D2)

> Formato FROZEN pela ESCALADA-2 (DECISIONS-E2, E2-D2). **Nenhuma entrada
> existe hoje** — a primeira entrada real é trabalho de GPU, depois do
> "sobe" do dono. Este doc existe para o formato não ser inventado na hora.

```json
{
  "id": "tuned/<dominio>-<base>",
  "tuned_from": "<id do modelo base no registry>",
  "measured_delta": {
    "report": ".dispatch/tuned-measure/<stamp>-<tuned>.json",
    "run_ids": ["<10 run_ids do bin/tuned-measure.sh: 5 base + 5 tuned>"],
    "tasks": 5,
    "protocol": "mesma spec, mesmo modo, só model_ref difere"
  }
}
```

## O gate do claim (E2-D1) — as três pernas, todas obrigatórias

1. Entrada no registry com **evidência de serving** (o modelo roda num
   endpoint seu — não vale só o id).
2. **Before/after em 5 specs reais** (E2-D1: N=5) — as duas runs de cada
   spec no ledger, com protocolo e seed idênticos (`bin/tuned-measure.sh`
   produz exatamente isso).
3. Oráculo da S10 verde (`bash tests/test-tuned-measure.sh`).

Até as três existirem juntas, a palavra "fine-tune" **não aparece em
nenhuma copy** — fica como NEXT/gated.
