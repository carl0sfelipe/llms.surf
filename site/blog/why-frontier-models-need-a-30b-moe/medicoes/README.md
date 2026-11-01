# Quem consegue rodar cada tamanho de modelo (31/10/2026)

## pool.py — fração dos usuários do Steam (setembro/2026)
Fonte: Steam Hardware & Software Survey, setembro de 2026 (tabelas de VRAM e RAM do sistema).
Hipóteses: arquivo 4-bit = 0,63 GB por bilhão de parâmetros (Qwen3.6-35B-A3B UD-Q4_K_M = 22,1 GB);
3-bit = 17 GB para 35B (Unsloth); contexto curto (+1,5 GB). "GPU+RAM" supõe VRAM e RAM independentes
e só vale para MoE com poucos parâmetros ativos (denso de 60B com offload fica lento demais).
Steam mede gamers, não desenvolvedores: use como proxy da base de máquinas, não como contagem de pesquisadores.

## hf_derivados.py — PENDENTE, rodar no rig
O container não acessa a API do Hugging Face. Conta quantizações, fine-tunes, adapters e merges por modelo-base,
comparando tamanhos lançados juntos. Resultado vai em `derivados.txt`.
