# Rodar no rig (precisa acesso ao huggingface.co). Conta derivados por modelo-base no Hugging Face.
# Compara tamanhos lançados JUNTOS (mesma família, mesma data), para não confundir tempo com tamanho.
import json, sys, urllib.request
PARES = [  # (família, repo)
  ("gpt-oss (ago/2025)", "openai/gpt-oss-20b"), ("gpt-oss (ago/2025)", "openai/gpt-oss-120b"),
  ("Qwen3.5 (fev/2026)", "Qwen/Qwen3.5-27B"), ("Qwen3.5 (fev/2026)", "Qwen/Qwen3.5-35B-A3B"),
  ("Qwen3.5 (fev/2026)", "Qwen/Qwen3.5-122B-A10B"), ("Qwen3.5 (fev/2026)", "Qwen/Qwen3.5-397B-A17B"),
  ("Qwen3.6 (abr/2026)", "Qwen/Qwen3.6-27B"), ("Qwen3.6 (abr/2026)", "Qwen/Qwen3.6-35B-A3B"),
  ("Qwen3.8 (ago/2026)", "Qwen/Qwen3.8-27B"), ("Qwen3.8 (ago/2026)", "Qwen/Qwen3.8-Flash-Next"),
  ("GLM (jan/2026)", "zai-org/GLM-4.7-Flash"), ("GLM (dez/2025)", "zai-org/GLM-4.7"),
]
def conta(rel, repo):
    n, url = 0, f"https://huggingface.co/api/models?filter=base_model:{rel}:{repo}&limit=1000"
    while url:
        with urllib.request.urlopen(url, timeout=60) as r:
            n += len(json.load(r)); link = r.headers.get("Link", "")
        url = link.split(";")[0].strip("<> ") if 'rel="next"' in link else None
    return n
print("família | repo | quantized | finetune | adapter | merge | total")
for fam, repo in PARES:
    try:
        c = [conta(k, repo) for k in ("quantized", "finetune", "adapter", "merge")]
        print(f"{fam} | {repo} | " + " | ".join(map(str, c)) + f" | {sum(c)}")
    except Exception as e:
        print(f"{fam} | {repo} | erro: {e}", file=sys.stderr)
