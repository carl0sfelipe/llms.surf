---
title: "Why frontier models need a ~30B MoE sibling"
description: "Shrinking a model from 120B to 35B takes it from ~1% of PCs to over half. Why that recruits more minds than any lab can hire, told through the repos that made Qwen3.6-35B-A3B run on DDR4 and 12 GB cards."
date: 2026-10-31
slug: why-frontier-models-need-a-30b-moe
lang: en
author: Carlos
tags:
  - moe
  - local-llm
  - qwen
  - glm
  - feedback
image: /blog/why-frontier-models-need-a-30b-moe/img/hero.png
canonical: https://llms.surf/blog/why-frontier-models-need-a-30b-moe
---

![Share of Steam PCs that can run each model size](/blog/why-frontier-models-need-a-30b-moe/img/hero.svg)

A frontier lab can hire a few hundred great engineers. A model that runs on a 16 GB graphics card recruits everyone who owns one, and in Steam's September 2026 hardware survey that was the most common amount of video memory, owned by 27% of users. Essentially none can hold a 120B model on the card, even at 4 bits. The best argument for shipping a small mixture-of-experts (MoE) model is not the model itself. It is what thousands of curious people do with it when they can run it at home, and how much of that work flows back into the frontier.

The evidence is already in. Qwen3.6-35B-A3B came out in April 2026. Six months later, it is still the newest open MoE of its size from either Qwen or Zhipu, and the community has made it run on DDR4 desktops, eight-year-old datacenter cards and thin laptops. They did it with forks, quantization formats and kernels that nobody at Alibaba wrote.

## The rumor, and the empty slot

Today a post on X claims Zhipu's GLM-5.5 is "well into post-training" and that the lab "seems to have been training internal 32B, 122B" models ([AGTP on X](https://x.com/AGTPinsights/status/2116516321479275000)). OpenCode's directory already has a `glm-5.5-flash` page, but every spec reads "Unknown" and it has served zero tokens ([OpenCode](https://opencode.ai/data/zhipu/glm-5-5-flash)). GLM-5.5 rumors have missed twice this year ([CellCog](https://cellcog.ai/blog/glm-5-5-release-date/)). Treat it as a hypothesis.

Why people want it to be true is the interesting part. Zhipu's "Flash" used to be the consumer model: GLM-4.7-Flash, in January, was 30B total and 3B active ([Gigazine](https://gigazine.net/gsc_news/en/20260120-zai-glm-4-7-flash)). GLM-5.3-Flash, in August, is 320B total and 18B active ([CellCog](https://cellcog.ai/blog/glm-5-5-release-date/)), roughly 160 GB at 4 bits. Qwen's August open releases were a 2.4T flagship, a 27B dense model and a 125B MoE ([Wikipedia](https://en.wikipedia.org/wiki/Qwen); [explainx](https://explainx.ai/blog/qwen3-8-flash-next-125b-moe-release-august-2026)). Qwen 3.7 never shipped open weights ([Codersera](https://codersera.com/blog/qwen-3-7-release-date-whats-new-2026/)).

Both labs moved up. The ~30B MoE slot has been empty since April.

## The participation curve: who can run 120B, 60B and 35B

The size of a model decides how many people can work on it. You can estimate that from the Steam Hardware Survey, which publishes how much video memory and system RAM its users have. In September 2026, 16 GB was the most common amount of VRAM (27.21% of users), followed by 8 GB (26.71%) and 12 GB (13.06%). Every tier of 24 GB or more added up to 7.41%; 32 GB and up, 1.91% ([Steam, September 2026](https://store.steampowered.com/hwsurvey/Steam-Hardware-Software-Survey-Welcome-to-Steam)).

A 4-bit file takes about 0.63 GB per billion parameters (Qwen3.6-35B-A3B's Q4 file is 22.1 GB, [InsiderLLM](https://insiderllm.com/guides/qwen-3-6-local-ai-guide/)). Put the two together:

| Model size | 4-bit file | Fits entirely in the GPU | Runs with experts in system RAM (MoE) |
|---|---:|---:|---:|
| ~120B | ~76 GB | 0% | ~1% |
| ~60B | ~38 GB | 0.5% | ~26% |
| ~35B | ~22 GB | 7.4% | ~54% |
| ~20B | ~13 GB | 37% | ~75% |

Share of Steam users in September 2026. "Runs with experts in RAM" counts machines where GPU memory plus system RAM holds the file with 6 GB to spare, assuming VRAM and RAM are independent; it only applies to MoE models with few active parameters ([our calculation and assumptions](/blog/why-frontier-models-need-a-30b-moe/medicoes/README.md)).

![Who can run each model size](/blog/why-frontier-models-need-a-30b-moe/img/pool.svg)

Read the table from top to bottom. Halving a model from 120B to 60B moves it from about 1% of machines to about a quarter, but almost nobody can hold it on the GPU alone. Halving again to ~35B doubles the hybrid pool to more than half of all machines and makes it fully GPU-resident for 7%. At ~20B, more than a third of users fit it entirely on the card. The first halving multiplies the pool about 25 times. The second roughly doubles it again and is the first size a meaningful share of people can run entirely on the card.

Steam measures gamers, not researchers, so treat it as a map of the hardware people own, not a headcount. But researchers, students and hobbyists buy the same cards. The repos below were built on exactly those tiers: 12 GB, 16 GB and 24 GB cards, DDR4 desktops and laptops.

Why MoE matters here: Qwen3.6-35B-A3B stores 35B parameters but reads about 3B per token, routing through 8 of its 256 experts plus a shared one ([InsiderLLM](https://insiderllm.com/guides/qwen-3-6-local-ai-guide/)). Generation is limited by memory bandwidth, so when the experts sit in slow system RAM, each token only pulls a small slice of them. A dense 60B with the same offload reads every weight for every token and slows to a crawl. That is why the last column only exists for MoE models.

![256 experts, 9 read per token](/blog/why-frontier-models-need-a-30b-moe/img/moe.svg)

## What the download data says

The Steam numbers describe who could take part. Hugging Face's own data shows who actually does, and it points the same way.

Small models get used. Among models that declare a parameter count, those under 1B take 83% of all-time downloads on the Hub, and models above 100B take 1%. In 2026 so far, only about 3% of downloads went to models above 70B ([Hugging Face, Summer 2026](https://huggingface.co/blog/state-of-open-models-summer-2026)). The ATOM Report, which tracks open language models specifically, finds the same shape: models under 10B account for about 75% of tracked downloads, and the 7–9B bucket alone takes 33.8% ([ATOM Report](https://arxiv.org/html/2604.07190)).

The labs that ship mostly giant models feel it. Hugging Face measured how much of each lab's 2026 downloads came from models above 70B:

![Downloads above 70B by lab](/blog/why-frontier-models-need-a-30b-moe/img/lab-size.svg)

Moonshot, which publishes only frontier-size models, had 37 million downloads in 2026. Qwen, which publishes everything from 0.6B up, had 2,045 million, about 55 times more ([Hugging Face, Summer 2026](https://huggingface.co/blog/state-of-open-models-summer-2026)).

Downloads are only half the story. The other half is what people build on top:

![Derivative models by family](/blog/why-frontier-models-need-a-30b-moe/img/derivatives.svg)

Qwen's share of new derivative models on the Hub went from 1% in January 2024 to 69% in February 2026, according to the ATOM Report. Its family covers every size a home machine can hold, and it ships under Apache 2.0.

The work behind those derivatives is overwhelmingly done outside the lab. This is the clearest single number in the whole debate:

![28,531 GGUF conversions vs 54 by Qwen](/blog/why-frontier-models-need-a-30b-moe/img/gguf.svg)

And the format people use to run models at home is the fastest-growing thing on the Hub:

![Growth by format](/blog/why-frontier-models-need-a-30b-moe/img/formats.svg)

The same community keeps growing. r/LocalLLaMA, where many of the techniques in this post first appeared, has about 861,000 members and added about 307,000 in the last year ([GummySearch](https://gummysearch.com/r/LocalLLaMA/)).

## What people built, one idea at a time

Below are the inventions, each with the person or small team behind it. None of them came from the lab that trained the model.

### One flag that turned a 12 GB card into a 35B machine

llama.cpp added `--n-cpu-moe N`, which keeps the MoE weights of the first N layers on the CPU ([llama.cpp source](https://github.com/ggml-org/llama.cpp/blob/master/common/arg.cpp)). A Habr author with an RTX 4070 (12 GB), 32 GB of **DDR4** and LM Studio moved all 40 MoE layers to the CPU. VRAM use dropped to 6.2 GB, the 22 GB model ran with a 65K context, and generation hit 42 tok/s ([Habr, April 2026](https://habr.com/en/articles/1026482/)). Before the flag, the model did not fit at all.

### A fork by the person who co-wrote the quants everyone uses

The k-quants that most GGUF files use were added to llama.cpp in pull request #1684, with Iwan Kawrakow credited as co-author ([commit](https://app.semanticdiff.com/gh/ggml-org/llama.cpp/commit/99009e72f8072fa552eb02efee436be596c71cdd)). He now maintains his own fork, ik_llama.cpp, focused on CPU and hybrid CPU/GPU inference, fused MoE operations and new quant types. It has about 3,350 stars ([SourcePulse](https://www.sourcepulse.org/projects/1843811)).

On r/LocalLLaMA, one user ran the 35B-A3B on an RTX 4070 Super with **12 GB** and got 110 tok/s with ik_llama.cpp versus 89.8 with mainline llama.cpp, a 23% gain. In the same thread, someone with a Ryzen 3700X, 32 GB of RAM and an **8 GB** GPU reported 25–55 tok/s ([r/LocalLLaMA](https://reddit.sentinel-team.org/posts/1tjh7az/snapshots/2026-05-30T00%3A45%3A07.677242Z)). Others could not reproduce the gain on their machines, and one person on a 5060 Ti found mainline faster. That disagreement is the process working: claims get tested by strangers within hours.

### A quantizer that picks a format for every tensor

ByteShape's quants choose a datatype per tensor instead of one level for the whole model. A developer benchmark shared on r/LocalLLaMA reported the full 35B-A3B fitting in a **6 GB** laptop GPU without CPU offload, about 30% faster than an Unsloth IQ quant. The test measured speed and size only, not quality ([AI Weekly](https://aiweekly.co/alerts/byteshape-qwen3-quant-beats-unsloth-iq-by-30-on-6gb-vram)). The thread above used a ByteShape IQ4_XS file at 4.19 bits per weight.

### A server tuned for one graphics card

Lucebox Hub, led by Sandro Puppo, hand-optimizes inference for specific consumer GPUs instead of trying to run everywhere. It has about 2,100 stars ([ecosyste.ms](https://awesome.ecosyste.ms/projects/github.com%2FLuce-Org%2Flucebox-hub)). On an RTX 3090, its port of z-lab's DFlash speculative decoding averages 129.5 tok/s on HumanEval with the Qwen 27B models ([Ranil Mukesh](https://ranilmukesh.github.io/blog/ai-inference-bottleneck/)), and its prefill work reports about 10x faster time-to-first-token at 128K context than llama.cpp. That is a 2020 card doing long-context work.

### Faster decoding without touching the weights

z-lab trained a DFlash drafter for this exact model; it proposes blocks of tokens in parallel from the target model's hidden states and reports 2.89x to 3.61x throughput on a B200 ([dev.co](https://dev.co/ai/llms/qwen3-6-35b-a3b-dflash)). Intel engineers ported it to a Core Ultra laptop and went from 41 to 89.8 tok/s on code, but only 1.3x on chat ([Hugging Face](https://huggingface.co/blog/ofirzaf/intel-dflash-ptl)). With multi-token prediction instead, one user posted 249 tok/s on a 24 GB laptop RTX 5090 at 3 bits, 3.4 times the dense 27B on the same machine ([r/LocalLLaMA](https://reddit.sentinel-team.org/posts/1tlfp5s/snapshots/2026-05-30T00%3A45%3A07.677242Z)).

### Old and odd hardware

The same threads are full of machines no lab would test on. An AMD MI50, a 2018 datacenter card, was reported at 75 tok/s on a 22 GB 4-bit quant. An RTX 2060 ran the previous 35B-A3B at 16–18 tok/s ([r/LocalLLaMA](https://reddit.sentinel-team.org/posts/1ruew2g/snapshots/2026-03-16T20%3A46%3A16.316967Z)). A Radeon 780M integrated GPU reached about 20 tok/s ([InsiderLLM](https://insiderllm.com/guides/qwen-3-6-local-ai-guide/)). These are forum reports, not lab benchmarks, but they map where the model is usable.

### Cutting experts, carefully

Feng Wang wanted the model on one RTX 5090, kept 183 of its 256 experts with REAP pruning, and wrote up what worked and what failed. His main lesson: "calibration composition matters more than any algorithmic tweak I could have made to the pruner itself." He also found that fine-tuning on frozen 4-bit experts made every benchmark worse ([Feng Wang](https://fengwang.github.io/posts/qwen-pruning-rtx5090/)).

### Two university engines built for hybrid machines

Academic groups attacked the same problem. Tsinghua's KTransformers splits MoE inference between CPU and GPU and has about 19,600 stars ([Trendshift](https://trendshift.io/repositories/14292)). SJTU's PowerInfer keeps frequently activated "hot" neurons on the GPU and computes "cold" ones on the CPU, reporting up to 11x over llama.cpp on an RTX 4090; it has about 9,850 stars ([SourcePulse](https://www.sourcepulse.org/projects/981103)).

### Science that measures the hacks

Then researchers measure what hobbyists invented. A Sony AI paper tested combined compression on ten MoE models. On Qwen3.6-35B-A3B, Q4_K_M quantization alone matched BF16 accuracy (0.8263 vs 0.8262), and pruning plus quantization cut memory from 69.38 GB to 16.04 GB at 0.8191, the smallest quality loss of the models compared ([arXiv 2608.21693](https://arxiv.org/pdf/2608.21693)).

## How this flows back to the frontier

The best proof that community work reaches frontier models is a story from 2023.

A hobbyist known as kaiokendev wrote a blog post about stretching LLaMA's context by interpolating positions. A Reddit user, bloc97, posted "NTK-Aware Scaled RoPE" on r/LocalLLaMA, extending context to 8K+ "without any fine-tuning". Another user, emozilla, posted a dynamic version there too. When the YaRN paper formalized these methods, it cited the Reddit posts directly: NTK-aware interpolation "was developed in (bloc97, 2023a)", and dynamic scaling "first appeared in public as a reddit post" ([YaRN, arXiv 2309.00071](https://arxiv.org/pdf/2309.00071)).

Today YaRN is how Qwen models stretch their context. vLLM's documentation shows it on a Qwen3 model, with a factor of 4 over a native 32,768 tokens ([vLLM docs](https://docs.vllm.ai/en/stable/features/context_extension/)). DeepSeek-V3 uses YaRN as well, to extend its context from 4K to 128K tokens ([DeepSeek-V3 report](https://arxiv.org/html/2412.19437)). A technique that started on a forum for people running models at home now ships inside frontier families.

YaRN is not a one-off. Here are six ideas, each traced to the person or tiny team who started it and to where it ended up:

| Idea | Started by | Where it ended up |
|---|---|---|
| NTK / dynamic RoPE scaling → YaRN | bloc97, emozilla, kaiokendev (Reddit, blog) | Qwen3 context extension, DeepSeek-V3 4K→128K |
| Muon optimizer | Keller Jordan, NanoGPT speedrun (~$8 runs) | Kimi K2 (1T, MuonClip), GLM-4.5 |
| Min-p sampling | independent researcher, "a passion project" | transformers, vLLM, SGLang, llama.cpp, Ollama |
| Prompt lookup decoding | Apoorv Saxena, one repo | `prompt_lookup_num_tokens` in transformers |
| Gemma / Phi-4 bug fixes | Daniel and Michael Han (Unsloth) | transformers 4.38.2, Phi-4 tokenizer fix |
| REAP expert pruning on small MoEs | tested on Qwen3-30B-A3B first | Qwen3-Coder-480B, Kimi-K2 (1T) |

A few of these deserve a closer look, because the details matter.

**Muon** is the strongest case. Keller Jordan developed it in the NanoGPT speedrun, a public race to train a small GPT as fast as possible, keeping each attempt to about $8 of rented GPU time ([36Kr](https://eu.36kr.com/en/p/3698501921320835)). He published it as a blog post and said he would not write a paper. Less than a year later, Moonshot trained Kimi K2, a 1-trillion-parameter model, on 15.5 trillion tokens with MuonClip, an extension of Muon, reporting "zero loss spike" ([Kimi K2 report](https://ar5iv.labs.arxiv.org/html/2507.20534)). Zhipu's GLM-4.5 technical report states that "the Muon optimizer is adopted for scalable training" ([GLM-4.5](https://www.emergentmind.com/papers/2508.06471)). To be precise: Muon was developed on rented datacenter GPUs, not a home card. What it shares with the others is the scale of the experiment, an individual's budget and a small model.

**Min-p sampling** began, in its authors' words, as "a passion project" by an independent researcher, and the paper says it "does not belong to any institution." By May 2025 it was built into transformers, vLLM, SGLang, llama.cpp and Ollama, frameworks with more than 668,000 GitHub stars between them ([min-p paper](https://arxiv.org/pdf/2407.01082v5)).

**Prompt lookup decoding** was a small repository by Apoorv Saxena: when the answer repeats parts of the prompt, as in summaries, copy candidate tokens from the prompt and let the model verify them. He reported about a 2.4x speed-up ([Simon Willison](https://www.simonwillison.net/2024/Jan/23/prompt-lookup-decoding)). It is now one argument in Hugging Face transformers, `prompt_lookup_num_tokens` ([transformers docs](https://huggingface.co/docs/transformers/en/assisted_decoding)).

**Bug reports count too.** In March 2024, Daniel and Michael Han of Unsloth found loss, precision and casting problems in Google's Gemma; fixes for the GELU and RoPE issues landed in transformers 4.38.2 ([Unsloth](https://www.plushcap.com/content/unsloth/blog/unsloth-fixing-all-gemma-bugs)). In January 2025 they found a tokenizer bug in Microsoft's Phi-4 ([Simon Willison](https://feeds.simonwillison.net/2025/Jan/11/phi-4-bug-fixes/)). These are exactly the kind of findings an incident feed, described below, would route to the lab directly.

The same thing happens with techniques that start on small models and then get applied to giant ones. Cerebras' REAP expert pruning was evaluated on Qwen3-30B-A3B and GLM-4.5-Air, and then on Qwen3-Coder-480B and the 1-trillion-parameter Kimi-K2. At 50% of the experts removed, the 480B coder kept 97.6% of its non-agentic coding ability ([Cerebras](https://www.cerebras.ai/blog/reap)). The DFlash drafter trained for the 35B-A3B was benchmarked on a B200 datacenter GPU as well as on laptops. And the hybrid CPU/GPU systems built by university groups for single consumer cards are now the reference for running the largest MoE models on modest servers: PowerInfer's evaluation used an RTX 4090 and an RTX 2080 Ti with 11 GB ([PowerInfer paper](https://arxiv.org/pdf/2312.12456v1.pdf)), and KTransformers, published at SOSP 2025, reports 4.62–19.74x faster prefill than existing hybrid systems for models like the 671B DeepSeek-V3 ([Tsinghua MADSys](https://madsys.cs.tsinghua.edu.cn/publication/ktransformers-unleashing-the-full-potential-of-cpu/gpu-hybrid-inference-for-moe-models/)).

The same pattern shows up everywhere above. Intel ported a community-facing drafter to its laptops. Sony AI built its benchmark on community quant formats. Quantization work co-written by one engineer is now inside most of the GGUF files people download. None of these people were on the lab's payroll.

## The missing piece: a way to send the findings back

There is one gap in this flywheel. When a model runs on someone's own machine, the lab sees nothing. No API call, no log, no thumbs-down button. Every failure a local user hits is invisible unless that person writes a forum post, and even then nobody is sure where it should go.

Here is a real example. In April, an r/LocalLLaMA user reported that long conversations with Qwen3.5-35B-A3B degraded, traced it to two tensors whose scale was about 60% above normal, rescaled them and published a fixed GGUF. Commenters reported better long-context and tool-call stability after switching. One of the first replies asked: "Any way to notify qwen team about this?" In the captured thread, nobody had an answer ([r/LocalLLaMA](https://reddit.sentinel-team.org/posts/1sfwauj/snapshots/2026-04-11T01%3A00%3A59.600359Z)). The fix is self-reported and unverified, which is exactly why it should reach someone who can verify it.

Other failures are less dramatic but more common. A developer running Qwen behind a local agent found raw `<think>` tags in the output and tool calls returned as plain text, traced to the chat template his launcher used ([DEV Community](https://dev.to/carryologist/qwen-is-not-yet-ready-to-power-local-openclaw-deployments-5ha3)). Thousands of people hit variations of that. Each one debugs it alone.

### What an incident harvest looks like in practice

I run a small agent-dispatch framework, [llms.surf](https://github.com/carl0sfelipe/llms.surf), that sends coding tasks to local and cloud models. It treats every failure as an incident that must turn into a protection. The loop is simple:

1. **Capture automatically.** At the end of every dispatch, `bin/emit-usage-feedback.sh` records what happened (task, result, exit codes, harness, spec hash) without anyone asking. It is on by default and can be turned off with one environment variable.
2. **Record it as an incident.** `bin/incident.sh new` creates a file with symptom, cause with evidence, fix, and one key field: `recorrivel` (can it happen again?).
3. **Turn it into a mechanism, not advice.** The triage step ranks the options: first a step in a workflow, then code that blocks the failure, and only as a last resort a written rule. Every rule must name its mechanism or declare that it has none.
4. **Audit the debt.** `bin/incident.sh audit` exits with an error if any recurrent incident has not been promoted. Unfixed lessons fail the build.
5. **Strip private data before anything leaves.** The telemetry spec collects only execution aggregates, never source code, secrets, environment variables or absolute paths, and remote sending happens only if the user sets a URL. A separate gate, `bin/check-publico.sh`, blocks phone numbers, e-mails and machine paths from anything published.

Between July 24 and September 19, 2026, this produced 119 incident files; 56 are marked as promoted and 43 point to the numbered rule they created. When I ran a Qwen3.8-27B GGUF locally on an RTX 3090 for a benchmark, the framework refused an unregistered model and opened a usage incident by itself, before I had looked at the logs ([llms.surf dogfood report](https://github.com/carl0sfelipe/llms.surf/blob/main/docs/dogfooding-2026-09-26-rails-chatapp-gguf.md)).

That is one person's machine. Now picture the same loop across every machine running a lab's small model.

### What a lab would need to publish

A lab does not need to run anything on the user's machine. It needs to publish three things next to the weights:

1. **A feedback URL in the model card.** One documented endpoint that local tools and agents can find automatically, the way they already read the chat template from the repo.
2. **A closed incident schema.** Model ID and the file's hash, runtime and version, hardware class (VRAM tier, not serial numbers), failure category from a fixed list (chat template, tool-call format, long-context drift, quantization sensitivity, refusal calibration, crash), numeric measurements, and whether the reporter has a fix. Typed fields only, no free text.
3. **A public ledger of what happened to each report.** Received, reproduced, fixed in which release, credited to whom. This is what turns a bug report into a reason to keep reporting.

Asking people to "trust us, we only keep the technical part" will not be enough. Agents running on someone's machine see their code, their documents and their prompts. The feedback channel has to make that leak impossible to hide, not just promise it.

### Making it provable: feedback receipts

This is the part I am building. I'm working on cloudfair.tech, a service for verifiable receipts: records where some fields are public, others stay private, and anyone can check, with nothing but SHA-256 and a public blockchain, that a record existed and was not changed. Its first version issues receipts for random draws: each draw is hashed with its private inputs, thousands of hashes go into a Merkle tree (the same RFC 6962 structure used by Certificate Transparency), and the tree's root is written into a Bitcoin transaction. An auditor can verify any single draw without seeing the private inputs of any other.

The same machinery fits incident feedback almost exactly:

![Feedback receipts pipeline](/blog/why-frontier-models-need-a-30b-moe/img/receipts.svg)

1. **Split on the user's machine.** The local agent writes two records. The technical record holds only the closed-schema fields above. The private context, meaning prompts, file paths, code and the full log, never leaves the machine. Only a salted hash of it goes into the technical record, so the user can later prove what they saw if they choose to share it.
2. **Sanitize with published code.** A deterministic, open-source sanitizer builds the technical record, and its version hash goes into the record. Because the schema has no free-text fields, anyone can check that a record contains no prose, paths or code by validating it against the published schema. No trust in the lab or in me is needed for that check.
3. **Sign it.** The agent signs the record with a key created on that install, not tied to a name. The lab can deduplicate reports and weigh a reporter's track record without knowing who they are.
4. **Batch and anchor.** Records go into a Merkle tree, and the root is anchored on Bitcoin. Each reporter keeps a receipt with an inclusion proof.
5. **Status changes are new entries, never edits.** "Reproduced" or "fixed in v1.2" are appended in later batches, pointing back to the original receipt.

What this proves, mathematically:

- **The lab received exactly what the user's agent sent.** The signature covers the bytes, and the inclusion proof ties them to a public anchor. The lab cannot later say a report never arrived, or quietly edit it.
- **The payload is technical only, by construction.** Anyone can validate every received record against the public schema. The private context is represented only by a hash, which reveals nothing about its content.
- **Reports were not silently dropped.** Each batch's size and root are public, so a lab that claims "few reports about this quant" can be checked against its own anchored batches.

What it does not prove: that a field value inside the schema could never be identifying in some edge case, or that the user ran the published sanitizer rather than a modified one. The first is handled by keeping the schema small and coarse (VRAM tier, not GPU serial). The second can be tightened later with a zero-knowledge proof that the record is the sanitizer's output for the committed raw log. That is heavier engineering, and the schema-plus-receipt design works without it.

The cost is small. One Bitcoin transaction anchors a whole batch: cloudfair's design puts a 48-byte root in an OP_RETURN output and estimates about US$0.00003 per record at its planned batch sizes.

![The flywheel](/blog/why-frontier-models-need-a-30b-moe/img/loop.svg)

## The 16 GB rule for labs

If a lab wants this flywheel, the design target is concrete:

1. **Fit a 16 GB card at 4 bits, with room for context.** The 35B-A3B needs about 22 GB at 4 bits ([Unsloth](https://unsloth.ai/docs/models/qwen3.6)), so on 16 GB it already relies on offload or 3-bit quants. A ~30B MoE with ~3B active is the ceiling, not the floor.
2. **Keep active parameters small.** That is what makes offload to DDR4 bearable and lets 8 GB and 12 GB cards join in.
3. **Ship a permissive license.** Apache 2.0 and MIT are why forks, quants and pruned variants can be published without asking.
4. **Ship it next to the flagship, not a year later.** Every guide, quant and drafter built on the small sibling teaches people your architecture, your tool format and your quirks. That knowledge transfers to your large model.
5. **Publish a feedback URL and an incident ledger with the weights.** The people running your model at home are the largest test fleet you will ever have. Give their agents somewhere to send what they find.

A small model will not top the leaderboard. It does not need to. Its job is to put your architecture in front of the largest possible number of curious people, and to let them find the ideas you have not had yet.

## Which model to run today

- **16 GB GPU:** Qwen3.6-35B-A3B at 3 or 4 bits with `--n-cpu-moe`, or a per-tensor quant like ByteShape's. Try ik_llama.cpp and mainline and keep whichever is faster on your machine.
- **8–12 GB GPU with 32 GB+ RAM:** the same model with all MoE layers on the CPU, as in the DDR4 example above.
- **24 GB GPU:** 4-bit fits fully; add DFlash or MTP for speed. If you need the best quality and can accept lower speed, the 27B dense models are stronger on Qwen's coding benchmarks (77.2 vs 73.4 on SWE-bench Verified, [InsiderLLM](https://insiderllm.com/guides/qwen-3-6-local-ai-guide/)).

If GLM-5.5 Flash turns out to be a ~32B open MoE, it will be the first new contender for this slot since April, and the forks above will be running it within days.

> Updated on October 31, 2026. Speeds are community reports with different backends, quants and settings; compare within a row, not across rows.

## Sources

- [AGTP on X — GLM-5.5 rumor](https://x.com/AGTPinsights/status/2116516321479275000)
- [OpenCode — glm-5.5-flash](https://opencode.ai/data/zhipu/glm-5-5-flash)
- [CellCog — GLM-5.5 leak vs what Z.ai shipped](https://cellcog.ai/blog/glm-5-5-release-date/)
- [Gigazine — GLM-4.7-Flash](https://gigazine.net/gsc_news/en/20260120-zai-glm-4-7-flash)
- [Wikipedia — Qwen](https://en.wikipedia.org/wiki/Qwen)
- [explainx — Qwen3.8-Flash-Next](https://explainx.ai/blog/qwen3-8-flash-next-125b-moe-release-august-2026)
- [Codersera — Qwen 3.7 status](https://codersera.com/blog/qwen-3-7-release-date-whats-new-2026/)
- [InsiderLLM — Qwen 3.6 guide](https://insiderllm.com/guides/qwen-3-6-local-ai-guide/)
- [Steam Hardware & Software Survey — September 2026](https://store.steampowered.com/hwsurvey/Steam-Hardware-Software-Survey-Welcome-to-Steam)
- [Our calculation — who can run each size](/blog/why-frontier-models-need-a-30b-moe/medicoes/README.md)
- [Cerebras — REAP](https://www.cerebras.ai/blog/reap)
- [PowerInfer paper](https://arxiv.org/pdf/2312.12456v1.pdf)
- [Tsinghua MADSys — KTransformers (SOSP 2025)](https://madsys.cs.tsinghua.edu.cn/publication/ktransformers-unleashing-the-full-potential-of-cpu/gpu-hybrid-inference-for-moe-models/)
- [llama.cpp — common/arg.cpp](https://github.com/ggml-org/llama.cpp/blob/master/common/arg.cpp)
- [Habr — Qwen3.6 35B on 12 GB + DDR4](https://habr.com/en/articles/1026482/)
- [llama.cpp k-quants commit (#1684)](https://app.semanticdiff.com/gh/ggml-org/llama.cpp/commit/99009e72f8072fa552eb02efee436be596c71cdd)
- [SourcePulse — ik_llama.cpp](https://www.sourcepulse.org/projects/1843811)
- [r/LocalLLaMA — 110 tok/s with 12 GB and ik_llama.cpp](https://reddit.sentinel-team.org/posts/1tjh7az/snapshots/2026-05-30T00%3A45%3A07.677242Z)
- [r/LocalLLaMA — ik_llama.cpp vs llama.cpp on DDR4](https://reddit.sentinel-team.org/posts/1ruew2g/snapshots/2026-03-16T20%3A46%3A16.316967Z)
- [r/LocalLLaMA — 249 t/s with MTP](https://reddit.sentinel-team.org/posts/1tlfp5s/snapshots/2026-05-30T00%3A45%3A07.677242Z)
- [AI Weekly — ByteShape on 6 GB](https://aiweekly.co/alerts/byteshape-qwen3-quant-beats-unsloth-iq-by-30-on-6gb-vram)
- [ecosyste.ms — Lucebox Hub](https://awesome.ecosyste.ms/projects/github.com%2FLuce-Org%2Flucebox-hub)
- [Ranil Mukesh — PFlash, DFlash and Lucebox](https://ranilmukesh.github.io/blog/ai-inference-bottleneck/)
- [dev.co — z-lab DFlash for Qwen3.6-35B-A3B](https://dev.co/ai/llms/qwen3-6-35b-a3b-dflash)
- [Hugging Face — DFlash on Intel Core Ultra](https://huggingface.co/blog/ofirzaf/intel-dflash-ptl)
- [Feng Wang — Pruning Qwen3.6-35B-A3B](https://fengwang.github.io/posts/qwen-pruning-rtx5090/)
- [Trendshift — KTransformers](https://trendshift.io/repositories/14292)
- [SourcePulse — PowerInfer](https://www.sourcepulse.org/projects/981103)
- [arXiv 2608.21693 — Composable compression in MoE LLMs](https://arxiv.org/pdf/2608.21693)
- [YaRN — arXiv 2309.00071](https://arxiv.org/pdf/2309.00071)
- [vLLM — context extension](https://docs.vllm.ai/en/stable/features/context_extension/)
- [Unsloth — Qwen3.6](https://unsloth.ai/docs/models/qwen3.6)
- [Hugging Face — State of Open Models: Summer 2026](https://huggingface.co/blog/state-of-open-models-summer-2026)
- [ATOM Report — Measuring the Open Language Model Ecosystem](https://arxiv.org/html/2604.07190)
- [GummySearch — r/LocalLLaMA](https://gummysearch.com/r/LocalLLaMA/)
- [r/LocalLLaMA — Qwen3.5-35B-A3B tensor fix, "Any way to notify qwen team?"](https://reddit.sentinel-team.org/posts/1sfwauj/snapshots/2026-04-11T01%3A00%3A59.600359Z)
- [DEV Community — Qwen behind a local agent](https://dev.to/carryologist/qwen-is-not-yet-ready-to-power-local-openclaw-deployments-5ha3)
- [llms.surf — incidents, feedback protocol, telemetry](https://github.com/carl0sfelipe/llms.surf)
- [Divvi Up in Firefox](https://divviup.org/blog/divvi-up-in-firefox/)
- [Keller Jordan and Muon — 36Kr](https://eu.36kr.com/en/p/3698501921320835)
- [Kimi K2 technical report](https://ar5iv.labs.arxiv.org/html/2507.20534)
- [GLM-4.5 technical report](https://www.emergentmind.com/papers/2508.06471)
- [Min-p paper (arXiv 2407.01082)](https://arxiv.org/pdf/2407.01082v5)
- [Prompt lookup decoding — Simon Willison](https://www.simonwillison.net/2024/Jan/23/prompt-lookup-decoding)
- [transformers — assisted decoding](https://huggingface.co/docs/transformers/en/assisted_decoding)
- [Unsloth — fixing Gemma bugs](https://www.plushcap.com/content/unsloth/blog/unsloth-fixing-all-gemma-bugs)
- [Phi-4 bug fixes — Simon Willison](https://feeds.simonwillison.net/2025/Jan/11/phi-4-bug-fixes/)
- [DeepSeek-V3 technical report](https://arxiv.org/html/2412.19437)
- [kaiokendev — Things I'm learning while training SuperHOT](https://hn.jakechampion.name/reader/https://kaiokendev.github.io/til)
- [llama.cpp — Wikipedia](https://en.wikipedia.org/wiki/Llama.cpp)
