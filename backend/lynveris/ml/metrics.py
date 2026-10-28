import numpy as np


def metrics(y, predicted, concluded=None):
    y, p = np.asarray(y, dtype=int), np.asarray(predicted, dtype=bool)
    tp, fp = int(np.sum((y == 1) & p)), int(np.sum((y == 0) & p))
    tn, fn = int(np.sum((y == 0) & ~p)), int(np.sum((y == 1) & ~p))
    precision, recall = tp / (tp + fp) if tp + fp else 0, tp / (tp + fn) if tp + fn else 0
    coverage = (
        float(np.mean(concluded)) if concluded is not None and len(y) else (1.0 if len(y) else 0)
    )
    return dict(
        n=len(y),
        tp=tp,
        fp=fp,
        tn=tn,
        fn=fn,
        precision=precision,
        recall=recall,
        f1=2 * precision * recall / (precision + recall) if precision + recall else 0,
        fpr=fp / (fp + tn) if fp + tn else None,
        coverage=coverage,
        unknown_rate=1 - coverage,
    )


def fused_scores(scores, detected, rule_flags=None):
    result = np.maximum(np.asarray(scores, dtype=float), np.asarray(detected, dtype=float))
    return (
        np.maximum(result, np.asarray(rule_flags, dtype=float))
        if rule_flags is not None
        else result
    )


def choose_threshold(y, scores, max_fpr=0.05, require_recall=False):
    if not any(label == 0 for label in y) or not any(label == 1 for label in y):
        raise ValueError("Validation requires both labels")
    candidates = sorted(set(float(s) for s in scores if 0 < s <= 1))
    valid = []
    for threshold in candidates:
        m = metrics(y, np.asarray(scores) >= threshold)
        if m["fpr"] is not None and m["fpr"] <= max_fpr:
            valid.append((m["recall"], m["precision"], threshold))
    if not valid:
        raise ValueError("No threshold satisfies final combined FPR constraint")
    recall, precision, threshold = max(valid)
    if require_recall and recall == 0:
        raise ValueError("No useful recall at required FPR")
    return threshold
