# Quantos usuários do Steam (set/2026) conseguem rodar um modelo de N bilhões de parâmetros a ~4 bits.
# Fonte: https://store.steampowered.com/hwsurvey (Sep 2026). "Other" (1.26%) e <=4 GB tratados como sem condição.
VRAM = {0.5:2.60,1:1.44,2:3.69,3:1.20,4:5.13,6:5.12,8:26.71,10:1.91,11:0.83,12:13.06,16:27.21,20:1.39,22:1.04,24:5.50,32:1.41,64:0.50}
RAM  = {8:6.47,16:37.82,32:42.22,64:3.71,96:0.53}   # ">64 GB" contado como 96
GB_POR_B = 22.1/35      # Qwen3.6-35B-A3B UD-Q4_K_M = 22.1 GB (InsiderLLM) -> 0.63 GB por bilhão
def arquivo(b): return GB_POR_B*b
def so_gpu(b, ctx=1.5, gbb=None):   return sum(p for v,p in VRAM.items() if v >= (gbb or GB_POR_B)*b+ctx)
def hibrido(b, so=6):   # GPU+RAM somadas cabem o arquivo + 6 GB (SO e contexto); supõe independência VRAM x RAM
    return sum(pv*pr/100 for v,pv in VRAM.items() if v>=6 for r,pr in RAM.items() if v+r >= arquivo(b)+so)
GB3 = 17/35  # Unsloth: 3-bit precisa ~17 GB no 35B-A3B
print("tamanho | arquivo 4-bit | só GPU 4-bit | só GPU 3-bit | GPU+RAM 4-bit (offload, MoE)")
for b in (120,60,35,20):
    print(f"{b}B | {arquivo(b):.0f} GB | {so_gpu(b):.2f}% | {so_gpu(b,0.5,GB3):.2f}% | {hibrido(b):.2f}%")
