"""Fine-tunes an open model into your label model with LoRA.

    pip install -r llm/requirements.txt
    python3 llm/train_lora.py --base Qwen/Qwen2.5-1.5B-Instruct

Needs a GPU (a single 16-24 GB card is plenty for 0.5B-3B models; a free Colab T4 works for
1.5B with --batch-size 2). Output:
    out/label-maker-lora/    the LoRA adapter
    out/label-maker-merged/  base + adapter merged, ready to convert to GGUF or serve with vLLM

Loss is computed on the assistant reply only, so the model learns to write labels, not to
repeat prompts.
"""

import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            messages = json.loads(line)["messages"]
            # Prompt/completion split: train only on the assistant turn.
            rows.append({"prompt": messages[:-1], "completion": messages[-1:]})
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="Qwen/Qwen2.5-1.5B-Instruct",
                        help="Hugging Face model id of an instruct model with a chat template")
    parser.add_argument("--train", type=Path, default=HERE / "data" / "train.jsonl")
    parser.add_argument("--eval", type=Path, default=HERE / "data" / "eval.jsonl")
    parser.add_argument("--out", type=Path, default=HERE / "out")
    parser.add_argument("--epochs", type=float, default=3)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--grad-accum", type=int, default=4)
    parser.add_argument("--max-length", type=int, default=3072,
                        help="tokens per example; product pages are trimmed to ~4000 characters in the app")
    parser.add_argument("--rank", type=int, default=16)
    args = parser.parse_args()

    # Imported here so --help works without the heavy dependencies installed.
    import torch
    from datasets import Dataset
    from peft import LoraConfig
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from trl import SFTConfig, SFTTrainer

    train = Dataset.from_list(load_jsonl(args.train))
    evaluation = Dataset.from_list(load_jsonl(args.eval)) if args.eval.exists() and args.eval.stat().st_size else None
    print(f"train examples: {len(train)}  eval examples: {len(evaluation) if evaluation else 0}")

    bf16 = torch.cuda.is_available() and torch.cuda.is_bf16_supported()
    tokenizer = AutoTokenizer.from_pretrained(args.base)
    model = AutoModelForCausalLM.from_pretrained(
        args.base, torch_dtype=torch.bfloat16 if bf16 else torch.float16 if torch.cuda.is_available() else torch.float32)

    adapter_dir = args.out / "label-maker-lora"
    config = SFTConfig(
        output_dir=str(adapter_dir),
        num_train_epochs=args.epochs,
        learning_rate=args.lr,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        logging_steps=10,
        save_strategy="epoch",
        eval_strategy="epoch" if evaluation is not None else "no",
        max_length=args.max_length,
        bf16=bf16,
        fp16=torch.cuda.is_available() and not bf16,
        gradient_checkpointing=True,
        report_to="none",
    )
    lora = LoraConfig(r=args.rank, lora_alpha=args.rank * 2, lora_dropout=0.05,
                      target_modules="all-linear", task_type="CAUSAL_LM")
    trainer = SFTTrainer(model=model, args=config, train_dataset=train, eval_dataset=evaluation,
                         processing_class=tokenizer, peft_config=lora)
    trainer.train()
    trainer.save_model(str(adapter_dir))
    tokenizer.save_pretrained(str(adapter_dir))

    merged_dir = args.out / "label-maker-merged"
    merged = trainer.model.merge_and_unload()
    merged.save_pretrained(str(merged_dir), safe_serialization=True)
    tokenizer.save_pretrained(str(merged_dir))
    print(f"Adapter: {adapter_dir}\nMerged model: {merged_dir}\nNext: see llm/README.md, 'Serve it'.")


if __name__ == "__main__":
    main()
