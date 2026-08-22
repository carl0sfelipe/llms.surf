# DISCOVERY — llama.cpp (llama-server)
Data: 2026-07-25T20:16:43Z
Binário: <home-do-dono>/llama.cpp/build/bin/llama-server
```
----- common params -----

-h,    --help, --usage                  print usage and exit
--version                               show version and build info
-cl,   --cache-list                     show list of models in cache
--completion-bash                       print source-able bash completion script for llama.cpp
-t,    --threads N                      number of CPU threads to use during generation (default: -1)
                                        (env: LLAMA_ARG_THREADS)
-tb,   --threads-batch N                number of threads to use during batch and prompt processing (default:
                                        same as --threads)
-C,    --cpu-mask M                     CPU affinity mask: arbitrarily long hex. Complements cpu-range
                                        (default: "")
-Cr,   --cpu-range lo-hi                range of CPUs for affinity. Complements --cpu-mask
--cpu-strict <0|1>                      use strict CPU placement (default: 0)
--prio N                                set process/thread priority : low(-1), normal(0), medium(1), high(2),
                                        realtime(3) (default: 0)
--poll <0...100>                        use polling level to wait for work (0 - no polling, default: 50)
-Cb,   --cpu-mask-batch M               CPU affinity mask: arbitrarily long hex. Complements cpu-range-batch
                                        (default: same as --cpu-mask)
-Crb,  --cpu-range-batch lo-hi          ranges of CPUs for affinity. Complements --cpu-mask-batch
--cpu-strict-batch <0|1>                use strict CPU placement (default: same as --cpu-strict)
--prio-batch N                          set process/thread priority : 0-normal, 1-medium, 2-high, 3-realtime
                                        (default: 0)
--poll-batch <0|1>                      use polling to wait for work (default: same as --poll)
-c,    --ctx-size N                     size of the prompt context (default: 0, 0 = loaded from model)
                                        (env: LLAMA_ARG_CTX_SIZE)
-n,    --predict, --n-predict N         number of tokens to predict (default: -1, -1 = infinity)
                                        (env: LLAMA_ARG_N_PREDICT)
-b,    --batch-size N                   logical maximum batch size (default: 2048)
                                        (env: LLAMA_ARG_BATCH)
-ub,   --ubatch-size N                  physical maximum batch size (default: 512)
                                        (env: LLAMA_ARG_UBATCH)
--keep N                                number of tokens to keep from the initial prompt (default: 0, -1 =
                                        all)
--swa-full                              use full-size SWA cache (default: false)
                                        [(more
                                        info)](https://github.com/ggml-org/llama.cpp/pull/13194#issuecomment-2868343055)
                                        (env: LLAMA_ARG_SWA_FULL)
-fa,   --flash-attn [on|off|auto]       set Flash Attention use ('on', 'off', or 'auto', default: 'auto')
                                        (env: LLAMA_ARG_FLASH_ATTN)
--perf, --no-perf                       whether to enable internal libllama performance timings (default:
                                        false)
                                        (env: LLAMA_ARG_PERF)
-e,    --escape, --no-escape            whether to process escapes sequences (\n, \r, \t, \', \", \\)
                                        (default: true)
--rope-scaling {none,linear,yarn}       RoPE frequency scaling method, defaults to linear unless specified by
                                        the model
                                        (env: LLAMA_ARG_ROPE_SCALING_TYPE)
--rope-scale N                          RoPE context scaling factor, expands context by a factor of N
                                        (env: LLAMA_ARG_ROPE_SCALE)
--rope-freq-base N                      RoPE base frequency, used by NTK-aware scaling (default: loaded from
                                        model)
                                        (env: LLAMA_ARG_ROPE_FREQ_BASE)
--rope-freq-scale N                     RoPE frequency scaling factor, expands context by a factor of 1/N
                                        (env: LLAMA_ARG_ROPE_FREQ_SCALE)
--yarn-orig-ctx N                       YaRN: original context size of model (default: 0 = model training
                                        context size)
                                        (env: LLAMA_ARG_YARN_ORIG_CTX)
--yarn-ext-factor N                     YaRN: extrapolation mix factor (default: -1.00, 0.0 = full
                                        interpolation)
                                        (env: LLAMA_ARG_YARN_EXT_FACTOR)
--yarn-attn-factor N                    YaRN: scale sqrt(t) or attention magnitude (default: -1.00)
                                        (env: LLAMA_ARG_YARN_ATTN_FACTOR)
--yarn-beta-slow N                      YaRN: high correction dim or alpha (default: -1.00)
                                        (env: LLAMA_ARG_YARN_BETA_SLOW)
--yarn-beta-fast N                      YaRN: low correction dim or beta (default: -1.00)
                                        (env: LLAMA_ARG_YARN_BETA_FAST)
-kvo,  --kv-offload, -nkvo, --no-kv-offload
                                        whether to enable KV cache offloading (default: enabled)
                                        (env: LLAMA_ARG_KV_OFFLOAD)
--repack, -nr, --no-repack              whether to enable weight repacking (default: enabled)
                                        (env: LLAMA_ARG_REPACK)
--no-host                               bypass host buffer allowing extra buffers to be used
                                        (env: LLAMA_ARG_NO_HOST)
-ctk,  --cache-type-k TYPE              KV cache data type for K
                                        allowed values: f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1
                                        (default: f16)
                                        (env: LLAMA_ARG_CACHE_TYPE_K)
-ctv,  --cache-type-v TYPE              KV cache data type for V
                                        allowed values: f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1
```
