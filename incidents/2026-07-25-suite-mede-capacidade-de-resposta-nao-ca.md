---
id: 2026-07-25-suite-mede-capacidade-de-resposta-nao-ca
titulo: Suíte mede capacidade de resposta, não capacidade agêntica
data: 2026-07-25
recorrivel: sim
interage_com: 20 (medição precisa registrar em QUE CONDIÇÕES foi feita, não só quem serviu); 28 (o sandbox isolou o modelo do repo — e escondeu que alguns adapters não alcançam o repo de jeito nenhum); 31 (exit 0 não é prova: aqui o modelo respondeu bem e não fez o trabalho). RISCO: adicionar campo de capacidade sem medir vira declaração não verificada, o mesmo erro do accuracy herdado de spec.
regra: 33
status: promovido
---

# Suíte mede capacidade de resposta, não capacidade agêntica

## Sintoma

`gemma-4-12b-it-Q6_K` (local, llama.cpp) tirou **8/8** na suíte v2 — nota igual aos melhores remotos. Com base nisso, aloquei a ele três despachos reais (D01, D08, D12).

O primeiro voltou com:

> "Não tenho acesso aos arquivos locais do seu computador para ler o ledger.jsonl"

## Causa

O adapter `llamacpp` é uma chamada HTTP de chat completion pura. **Não tem laço de ferramentas**: o modelo não lê arquivo, não roda comando, não navega o repositório.

A suíte v2 não detectou isso porque **suas 8 tarefas são prompts autocontidos** — instrução literal, aritmética, saída de código dada no enunciado, JSON, bulk a partir do prompt, refinamento de um trecho colado, agulha em texto colado, recusa. Nenhuma exige alcançar o mundo externo.

Ou seja, a suíte mede **capacidade de resposta**. Trabalho real de dispatch exige **capacidade agêntica** — e as duas não se implicam.

Eu li "8/8, qualidade equivalente" como "pode fazer o mesmo trabalho". Não pode. A nota estava certa; a inferência era minha.

## Correção aplicada

- `adapters/llamacpp/capabilities.env`: campo `TOOLS=0` explícito, com o motivo.
- `adapters/*/capabilities.env` dos demais: `TOOLS=1` onde há laço de ferramentas.
- `RUNBOOK-dispatch.md`: coluna/nota separando "responde bem" de "opera no repositório".
- `DESPACHOS-transformacao.md`: D01, D08 e D12 reatribuídos; camada local restrita a tarefas de texto puro com contexto no prompt.

**Não corrigido de propósito:** a suíte continua sem tarefa agêntica. Acrescentar uma exigiria que o harness desse ferramentas ao modelo dentro do sandbox — e o sandbox existe porque modelo com ferramentas editou a própria suíte (regra 28). Resolver isso é projeto, não ajuste.

## Pode acontecer de novo?

**Sim, e para qualquer adapter novo.** Nada no framework obriga a declarar se um runner tem ferramentas. Sem o campo `TOOLS`, a próxima integração repete a inferência errada — e a nota alta continua parecendo permissão para qualquer trabalho.
