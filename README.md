# c-transformer

A transformer-based language model implemented from scratch in C++ and CUDA. No frameworks. The full stack is covered: a BPE tokenizer, CPU and GPU forward passes, analytical backpropagation, AdamW training, custom CUDA kernels (Flash Attention, fused LayerNorm), and a standalone inference binary.

Karpathy's [llm.c](https://github.com/karpathy/llm.c) is used as a reference

---

## Requirements

| Component | Version |
|-----------|---------|
| C++ compiler | GCC or Clang with C++17 support |
| CUDA Toolkit | 12.x (`nvcc`) |
| GPU | NVIDIA (consumer GPU for development; A100 for full training) |
| Profiling (optional) | Nsight Compute (`ncu`), Nsight Systems (`nsys`) |

---

## Build

```bash
git clone https://github.com/Pepps233/c-transformer.git
cd c-transformer
make          # build all binaries
make test     # run unit tests
make train    # run training
```

Host code is compiled with `g++`/`clang++`; CUDA kernels with `nvcc`. The Makefile links them together — no CMake, Bazel, or Meson required.

---

## Architecture

Decoder-only transformer following Vaswani et al. (2017):

```
Token IDs
  → Embedding + Positional Encoding
  → [LayerNorm → Multi-Head Attention → Residual
     → LayerNorm → FFN (GELU) → Residual] × N
  → LayerNorm → Projection → Logits
```

**Design decisions:**

- Token IDs stored as flat binary `uint16_t` files, memory-mapped during training. No JSON or CSV in the training loop.
- `cuBLAS` handles production matrix multiplication. Custom kernels target attention, LayerNorm, and GELU — the components where writing by hand yields the most insight.
- FP32 throughout the baseline; mixed precision is introduced only after correctness is established.
- Mersenne Twister or PCG for random number generation. `rand()` is not suitable for reproducible training.

---

## Components

### BPE Tokenizer

Byte-pair encoding trained from scratch. Produces a vocabulary file and a merges file. Correctness is verified with encode/decode round-trips on arbitrary strings. An open-addressing hashmap (~200 lines of C++) handles pair counts; `uthash` is a drop-in alternative.

### CPU Forward Pass

Full transformer forward pass in plain C++ loops, no CUDA. Correctness is established here before any GPU code is written. A small model (2 layers, 4 heads, dimension 32) with fixed weights is verified against hand-computed values on a 5-token input.

### GPU Forward Pass

Each operation ported to CUDA one kernel at a time: elementwise ops, LayerNorm, matmul (naive first, then cuBLAS), attention. Every kernel is validated by running the same operation on CPU and GPU with identical inputs and asserting agreement within `1e-4`.

### Backward Pass and Training

Gradients are derived analytically before implementation. Gradient checking — `(f(x+ε) − f(x−ε)) / (2ε)` compared against the analytical result — is applied to every operation before it enters the training loop.

AdamW (Loshchilov & Hutter, 2019) is implemented with decoupled weight decay. The training loop assembles batch loading, forward pass, cross-entropy loss, backward pass, and optimizer step. The first validation milestone is overfitting a single batch of ~1,000 tokens to near-zero loss.

### Custom CUDA Kernels

- **Flash Attention** (Dao et al., 2022) — tiled attention that stays within SRAM, eliminating full HBM reads of the attention matrix. Forward pass first, backward follows.
- **Fused LayerNorm** — mean, variance, and normalized output in one pass over the data, removing intermediate HBM writes.
- **Fused GELU** — merged into the feedforward matmul (optional further optimization).

Every kernel is benchmarked against its naive counterpart using Nsight Compute. Throughput numbers are reported from measured results.

### Training

Small-scale run: ~5M parameters (4 layers, 256 hidden, 4 heads) on a consumer GPU, completes in hours. Full run: ~12M parameters on A100s via Modal or Lambda Labs, typically in the tens-of-dollars range. Loss is logged, checkpoints written regularly, and a separate inference path is kept runnable throughout.

### Inference

A standalone `infer` binary loads a checkpoint and samples from a prompt. No Python runtime required.

---

## Dataset

[TinyStories](https://huggingface.co/datasets/roneneldan/TinyStories) (Eldan & Li, 2023) — roughly 2 GB of plain English text. Designed so that models with single-digit millions of parameters can produce coherent output, making the difference between a working implementation and a broken one visually obvious.

Tokenize once, write to a flat binary, memory-map during training.

---

## References

| Paper | Relevance |
|-------|-----------|
| Vaswani et al., "Attention Is All You Need" (2017) | Core architecture |
| Sennrich et al., "Neural Machine Translation of Rare Words with Subword Units" (2016) | BPE tokenizer |
| Loshchilov & Hutter, "Decoupled Weight Decay Regularization" (2019) | AdamW optimizer |
| Dao et al., "FlashAttention" (2022) | Memory-efficient attention kernel |
| Milakov & Gimelshein, "Online Normalizer Calculation for Softmax" (2018) | Numerically stable softmax used in Flash Attention |

---

## License

MIT
