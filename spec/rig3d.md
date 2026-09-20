# PROMPT PARA O AGENTE IMPLEMENTADOR

Você vai construir **rig3d** — uma ferramenta que compõe hardware em 3D para
**ver e projetar rigs e datacenters** (GPUs, placas-mãe, PSUs, racks, sala),
calculando orçamentos reais de **energia, térmica, espaço (U), peso, PCIe e
custo**, e gerando um modelo 3D navegável.

Regras de ouro (estilo llms.surf): **nada passa na sua palavra.** Toda entrega
é provada por um **oráculo mecânico** — um comando que FALHA antes do trabalho
existir e PASSA depois, lendo artefatos no disco. Número/dimensão/potência que
você não tiver de datasheet é `[TO MEASURE]`, **nunca chutado**. Um número
inventado é bug crítico.

Stack decidida (não troque sem declarar): **Blender headless (bpy)** como
núcleo geométrico + oráculo (roda em CI, sem GUI, é automatizável e testável);
**glTF/.glb** como saída interoperável; **three.js / <model-viewer>** como
visualizador web interativo (o "ver e projetar" sem peso de engine). **Unreal**
é camada OPCIONAL de apresentação imersiva (importa o .glb/USD) — NÃO é o
núcleo, porque headless/oráculo em Unreal é frágil.

---

# S1 — rig3d: compositor 3D de hardware com orçamento fail-closed

Mode: hand or capable-agent, **oracle frozen first** · file ceiling: ~14 files
· Order: schema+budget antes do Blender; Blender antes do viewer.
Purpose: transformar "montar um rig/datacenter" numa MÁQUINA que valida
fisicamente (cabe? aguenta a energia? dissipa o calor?) e mostra em 3D — não
num desenho bonito sem lastro.

## Verified data (dados verificados)

Use SÓ o que está aqui como fato de partida; o resto vem de datasheet do
componente (campo `source` obrigatório) ou é `[TO MEASURE]`.

- **Cluster semente (real, do dono):** 8× NVIDIA RTX 3090 (24 GB) distribuídas
  em **2 máquinas dual-GPU** + **1 rig com duas placas X99, cada uma dual-GPU**
  (2+2 = 4). Medido: ~79 tok/s/GPU (Qwen3-27B Q3.5); consumo de placa a
  confirmar (TDP de referência RTX 3090 = 350 W — marque `source`).
- **Unidade de rack:** 1U = 44,45 mm. Rack padrão 42U ≈ 600 × 1200 × 2000 mm.
- **RTX 3090 (referência a validar por SKU):** ~313 × 138 mm, 2.2–3 slots de
  espessura; slot PCIe = 20,32 mm de passo. Marque `source` por SKU real.
- **Energia (âncora de projeto, não de componente):** tarifa IA Paraguai
  US$0,044/kWh (para o cálculo de custo operacional, opcional).
- Conversão de unidade: modele tudo em **milímetros** nos dados; converta para
  **metros** só na hora de criar a malha no Blender (bpy usa metros).

Do not invent (nao invente) dimensões, potências, pesos, preços, nomes de
campo ou de componente além dos listados. O que for indecidível é
`[TO MEASURE]`/`[TO DECIDE]`, jamais um número plausível. NUNCA gere malha de
um componente cujas dimensões você não tem — o build deve **halt loud**.

## Work

1. **`components/*.json` + `src/rig3d/schema.py`** — biblioteca de componentes
   e validação (pydantic). Tipos: `gpu`, `mainboard`, `psu`, `rack`, `node`
   (chassi), `room`, `crac`. Campos mínimos por componente:
   `id, type, dims_mm:[x,y,z], weight_kg, power_w, heat_btu?, slots?,
   pcie_lanes?, price_usd?, source` (URL/datasheet ou `[TO MEASURE]`).
   Semente obrigatória: `rtx-3090`, `x99-dual`, um `psu`, um `node-dual`,
   `rack-42u`.
2. **`scenes/*.json`** — layout: lista de instâncias com
   `component_id, position_mm:[x,y,z], rotation_deg`, aninhamento
   (gpu→node→rack→room). Semente: `examples/vector-cde-8x3090.json`
   reproduzindo o cluster real (2 nós dual + 1 rig X99 com 2 boards dual).
3. **`src/rig3d/budget.py`** — motor de orçamento puro (sem Blender), com
   testes: soma **potência total**, calcula **folga da PSU**
   (`psu_w - draw_w`, deve ser ≥ margem configurável, default 20%), **carga
   térmica** (BTU/h ≈ W × 3,412), **U ocupado vs U do rack**, **peso vs limite
   do rack**, **lanes PCIe vs disponível**, **custo total**. Retorna
   `valid: bool` + lista de `violations`. Fail-closed: violação ⇒ `valid=false`.
4. **`src/rig3d/build_blender.py`** — recebe um scene.json e produz, via bpy
   **headless**: `out/scene.glb` (malhas paramétricas: caixas escaladas às
   dims reais, cor por tipo), `out/render.png` (câmera isométrica) e chama o
   `report.py`. Se algum componente do scene não tiver dims → **erro, exit≠0**
   (não desenhe caixa genérica silenciosa).
5. **`src/rig3d/report.py` + `cli.py`** — `report.json` com todos os números
   do budget + contagem de objetos 3D + hash do glb. CLI:
   `rig3d build <scene.json> --out out/`.
6. **`viewer/index.html`** — carrega `out/scene.glb` com `<model-viewer>` (ou
   three.js) + overlay com os números do `report.json` (energia, térmica, U,
   peso, custo, violations). Mobile-first. É o "ver e projetar".
7. **Escala datacenter:** a mesma engine com `room` + N `rack` + `crac`;
   budget calcula **PUE estimado**, carga térmica por corredor e área de piso.
   Exemplo `examples/datacenter-8-racks.json`.
8. **(Opcional) Unreal/USD:** exportar `out/scene.usd` e um README de import no
   Unreal (Datasmith/USD) para walkthrough imersivo — sem entrar no oráculo.

## Do not touch

Não commite malhas CAD proprietárias de terceiros. Não invente SKUs. Não
troque a stack (Blender núcleo) sem declarar exceção. Sem chave de API, sem
rede no oráculo.

VERIFICACAO: test -f examples/vector-cde-8x3090.json && command -v blender

(Antes do trabalho existir, o oráculo abaixo FALHA pelo motivo certo: sem
`out/scene.glb` e sem `out/report.json`. Isso é o estado correto de partida.)

## Barra

Referência nomeada: o cenário semente `vector-cde-8x3090` tem de renderizar as
8× 3090 nos 3 nós reais e o `report.json` tem de bater a soma de potência com a
conta feita à mão dos componentes (mesma fonte de dims/W). Um cenário que
estoura a PSU (negativo) DEVE ser reprovado (`valid=false`).

## Oraculo

- comando:
  ```
  bash tests/test_oracle.sh
  ```
  onde `tests/test_oracle.sh` faz, e só passa (exit 0) se TUDO valer:
  1. `pytest tests/test_budget.py -q` (engine de orçamento correta, incl.
     caso PSU insuficiente ⇒ `valid=false`).
  2. `blender --background --python src/rig3d/build_blender.py -- examples/vector-cde-8x3090.json out/`
     gera `out/scene.glb` (tamanho > 0) e `out/report.json`.
  3. `python -c "import json,sys; r=json.load(open('out/report.json')); \
     assert r['valid'] is True; \
     assert r['object_count']>=8; \
     assert all(k in r for k in ['total_power_w','psu_headroom_w','thermal_btu','rack_u_used','weight_kg','cost_usd']); \
     print('scene ok', r['total_power_w'])"`
  4. **Negativo (fail-closed):** rodar o build num
     `examples/_overpower.json` (PSU pequena de propósito) e exigir
     `valid=false` no report OU exit≠0 do build — se passar como válido, o
     oráculo REPROVA.

Exit 0 só depois que: a engine está provada (incl. o negativo), o .glb e o
report nascem no disco a partir do cenário real das 8× 3090, e um layout
fisicamente impossível é recusado. Nenhum número é aceito na palavra do agente
— o report é lido do disco.

## Entregáveis (estrutura)

```
rig3d/
  components/{rtx-3090.json,x99-dual.json,psu.json,node-dual.json,rack-42u.json}
  scenes/  examples/{vector-cde-8x3090.json,datacenter-8-racks.json,_overpower.json}
  src/rig3d/{schema.py,budget.py,build_blender.py,report.py,cli.py}
  viewer/index.html
  tests/{test_budget.py,test_oracle.sh}
  README.md   (como rodar: pip install, blender headless, abrir o viewer)
```

## Notas para o implementador (não são fatos do projeto)

- Blender headless: `blender --background --python script.py -- args`. Exporte
  glb com `bpy.ops.export_scene.gltf(filepath=..., export_format='GLB')`.
- Malha paramétrica MVP = `bpy.ops.mesh.primitive_cube_add` escalado a
  `dims_mm/1000/2` + material por tipo (gpu=verde, board=ciano, psu=âmbar,
  rack=cinza). Depois dá para trocar por glTF real por componente (campo
  `mesh` opcional no JSON).
- Snap/colisão: comece com posições explícitas em mm; evolua para um packer
  (empilhar GPUs por passo de slot, nós por U no rack).
- Viewer: `<model-viewer src="scene.glb" camera-controls ar>` já entrega
  órbita/zoom no navegador e no celular; o overlay lê `report.json` via fetch.
```
