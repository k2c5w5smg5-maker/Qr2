# Your own label model

The label maker writes labels with a language model that you own and run. This folder is
everything needed to make that model, test it, and serve it to the app.

## The approach

Training a language model from scratch costs millions of dollars and isn't needed for this
job. Instead, take a small open-weight instruct model (Qwen 2.5, Llama 3.2, Gemma, Phi) and
**fine-tune** it on examples of exactly this task. The result is your model: your weights,
your server, no per-request fees to anyone, and it gets better as you use the app.

```
 product page ─┐                    ┌────────────────────┐
 voice / text ─┼─> app builds the ─>│ your fine-tuned LLM │──> {"labels":[...]} ──> PDF sheet
 current labels┘   prompt (on device)│ (OpenAI-style API)  │
                                    └────────────────────┘
            every printed sheet (after your edits) ──> training example ──> next fine-tune
```

- The **app** reads the product page on the phone, builds the prompt and parses the reply.
  Without a model it falls back to on-device rules, so it always works standalone.
- The **contract** between app and model is fixed: the system prompt in
  [`prompt/system.txt`](prompt/system.txt) plus the user message format in
  [`labelformat.py`](labelformat.py), which mirror `LabelKit/Model/LabelPrompt.swift`.
- The **data flywheel**: turn on *Settings → Save training examples* in the app. Each sheet
  you print or share is saved with the labels as you corrected them. Share the file to your
  computer and add it to the training set.

## Files

| File | What it does |
| --- | --- |
| `prompt/system.txt` | The system prompt. Must match the app (`check_prompt_sync.py` checks). |
| `labelformat.py` | Python port of the app's prompt format, reply parser and record checks. |
| `build_seed.py` | Writes `data/seed.jsonl`, 18 hand-written examples. Add your own. |
| `prepare_data.py` | Merges seed + app exports, validates, de-duplicates, splits train/eval. |
| `train_lora.py` | LoRA fine-tune with Hugging Face TRL; writes an adapter and a merged model. |
| `eval.py` | Scores any served model on the eval set (stdlib only). |
| `Modelfile` | Ollama recipe for the finished model. |

## 1. Build the dataset

```bash
python3 llm/build_seed.py
python3 llm/prepare_data.py llm/data/seed.jsonl ~/Downloads/label-training.jsonl
```

Aim for 300 to 1,000 good examples before expecting great results. Mix the kinds of jobs you
care about: product pages from the stores you use, spoken lists, edits ("make 10 of each").
Quality beats quantity: every assistant answer must be exactly what you want printed, so fix
any mistakes in the app before printing (your edits are what gets saved).

To get there faster, generate drafts with a large model: feed it real product pages through
`labelformat.user_message(...)`, then review and correct every answer before using it. Check
the large model's terms of use allow training on its output.

## 2. Fine-tune

On a machine with an NVIDIA GPU (or Google Colab):

```bash
pip install -r llm/requirements.txt
python3 llm/train_lora.py --base Qwen/Qwen2.5-1.5B-Instruct
```

- `Qwen/Qwen2.5-1.5B-Instruct` (Apache 2.0) is a good default: fast, cheap to serve, and good
  at JSON. Try `Qwen/Qwen2.5-3B-Instruct` or `meta-llama/Llama-3.2-3B-Instruct` if quality is
  short. Check each model's license for commercial use.
- A few hundred examples train in minutes on one GPU. Watch eval loss; if it rises while
  train loss falls, reduce `--epochs`.

## 3. Serve it

The app talks to any OpenAI-compatible `POST /v1/chat/completions` endpoint.

**llama.cpp (laptop, Mac mini, small VPS):**

```bash
python3 llama.cpp/convert_hf_to_gguf.py llm/out/label-maker-merged --outfile llm/out/label-maker-f16.gguf
llama.cpp/build/bin/llama-quantize llm/out/label-maker-f16.gguf llm/out/label-maker-q4_k_m.gguf Q4_K_M
llama.cpp/build/bin/llama-server -m llm/out/label-maker-q4_k_m.gguf --host 0.0.0.0 --port 8080 --api-key "$LABEL_MODEL_KEY"
```

**Ollama:** after the GGUF step, `ollama create label-maker -f llm/Modelfile`, then use base
URL `http://<host>:11434/v1`.

**vLLM (GPU server, many users):**
`vllm serve llm/out/label-maker-merged --served-model-name label-maker --api-key "$LABEL_MODEL_KEY"`

Then score it:

```bash
python3 llm/eval.py --url http://localhost:8080/v1 --model label-maker --key "$LABEL_MODEL_KEY" --show
```

Run the same command against the untuned base model to see what fine-tuning bought you.

## 4. Point the app at it

In the app: *Labels → gear icon → Your label model*. Enter the base URL (for example
`https://labels.yourdomain.com/v1`), the model name (`label-maker`) and the API key, then tap
*Test connection*.

- For a public App Store release, put the model behind HTTPS with your own domain. Don't
  hard-code a server key that unlocks anything else; a key inside an app can be extracted.
  Rate-limit the endpoint.
- iOS blocks plain `http://` to internet hosts. For testing on your own network, use the
  computer's local IP. If a request is still blocked, add an App Transport Security
  exception for local networking to the target's Info settings.
- Privacy: your server receives the page summary and the user's instructions. Declare that in
  App Store Connect's privacy section and in your privacy policy.

## Keeping app and model in sync

If you change the prompt format, change it in **both** `LabelKit/Model/LabelPrompt.swift`
and `llm/` (`prompt/system.txt`, `labelformat.py`), run `python3 llm/check_prompt_sync.py`,
and retrain. A model trained on one prompt and served with another quietly gets worse.
