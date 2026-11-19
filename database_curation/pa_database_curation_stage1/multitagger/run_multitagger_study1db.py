import os
import glob
import pickle
import argparse

import numpy as np
import pandas as pd
import torch
from transformers import AutoTokenizer

from AMIA.models.bert_model import BertForMultiLabelClassification

# -----------------------------
# SETTINGS - edit these
# -----------------------------
INPUT_CSV = "articles_for_classification.csv"
TEXT_COLUMN = "abstract"            # column in INPUT_CSV that holds the text
OUTPUT_CSV = "multitagger_predictions.csv"
CHECKPOINT_DIR = "best_verbalize_478k"
THRESHOLD_FILE = os.path.join(CHECKPOINT_DIR, "best_thresholds.pkl")

# Set to a number (e.g. 50) to test on the first N rows; None = all rows
TEST_ROWS = None

# Progress is saved every BATCH_SIZE articles into this folder.
# If the run stops, just run the script again: finished batches are skipped.
BATCH_SIZE = 500
PARTS_DIR = "prediction_parts"

BERT_MODEL_NAME = "microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext"
MAX_LEN = 512


# -----------------------------
# LABELS + THRESHOLDS
# Taken straight from the model's own thresholds file, so the
# label names, count (59) and order always match the checkpoint.
# -----------------------------
def load_labels_and_thresholds(threshold_file):
    with open(threshold_file, "rb") as f:
        t = pickle.load(f)
    labels = list(t.keys())
    thresholds = np.array([float(t[l]) for l in labels])
    return labels, thresholds


# -----------------------------
# MODEL
# -----------------------------
class SimpleConfig:
    def __init__(self, bert_model_name, bert_dropout):
        self.bert_model_name = bert_model_name
        self.bert_dropout = bert_dropout


def load_model(checkpoint_dir, num_labels):
    config = SimpleConfig(BERT_MODEL_NAME, bert_dropout=0.1)
    model = BertForMultiLabelClassification(config, num_labels=num_labels)

    checkpoint_path = os.path.join(checkpoint_dir, "best_f1.mdl")
    torch.serialization.add_safe_globals([argparse.Namespace])
    state = torch.load(checkpoint_path, map_location="cpu", weights_only=False)

    model.load_state_dict(state["model"])
    model.eval()
    return model


# -----------------------------
# INFERENCE
# -----------------------------
def predict(model, tokenizer, texts, thresholds):
    all_probs = []
    for text in texts:
        enc = tokenizer([text], padding=True, truncation=True,
                        max_length=MAX_LEN, return_tensors="pt")
        batch = type("Batch", (), {})()
        batch.text_ids = enc["input_ids"]
        batch.attention_mask_text = enc["attention_mask"]

        with torch.no_grad():
            logits = model(batch)
            probs = torch.sigmoid(logits).numpy()[0]
        all_probs.append(probs)

    probs = np.vstack(all_probs)
    preds = (probs >= thresholds).astype(int)
    return probs, preds


def add_prediction_columns(df, labels, probs, preds):
    types = pd.DataFrame({"predicted_types": [
        "; ".join(l for l, p in zip(labels, row) if p) for row in preds
    ]}, index=df.index)
    yes_no = pd.DataFrame(preds, columns=labels, index=df.index)
    prob = pd.DataFrame(probs.round(4), columns=[f"prob_{l}" for l in labels],
                        index=df.index)
    return pd.concat([df, types, yes_no, prob], axis=1)


def part_path(batch_num):
    return os.path.join(PARTS_DIR, f"part_{batch_num:05d}.csv")


def combine_parts(n_batches):
    paths = [part_path(b) for b in range(n_batches)]
    missing = [p for p in paths if not os.path.exists(p)]
    if missing:
        raise SystemExit(f"Cannot combine: {len(missing)} batch files missing, "
                         f"e.g. {missing[0]}. Run the script again.")
    with open(OUTPUT_CSV, "w", encoding="utf-8", newline="") as out:
        for i, p in enumerate(paths):
            with open(p, "r", encoding="utf-8", newline="") as f:
                header = f.readline()
                if i == 0:
                    out.write(header)
                for line in f:
                    out.write(line)


def main():
    labels, thresholds = load_labels_and_thresholds(THRESHOLD_FILE)
    print(f"Loaded {len(labels)} labels from {THRESHOLD_FILE}")

    df = pd.read_csv(INPUT_CSV)
    if TEXT_COLUMN not in df.columns:
        raise SystemExit(
            f"Column '{TEXT_COLUMN}' not found in {INPUT_CSV}.\n"
            f"Available columns: {list(df.columns)}\n"
            f"Edit TEXT_COLUMN at the top of this script."
        )
    if TEST_ROWS:
        df = df.head(TEST_ROWS).copy()
        print(f"TEST MODE: using first {len(df)} rows (set TEST_ROWS = None for all)")

    total = len(df)
    n_batches = (total + BATCH_SIZE - 1) // BATCH_SIZE
    os.makedirs(PARTS_DIR, exist_ok=True)

    # Guard against leftover batch files from a run with different settings
    marker = os.path.join(PARTS_DIR, "run_info.txt")
    info = f"{os.path.abspath(INPUT_CSV)}|{total}|{BATCH_SIZE}|{TEXT_COLUMN}|{CHECKPOINT_DIR}"
    if os.path.exists(marker):
        with open(marker, encoding="utf-8") as f:
            if f.read().strip() != info:
                raise SystemExit(
                    f"The '{PARTS_DIR}' folder has saved batches from a run with "
                    f"different settings (input file, TEST_ROWS, BATCH_SIZE, ...).\n"
                    f"Delete or rename the '{PARTS_DIR}' folder, then run again."
                )
    else:
        with open(marker, "w", encoding="utf-8") as f:
            f.write(info)

    todo = [b for b in range(n_batches) if not os.path.exists(part_path(b))]
    done = n_batches - len(todo)
    print(f"{total} articles in {n_batches} batches of {BATCH_SIZE}. "
          f"Already done: {done}. Remaining: {len(todo)}.")

    if todo:
        tokenizer = AutoTokenizer.from_pretrained(BERT_MODEL_NAME)
        model = load_model(CHECKPOINT_DIR, num_labels=len(labels))

    for b in todo:
        start, end = b * BATCH_SIZE, min((b + 1) * BATCH_SIZE, total)
        chunk = df.iloc[start:end]
        texts = chunk[TEXT_COLUMN].fillna("").astype(str).tolist()
        probs, preds = predict(model, tokenizer, texts, thresholds)
        out = add_prediction_columns(chunk, labels, probs, preds)

        # Write to a temp file, then rename, so a crash never leaves
        # a half-written batch that looks finished.
        tmp = part_path(b) + ".tmp"
        out.to_csv(tmp, index=False, encoding="utf-8")
        os.replace(tmp, part_path(b))
        done += 1
        print(f"  batch {done}/{n_batches} saved (articles {start + 1}-{end} of {total})")

    print("Combining batches...")
    combine_parts(n_batches)
    print(f"Saved predictions to {OUTPUT_CSV}")
    print(f"(Once you've checked it, you can delete the '{PARTS_DIR}' folder.)")


if __name__ == "__main__":
    main()