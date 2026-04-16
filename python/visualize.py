#!/usr/bin/env python3
"""
Benchmark Analysis & Visualization Script

Parses JMeter .jtl result files and generates comparison charts
for monolith vs microservices architectures.

Usage:
    python visualize.py --experiment-dir results/2026-04-10_12-34-56
    python visualize.py --experiment-dir results/2026-04-10_12-34-56 --output results/2026-04-10_12-34-56/charts
"""

import argparse
import math
import os
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import pandas as pd
import seaborn as sns

# Consistent styling
sns.set_theme(style="whitegrid")
plt.rcParams.update(
    {
        "figure.figsize": (12, 7),
        "font.size": 12,
        "axes.titlesize": 14,
        "axes.labelsize": 12,
        "figure.dpi": 150,
    }
)

COLORS = {
    "monolith": "#2196F3",
    "microservices": "#FF5722",
}

PRIMARY_METRICS = ["throughput_rps", "p95_latency_ms", "error_rate_pct"]


def load_jtl(filepath: str, warmup_seconds: int = 0) -> pd.DataFrame:
    """Load a JMeter .jtl (CSV) file into a DataFrame.

    Args:
        filepath: Path to the .jtl file.
        warmup_seconds: Number of seconds to discard from the start of the test.
            Samples within the first ``warmup_seconds`` are dropped before analysis.
    """
    df = pd.read_csv(filepath)

    # Standard JTL column names
    expected_cols = [
        "timeStamp",
        "elapsed",
        "label",
        "responseCode",
        "success",
        "bytes",
        "sentBytes",
        "grpThreads",
        "allThreads",
        "Latency",
        "IdleTime",
        "Connect",
    ]

    # Normalize column names (JMeter sometimes uses different casing)
    col_map = {c.lower(): c for c in expected_cols}
    df.columns = [col_map.get(c.lower(), c) for c in df.columns]

    # Convert timestamp to datetime
    if "timeStamp" in df.columns:
        df["datetime"] = pd.to_datetime(df["timeStamp"], unit="ms")

    # Ensure success is boolean
    if "success" in df.columns:
        df["success"] = df["success"].astype(str).str.lower() == "true"

    # Normalize labels (strip duplicated suffixes like "(2)", "(3)")
    if "label" in df.columns:
        df["endpoint"] = df["label"].str.replace(r"\s*\(\d+\)$", "", regex=True)

    # Filter out warmup samples
    if warmup_seconds > 0 and "timeStamp" in df.columns:
        min_ts = df["timeStamp"].min()
        cutoff = min_ts + warmup_seconds * 1000
        before = len(df)
        df = df[df["timeStamp"] >= cutoff].reset_index(drop=True)
        print(
            f"  Warmup filter: discarded {before - len(df):,} samples "
            f"(first {warmup_seconds}s), kept {len(df):,}"
        )

    return df


def compute_metrics(df: pd.DataFrame) -> dict:
    """Compute aggregate metrics from a DataFrame."""
    total_requests = len(df)
    duration_s = (df["timeStamp"].max() - df["timeStamp"].min()) / 1000.0

    metrics = {
        "total_requests": total_requests,
        "duration_seconds": round(duration_s, 2),
        "throughput_rps": round(total_requests / duration_s, 2)
        if duration_s > 0
        else 0,
        "avg_latency_ms": round(df["elapsed"].mean(), 2),
        "median_latency_ms": round(df["elapsed"].median(), 2),
        "p90_latency_ms": round(df["elapsed"].quantile(0.90), 2),
        "p95_latency_ms": round(df["elapsed"].quantile(0.95), 2),
        "p99_latency_ms": round(df["elapsed"].quantile(0.99), 2),
        "max_latency_ms": round(df["elapsed"].max(), 2),
        "min_latency_ms": round(df["elapsed"].min(), 2),
        "error_count": int((~df["success"]).sum()),
        "error_rate_pct": round((~df["success"]).mean() * 100, 4),
        "avg_bytes": round(df["bytes"].mean(), 2) if "bytes" in df.columns else 0,
    }

    return metrics


def compute_per_endpoint_metrics(df: pd.DataFrame) -> pd.DataFrame:
    """Compute metrics grouped by endpoint."""
    rows = []
    for endpoint, group in df.groupby("endpoint"):
        m = compute_metrics(group)
        m["endpoint"] = endpoint
        rows.append(m)
    return pd.DataFrame(rows)


def print_summary(label: str, metrics: dict):
    """Pretty-print summary metrics."""
    print(f"\n{'=' * 60}")
    print(f"  {label}")
    print(f"{'=' * 60}")
    print(f"  Total Requests:    {metrics['total_requests']:,}")
    print(f"  Duration:          {metrics['duration_seconds']:.1f}s")
    print(f"  Throughput:        {metrics['throughput_rps']:.2f} req/s")
    print(f"  Avg Latency:       {metrics['avg_latency_ms']:.2f} ms")
    print(f"  Median Latency:    {metrics['median_latency_ms']:.2f} ms")
    print(f"  P90 Latency:       {metrics['p90_latency_ms']:.2f} ms")
    print(f"  P95 Latency:       {metrics['p95_latency_ms']:.2f} ms")
    print(f"  P99 Latency:       {metrics['p99_latency_ms']:.2f} ms")
    print(f"  Max Latency:       {metrics['max_latency_ms']:.2f} ms")
    print(f"  Error Rate:        {metrics['error_rate_pct']:.4f}%")
    print(f"  Errors:            {metrics['error_count']:,}")
    print(f"{'=' * 60}")


def _concat_runs_contiguous(run_dfs: list[pd.DataFrame]) -> pd.DataFrame:
    """Concatenate runs while removing inter-run wall-clock gaps.

    Each run keeps its relative timing, but timestamps are shifted so runs are
    back-to-back. This avoids misleading throughput/duration artifacts from
    startup/cooldown gaps between runs.
    """
    shifted = []
    offset = 0
    for df in run_dfs:
        part = df.copy()
        run_min = int(part["timeStamp"].min())
        part["timeStamp"] = part["timeStamp"] - run_min + offset
        run_span = int(part["timeStamp"].max()) + 1
        offset += run_span
        shifted.append(part)

    if not shifted:
        return pd.DataFrame()

    return pd.concat(shifted, ignore_index=True)


def _prepare_run_second_series(df: pd.DataFrame) -> pd.DataFrame:
    """Return a copy with per-run relative second column."""
    out = df.copy()
    out["second"] = ((out["timeStamp"] - out["timeStamp"].min()) / 1000).astype(int)
    return out


def _aggregate_series_with_ci(
    series_list: list[pd.Series],
) -> tuple[pd.Series, pd.Series]:
    """Align multiple indexed series and return mean and 95% CI half-width."""
    if not series_list:
        return pd.Series(dtype=float), pd.Series(dtype=float)

    aligned = pd.concat(series_list, axis=1)
    mean = aligned.mean(axis=1)
    std = aligned.std(axis=1, ddof=1).fillna(0.0)
    n = aligned.notna().sum(axis=1).clip(lower=1)
    ci = 1.96 * std / np.sqrt(n)
    return mean, ci


def plot_throughput_over_time_avg(
    monolith_runs: list[pd.DataFrame],
    micro_runs: list[pd.DataFrame],
    output_dir: str,
):
    """Mean throughput-over-time across runs with 95% CI."""
    fig, ax = plt.subplots()

    for label, runs, color in [
        ("Monolith", monolith_runs, COLORS["monolith"]),
        ("Microservices", micro_runs, COLORS["microservices"]),
    ]:
        run_series = []
        for run_df in runs:
            d = _prepare_run_second_series(run_df)
            throughput = (
                d.groupby("second").size().rolling(window=30, min_periods=1).mean()
            )
            run_series.append(throughput)

        mean, ci = _aggregate_series_with_ci(run_series)
        if mean.empty:
            continue

        ax.plot(mean.index, mean.values, label=label, color=color, alpha=0.9)
        ax.fill_between(
            mean.index, (mean - ci).values, (mean + ci).values, color=color, alpha=0.2
        )

    ax.set_xlabel("Time (seconds)")
    ax.set_ylabel("Throughput (req/s)")
    ax.set_title("Throughput Over Time (mean across runs, 95% CI)")
    ax.legend()
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{int(x)}s"))

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "throughput_over_time.png"))
    plt.close()
    print("  Saved: throughput_over_time.png")


def plot_latency_over_time_avg(
    monolith_runs: list[pd.DataFrame],
    micro_runs: list[pd.DataFrame],
    output_dir: str,
):
    """Mean P95 latency-over-time across runs with 95% CI."""
    fig, ax = plt.subplots()

    for label, runs, color in [
        ("Monolith", monolith_runs, COLORS["monolith"]),
        ("Microservices", micro_runs, COLORS["microservices"]),
    ]:
        run_series = []
        for run_df in runs:
            d = _prepare_run_second_series(run_df)
            d["bucket"] = (d["second"] // 10) * 10
            p95 = d.groupby("bucket")["elapsed"].quantile(0.95)
            run_series.append(p95)

        mean, ci = _aggregate_series_with_ci(run_series)
        if mean.empty:
            continue

        ax.plot(mean.index, mean.values, label=label, color=color, alpha=0.9)
        ax.fill_between(
            mean.index, (mean - ci).values, (mean + ci).values, color=color, alpha=0.2
        )

    ax.set_xlabel("Time (seconds)")
    ax.set_ylabel("P95 Latency (ms)")
    ax.set_title("P95 Latency Over Time (mean across runs, 95% CI)")
    ax.legend()

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "latency_over_time.png"))
    plt.close()
    print("  Saved: latency_over_time.png")


def plot_endpoint_latency_over_time_avg(
    monolith_runs: list[pd.DataFrame],
    micro_runs: list[pd.DataFrame],
    output_dir: str,
):
    """Per-endpoint P95 latency over time as mean across runs."""
    all_endpoints = set()
    for run_df in monolith_runs + micro_runs:
        all_endpoints.update(run_df["endpoint"].unique())
    all_endpoints = sorted(all_endpoints)

    endpoint_colors = {
        "GET /products/{id}": "#4CAF50",
        "GET /products": "#4CAF50",
        "GET /users/{id}": "#2196F3",
        "GET /users": "#2196F3",
        "POST /orders": "#FF5722",
    }

    fig, ax = plt.subplots(figsize=(14, 7))

    for label, runs, linestyle, alpha in [
        ("Monolith", monolith_runs, "-", 0.9),
        ("Microservices", micro_runs, "--", 0.8),
    ]:
        for endpoint in all_endpoints:
            run_series = []
            for run_df in runs:
                d = _prepare_run_second_series(run_df)
                ep = d[d["endpoint"] == endpoint].copy()
                if ep.empty:
                    continue
                ep["bucket"] = (ep["second"] // 10) * 10
                p95 = ep.groupby("bucket")["elapsed"].quantile(0.95)
                run_series.append(p95)

            mean, _ = _aggregate_series_with_ci(run_series)
            if mean.empty:
                continue

            color = endpoint_colors.get(endpoint, "gray")
            ax.plot(
                mean.index,
                mean.values,
                label=f"{endpoint} ({label})",
                color=color,
                linestyle=linestyle,
                alpha=alpha,
                linewidth=2.2,
            )

    ax.set_xlabel("Time (seconds)")
    ax.set_ylabel("P95 Latency (ms)")
    ax.set_title("Per-Endpoint P95 Latency Over Time (mean across runs)")
    ax.legend(loc="best", fontsize=9, ncol=2)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(
        os.path.join(output_dir, "endpoint_latency_over_time.png"), bbox_inches="tight"
    )
    plt.close()
    print("  Saved: endpoint_latency_over_time.png")


def plot_latency_comparison(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Bar chart comparing latency percentiles between architectures."""
    mono_m = compute_metrics(monolith_df)
    micro_m = compute_metrics(micro_df)

    percentiles = ["avg", "median", "p90", "p95", "p99"]
    labels = ["Average", "Median", "P90", "P95", "P99"]
    mono_vals = [mono_m[f"{p}_latency_ms"] for p in percentiles]
    micro_vals = [micro_m[f"{p}_latency_ms"] for p in percentiles]

    x = np.arange(len(labels))
    width = 0.35

    fig, ax = plt.subplots()
    bars1 = ax.bar(
        x - width / 2, mono_vals, width, label="Monolith", color=COLORS["monolith"]
    )
    bars2 = ax.bar(
        x + width / 2,
        micro_vals,
        width,
        label="Microservices",
        color=COLORS["microservices"],
    )

    ax.set_ylabel("Latency (ms)")
    ax.set_title("Response Latency Comparison")
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.legend()

    # Add value labels on bars
    for bar in bars1:
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            bar.get_height(),
            f"{bar.get_height():.1f}",
            ha="center",
            va="bottom",
            fontsize=9,
        )
    for bar in bars2:
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            bar.get_height(),
            f"{bar.get_height():.1f}",
            ha="center",
            va="bottom",
            fontsize=9,
        )

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "latency_comparison.png"))
    plt.close()
    print(f"  Saved: latency_comparison.png")


def plot_latency_distribution(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Histogram/KDE of response times for both architectures."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 7))

    # Cap at P99 for readability
    mono_cap = monolith_df["elapsed"].quantile(0.99)
    micro_cap = micro_df["elapsed"].quantile(0.99)

    axes[0].hist(
        monolith_df["elapsed"][monolith_df["elapsed"] <= mono_cap],
        bins=100,
        color=COLORS["monolith"],
        alpha=0.7,
        edgecolor="white",
    )
    axes[0].set_title("Monolith - Latency Distribution")
    axes[0].set_xlabel("Response Time (ms)")
    axes[0].set_ylabel("Frequency")
    axes[0].axvline(
        monolith_df["elapsed"].median(),
        color="red",
        linestyle="--",
        label=f"Median: {monolith_df['elapsed'].median():.0f}ms",
    )
    axes[0].axvline(
        monolith_df["elapsed"].quantile(0.95),
        color="orange",
        linestyle="--",
        label=f"P95: {monolith_df['elapsed'].quantile(0.95):.0f}ms",
    )
    axes[0].legend()

    axes[1].hist(
        micro_df["elapsed"][micro_df["elapsed"] <= micro_cap],
        bins=100,
        color=COLORS["microservices"],
        alpha=0.7,
        edgecolor="white",
    )
    axes[1].set_title("Microservices - Latency Distribution")
    axes[1].set_xlabel("Response Time (ms)")
    axes[1].set_ylabel("Frequency")
    axes[1].axvline(
        micro_df["elapsed"].median(),
        color="red",
        linestyle="--",
        label=f"Median: {micro_df['elapsed'].median():.0f}ms",
    )
    axes[1].axvline(
        micro_df["elapsed"].quantile(0.95),
        color="orange",
        linestyle="--",
        label=f"P95: {micro_df['elapsed'].quantile(0.95):.0f}ms",
    )
    axes[1].legend()

    plt.suptitle("Response Time Distribution", fontsize=16, y=1.02)
    plt.tight_layout()
    plt.savefig(
        os.path.join(output_dir, "latency_distribution.png"), bbox_inches="tight"
    )
    plt.close()
    print(f"  Saved: latency_distribution.png")


def plot_per_endpoint_comparison(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Compare latency and throughput per endpoint."""
    mono_ep = compute_per_endpoint_metrics(monolith_df)
    micro_ep = compute_per_endpoint_metrics(micro_df)

    # Merge on endpoint
    mono_ep["architecture"] = "Monolith"
    micro_ep["architecture"] = "Microservices"
    combined = pd.concat([mono_ep, micro_ep], ignore_index=True)

    # Filter to main endpoints
    main_endpoints = ["GET /products/{id}", "GET /users/{id}", "POST /orders"]
    combined = combined[combined["endpoint"].isin(main_endpoints)]

    if combined.empty:
        print("  Warning: No matching endpoints found for per-endpoint comparison")
        return

    fig, axes = plt.subplots(1, 2, figsize=(16, 7))

    # P95 Latency per endpoint
    pivot_p95 = combined.pivot(
        index="endpoint", columns="architecture", values="p95_latency_ms"
    )
    pivot_p95.plot(
        kind="bar", ax=axes[0], color=[COLORS["microservices"], COLORS["monolith"]]
    )
    axes[0].set_title("P95 Latency per Endpoint")
    axes[0].set_ylabel("Latency (ms)")
    axes[0].set_xlabel("")
    axes[0].tick_params(axis="x", rotation=0)

    # Throughput per endpoint
    pivot_tps = combined.pivot(
        index="endpoint", columns="architecture", values="throughput_rps"
    )
    pivot_tps.plot(
        kind="bar", ax=axes[1], color=[COLORS["microservices"], COLORS["monolith"]]
    )
    axes[1].set_title("Throughput per Endpoint")
    axes[1].set_ylabel("Requests/sec")
    axes[1].set_xlabel("")
    axes[1].tick_params(axis="x", rotation=0)

    plt.suptitle("Per-Endpoint Performance Comparison", fontsize=16, y=1.02)
    plt.tight_layout()
    plt.savefig(
        os.path.join(output_dir, "per_endpoint_comparison.png"), bbox_inches="tight"
    )
    plt.close()
    print(f"  Saved: per_endpoint_comparison.png")


def plot_per_endpoint_error_rate(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Compare error rates by endpoint between architectures."""
    mono = monolith_df.copy()
    mono["architecture"] = "Monolith"
    micro = micro_df.copy()
    micro["architecture"] = "Microservices"
    combined = pd.concat([mono, micro], ignore_index=True)

    endpoint_errors = (
        combined.groupby(["endpoint", "architecture"])["success"]
        .apply(lambda s: (~s).mean() * 100.0)
        .reset_index(name="error_rate_pct")
    )

    if endpoint_errors.empty:
        print("  Warning: No endpoint error data found")
        return

    endpoint_errors.to_csv(
        os.path.join(output_dir, "per_endpoint_error_rate.csv"), index=False
    )
    print("  Saved: per_endpoint_error_rate.csv")

    fig, ax = plt.subplots(figsize=(12, 6))
    sns.barplot(
        data=endpoint_errors,
        x="endpoint",
        y="error_rate_pct",
        hue="architecture",
        palette={
            "Monolith": COLORS["monolith"],
            "Microservices": COLORS["microservices"],
        },
        ax=ax,
    )
    ax.set_ylabel("Error Rate (%)")
    ax.set_xlabel("Endpoint")
    ax.set_title("Per-Endpoint Error Rate")
    ax.tick_params(axis="x", rotation=15)
    plt.tight_layout()
    plt.savefig(
        os.path.join(output_dir, "per_endpoint_error_rate.png"), bbox_inches="tight"
    )
    plt.close()
    print("  Saved: per_endpoint_error_rate.png")


def plot_error_rate_comparison(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Compare error rates between architectures."""
    mono_m = compute_metrics(monolith_df)
    micro_m = compute_metrics(micro_df)

    fig, ax = plt.subplots(figsize=(8, 6))

    architectures = ["Monolith", "Microservices"]
    error_rates = [mono_m["error_rate_pct"], micro_m["error_rate_pct"]]
    colors = [COLORS["monolith"], COLORS["microservices"]]

    bars = ax.bar(architectures, error_rates, color=colors, width=0.5)

    for bar, rate in zip(bars, error_rates):
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            bar.get_height(),
            f"{rate:.4f}%",
            ha="center",
            va="bottom",
            fontsize=12,
        )

    ax.set_ylabel("Error Rate (%)")
    ax.set_title("Error Rate Comparison")

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "error_rate_comparison.png"))
    plt.close()
    print(f"  Saved: error_rate_comparison.png")


def plot_throughput_bar(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Simple side-by-side bar chart of total throughput (req/s)."""
    mono_m = compute_metrics(monolith_df)
    micro_m = compute_metrics(micro_df)

    fig, ax = plt.subplots(figsize=(8, 6))

    architectures = ["Monolith", "Microservices"]
    throughputs = [mono_m["throughput_rps"], micro_m["throughput_rps"]]
    colors = [COLORS["monolith"], COLORS["microservices"]]

    bars = ax.bar(architectures, throughputs, color=colors, width=0.5)

    for bar, val in zip(bars, throughputs):
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            bar.get_height(),
            f"{val:,.1f}",
            ha="center",
            va="bottom",
            fontsize=13,
            fontweight="bold",
        )

    ax.set_ylabel("Throughput (req/s)")
    ax.set_title("Overall Throughput Comparison")

    # Add ratio annotation
    if throughputs[1] > 0:
        ratio = throughputs[0] / throughputs[1]
        ax.annotate(
            f"Monolith is {ratio:.1f}x higher",
            xy=(0.5, 0.92),
            xycoords="axes fraction",
            ha="center",
            fontsize=11,
            fontstyle="italic",
            color="gray",
        )

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "throughput_bar.png"))
    plt.close()
    print(f"  Saved: throughput_bar.png")


def plot_latency_boxplot(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Side-by-side boxplots showing latency spread, quartiles, and outliers."""
    fig, ax = plt.subplots(figsize=(9, 7))

    # Cap at P99 of each to avoid extreme outlier compression
    mono_cap = monolith_df["elapsed"].quantile(0.99)
    micro_cap = micro_df["elapsed"].quantile(0.99)
    mono_capped = monolith_df["elapsed"][monolith_df["elapsed"] <= mono_cap]
    micro_capped = micro_df["elapsed"][micro_df["elapsed"] <= micro_cap]

    # Subsample to 100k points max for performance (boxplot with millions of points is slow)
    max_samples = 100_000
    if len(mono_capped) > max_samples:
        mono_capped = mono_capped.sample(n=max_samples, random_state=42)
    if len(micro_capped) > max_samples:
        micro_capped = micro_capped.sample(n=max_samples, random_state=42)

    # Build a combined DataFrame for seaborn
    combined = pd.DataFrame(
        {
            "Response Time (ms)": pd.concat(
                [mono_capped, micro_capped], ignore_index=True
            ),
            "Architecture": (
                ["Monolith"] * len(mono_capped) + ["Microservices"] * len(micro_capped)
            ),
        }
    )

    sns.boxplot(
        data=combined,
        x="Architecture",
        y="Response Time (ms)",
        hue="Architecture",
        palette={
            "Monolith": COLORS["monolith"],
            "Microservices": COLORS["microservices"],
        },
        width=0.5,
        fliersize=2,
        legend=False,
        ax=ax,
    )

    # Annotate medians
    for i, arch in enumerate(["Monolith", "Microservices"]):
        subset = combined[combined["Architecture"] == arch]["Response Time (ms)"]
        median = subset.median()
        ax.text(
            i,
            median,
            f" {median:.1f}ms",
            ha="left",
            va="center",
            fontsize=10,
            fontweight="bold",
            color="black",
        )

    ax.set_title("Response Time Distribution (capped at P99)")

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "latency_boxplot.png"))
    plt.close()
    print(f"  Saved: latency_boxplot.png")


def generate_csv_report(
    monolith_df: pd.DataFrame, micro_df: pd.DataFrame, output_dir: str
):
    """Generate a CSV summary report."""
    mono_m = compute_metrics(monolith_df)
    micro_m = compute_metrics(micro_df)

    mono_m["architecture"] = "Monolith"
    micro_m["architecture"] = "Microservices"

    report_df = pd.DataFrame([mono_m, micro_m])
    cols = ["architecture"] + [c for c in report_df.columns if c != "architecture"]
    report_df = report_df[cols]

    report_path = os.path.join(output_dir, "benchmark_summary.csv")
    report_df.to_csv(report_path, index=False)
    print(f"  Saved: benchmark_summary.csv")

    # Per-endpoint report
    mono_ep = compute_per_endpoint_metrics(monolith_df)
    micro_ep = compute_per_endpoint_metrics(micro_df)
    mono_ep["architecture"] = "Monolith"
    micro_ep["architecture"] = "Microservices"
    combined = pd.concat([mono_ep, micro_ep], ignore_index=True)
    endpoint_path = os.path.join(output_dir, "per_endpoint_summary.csv")
    combined.to_csv(endpoint_path, index=False)
    print(f"  Saved: per_endpoint_summary.csv")


def discover_experiment_runs(experiment_dir: str) -> tuple[list[Path], list[Path]]:
    """Discover run_*.jtl files for both architectures."""
    exp_path = Path(experiment_dir)
    # experiment_dir + "monolith" + run_\d.jtl
    monolith_files = sorted(exp_path.joinpath("monolith").glob("run_*.jtl"))
    microservices_files = sorted(exp_path.joinpath("microservices").glob("run_*.jtl"))
    return monolith_files, microservices_files


def discover_scenario_dirs(experiment_root: Path) -> list[Path]:
    """Return scenario dirs containing both monolith and microservices runs."""
    scenario_dirs = []
    for child in sorted(experiment_root.iterdir()):
        if not child.is_dir():
            continue
        if (
            child.joinpath("monolith").is_dir()
            and child.joinpath("microservices").is_dir()
        ):
            scenario_dirs.append(child)
    return scenario_dirs


def _run_number_from_name(path: Path) -> int:
    """Extract run number from run_N filename."""
    try:
        return int(path.stem.split("_")[1])
    except (IndexError, ValueError):
        return 0


def _plot_multi_run_series(
    df: pd.DataFrame,
    metric: str,
    ylabel: str,
    title: str,
    output_name: str,
    output_dir: str,
):
    """Plot run-indexed line chart for a metric."""
    fig, ax = plt.subplots(figsize=(10, 6))

    for arch, color in [
        ("Monolith", COLORS["monolith"]),
        ("Microservices", COLORS["microservices"]),
    ]:
        subset = df[df["architecture"] == arch].sort_values("run")
        if subset.empty:
            continue
        ax.plot(
            subset["run"], subset[metric], "o-", color=color, label=arch, linewidth=2
        )

    ax.set_xlabel("Run")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, output_name))
    plt.close()
    print(f"  Saved: {output_name}")


def _plot_multi_run_boxplot(
    df: pd.DataFrame,
    metric: str,
    ylabel: str,
    title: str,
    output_name: str,
    output_dir: str,
):
    """Plot architecture-level boxplot over runs for a metric."""
    fig, ax = plt.subplots(figsize=(9, 6))
    sns.boxplot(
        data=df,
        x="architecture",
        y=metric,
        hue="architecture",
        palette={
            "Monolith": COLORS["monolith"],
            "Microservices": COLORS["microservices"],
        },
        legend=False,
        ax=ax,
    )
    sns.stripplot(
        data=df,
        x="architecture",
        y=metric,
        color="black",
        alpha=0.5,
        size=5,
        ax=ax,
    )
    ax.set_xlabel("Architecture")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, output_name))
    plt.close()
    print(f"  Saved: {output_name}")


def _confidence_interval_95(series: pd.Series) -> float:
    """Approximate 95% CI half-width using normal approximation."""
    clean = series.dropna()
    n = len(clean)
    if n < 2:
        return 0.0
    std = clean.std(ddof=1)
    if pd.isna(std):
        return 0.0
    return float(1.96 * std / math.sqrt(n))


def _generate_research_tables(per_run_df: pd.DataFrame, output_dir: str):
    """Generate report-ready statistical tables."""
    if per_run_df.empty:
        return

    if "scenario" not in per_run_df.columns:
        per_run_df = per_run_df.copy()
        per_run_df["scenario"] = "default"

    # Normalize pool sweep scenario naming so pool_exhaustion_p2/p5/p10 can be
    # compared as one scenario family.
    normalized = per_run_df.copy()
    if "pool_max_size" in normalized.columns:
        pool_rows = (
            normalized["scenario"].astype(str).str.startswith("pool_exhaustion_p")
        )
        normalized.loc[pool_rows, "scenario"] = "pool_exhaustion"

    # Mean/Std/CI by scenario x architecture.
    rows = []
    grouped = normalized.groupby(["scenario", "architecture"])
    for (scenario, architecture), group in grouped:
        row = {"scenario": scenario, "architecture": architecture, "runs": len(group)}
        for metric in PRIMARY_METRICS:
            row[f"{metric}_mean"] = round(float(group[metric].mean()), 4)
            row[f"{metric}_std"] = (
                round(float(group[metric].std(ddof=1)), 4) if len(group) > 1 else 0.0
            )
            row[f"{metric}_ci95"] = round(_confidence_interval_95(group[metric]), 4)
        rows.append(row)

    stats_df = pd.DataFrame(rows).sort_values(["scenario", "architecture"])
    stats_df.to_csv(
        os.path.join(output_dir, "scenario_architecture_stats.csv"), index=False
    )
    print("  Saved: scenario_architecture_stats.csv")

    # Delta between architectures per scenario.
    delta_rows = []
    for scenario, group in normalized.groupby("scenario"):
        mono = group[group["architecture"] == "Monolith"]
        micro = group[group["architecture"] == "Microservices"]
        if mono.empty or micro.empty:
            continue

        row = {"scenario": scenario}
        for metric in PRIMARY_METRICS:
            mono_mean = float(mono[metric].mean())
            micro_mean = float(micro[metric].mean())
            row[f"{metric}_monolith_mean"] = round(mono_mean, 4)
            row[f"{metric}_microservices_mean"] = round(micro_mean, 4)
            row[f"{metric}_delta_abs"] = round(micro_mean - mono_mean, 4)
            if mono_mean != 0:
                row[f"{metric}_delta_pct_vs_monolith"] = round(
                    ((micro_mean - mono_mean) / mono_mean) * 100.0, 4
                )
            else:
                row[f"{metric}_delta_pct_vs_monolith"] = np.nan
        delta_rows.append(row)

    if delta_rows:
        delta_df = pd.DataFrame(delta_rows).sort_values("scenario")
        delta_df.to_csv(
            os.path.join(output_dir, "architecture_delta_by_scenario.csv"), index=False
        )
        print("  Saved: architecture_delta_by_scenario.csv")
    else:
        print("  Skipped: architecture_delta_by_scenario.csv (insufficient data)")

    # Degradation vs baseline for each architecture.
    if "baseline" in set(normalized["scenario"]):
        degr_rows = []
        baselines = (
            normalized[normalized["scenario"] == "baseline"]
            .groupby("architecture")[PRIMARY_METRICS]
            .mean()
        )
        for (scenario, architecture), group in normalized.groupby(
            ["scenario", "architecture"]
        ):
            if scenario == "baseline" or architecture not in baselines.index:
                continue
            row = {"scenario": scenario, "architecture": architecture}
            for metric in PRIMARY_METRICS:
                scenario_mean = float(group[metric].mean())
                baseline_mean = float(baselines.loc[architecture, metric])
                row[f"{metric}_mean"] = round(scenario_mean, 4)
                row[f"baseline_{metric}_mean"] = round(baseline_mean, 4)
                if baseline_mean != 0:
                    row[f"{metric}_change_pct_vs_baseline"] = round(
                        ((scenario_mean - baseline_mean) / baseline_mean) * 100.0, 4
                    )
                else:
                    row[f"{metric}_change_pct_vs_baseline"] = np.nan
            degr_rows.append(row)

        if degr_rows:
            degradation_df = pd.DataFrame(degr_rows).sort_values(
                ["architecture", "scenario"]
            )
            degradation_df.to_csv(
                os.path.join(output_dir, "degradation_vs_baseline.csv"), index=False
            )
            print("  Saved: degradation_vs_baseline.csv")
        else:
            print("  Skipped: degradation_vs_baseline.csv (only baseline present)")


def _normalize_scenario_labels(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize scenario labels for cross-scenario aggregation."""
    normalized = df.copy()
    if "scenario" not in normalized.columns:
        normalized["scenario"] = "default"

    def _normalize(name: str) -> str:
        text = str(name)
        if text.startswith("pool_exhaustion"):
            return "pool_exhaustion"
        return text

    normalized["scenario"] = normalized["scenario"].map(_normalize)
    return normalized


def _load_cross_scenario_per_run(experiment_root: Path) -> pd.DataFrame:
    """Load and merge per-run summaries across all scenario directories."""
    rows = []
    for scenario_dir in discover_scenario_dirs(experiment_root):
        summary_path = scenario_dir / "charts" / "per_run_summary.csv"
        if not summary_path.exists():
            continue
        df = pd.read_csv(summary_path)
        if "scenario" not in df.columns:
            df["scenario"] = scenario_dir.name
        rows.append(df)

    if not rows:
        return pd.DataFrame()
    return pd.concat(rows, ignore_index=True)


def _generate_cross_scenario_outputs(experiment_root: Path, output_dir: str):
    """Generate global scenario comparison and pooled sweep outputs."""
    per_run_df = _load_cross_scenario_per_run(experiment_root)
    if per_run_df.empty:
        print(
            "  Skipped cross-scenario aggregation: no per_run_summary.csv files found"
        )
        return

    per_run_path = os.path.join(output_dir, "all_scenarios_per_run_summary.csv")
    per_run_df.to_csv(per_run_path, index=False)
    print("  Saved: all_scenarios_per_run_summary.csv")

    normalized = _normalize_scenario_labels(per_run_df)
    normalized_path = os.path.join(
        output_dir, "all_scenarios_per_run_summary_normalized.csv"
    )
    normalized.to_csv(normalized_path, index=False)
    print("  Saved: all_scenarios_per_run_summary_normalized.csv")

    _generate_research_tables(normalized, output_dir)
    _plot_scenario_metric_ci(normalized, output_dir)
    _plot_scenario_boxplots(normalized, output_dir)
    _plot_pool_exhaustion_sweep(normalized, output_dir)


def _plot_scenario_metric_ci(per_run_df: pd.DataFrame, output_dir: str):
    """Plot scenario-level mean with 95% CI for primary metrics."""
    if per_run_df.empty:
        return

    normalized = per_run_df.copy()
    pool_rows = normalized["scenario"].astype(str).str.startswith("pool_exhaustion_p")
    normalized.loc[pool_rows, "scenario"] = "pool_exhaustion"
    scenario_order = list(dict.fromkeys(normalized["scenario"].tolist()))

    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    metric_meta = [
        ("throughput_rps", "Throughput (req/s)"),
        ("p95_latency_ms", "P95 Latency (ms)"),
        ("error_rate_pct", "Error Rate (%)"),
    ]

    for idx, (metric, ylabel) in enumerate(metric_meta):
        ax = axes[idx]
        for arch, color, offset in [
            ("Monolith", COLORS["monolith"], -0.1),
            ("Microservices", COLORS["microservices"], 0.1),
        ]:
            means = []
            cis = []
            xs = []
            for i, scenario in enumerate(scenario_order):
                subset = normalized[
                    (normalized["scenario"] == scenario)
                    & (normalized["architecture"] == arch)
                ]
                if subset.empty:
                    continue
                xs.append(i + offset)
                means.append(float(subset[metric].mean()))
                cis.append(_confidence_interval_95(subset[metric]))

            ax.errorbar(
                xs, means, yerr=cis, fmt="o-", capsize=4, color=color, label=arch
            )

        ax.set_title(metric.replace("_", " ").upper())
        ax.set_ylabel(ylabel)
        ax.set_xticks(range(len(scenario_order)))
        ax.set_xticklabels(scenario_order, rotation=20, ha="right")
        ax.grid(True, alpha=0.3)

    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=2)
    plt.tight_layout(rect=(0, 0, 1, 0.93))
    plt.savefig(
        os.path.join(output_dir, "scenario_comparison_ci.png"), bbox_inches="tight"
    )
    plt.close()
    print("  Saved: scenario_comparison_ci.png")


def _plot_scenario_boxplots(per_run_df: pd.DataFrame, output_dir: str):
    """Plot run-level scenario distributions for primary metrics."""
    if per_run_df.empty:
        return

    normalized = per_run_df.copy()
    pool_rows = normalized["scenario"].astype(str).str.startswith("pool_exhaustion_p")
    normalized.loc[pool_rows, "scenario"] = "pool_exhaustion"

    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    metric_meta = [
        ("throughput_rps", "Throughput (req/s)"),
        ("p95_latency_ms", "P95 Latency (ms)"),
        ("error_rate_pct", "Error Rate (%)"),
    ]

    for ax, (metric, ylabel) in zip(axes, metric_meta):
        sns.boxplot(
            data=normalized,
            x="scenario",
            y=metric,
            hue="architecture",
            palette={
                "Monolith": COLORS["monolith"],
                "Microservices": COLORS["microservices"],
            },
            ax=ax,
        )
        ax.set_ylabel(ylabel)
        ax.set_xlabel("Scenario")
        ax.tick_params(axis="x", rotation=20)

    handles, labels = axes[0].get_legend_handles_labels()
    for ax in axes:
        legend = ax.get_legend()
        if legend is not None:
            legend.remove()
    fig.legend(handles, labels, loc="upper center", ncol=2)

    plt.tight_layout(rect=(0, 0, 1, 0.93))
    plt.savefig(os.path.join(output_dir, "scenario_boxplots.png"), bbox_inches="tight")
    plt.close()
    print("  Saved: scenario_boxplots.png")


def _plot_pool_exhaustion_sweep(per_run_df: pd.DataFrame, output_dir: str):
    """Plot pool-size sweep charts for pool_exhaustion_p* scenarios."""
    if (
        "scenario" not in per_run_df.columns
        or "pool_max_size" not in per_run_df.columns
    ):
        return

    subset = per_run_df[
        per_run_df["scenario"].astype(str).str.startswith("pool_exhaustion")
    ].copy()
    if subset.empty:
        return

    subset = subset.dropna(subset=["pool_max_size"])
    if subset.empty:
        return

    summary_rows = []
    for (arch, pool_size), group in subset.groupby(["architecture", "pool_max_size"]):
        summary_rows.append(
            {
                "architecture": arch,
                "pool_max_size": int(pool_size),
                "runs": len(group),
                "throughput_mean": float(group["throughput_rps"].mean()),
                "throughput_ci95": _confidence_interval_95(group["throughput_rps"]),
                "p95_latency_mean": float(group["p95_latency_ms"].mean()),
                "p95_latency_ci95": _confidence_interval_95(group["p95_latency_ms"]),
                "error_rate_mean": float(group["error_rate_pct"].mean()),
                "error_rate_ci95": _confidence_interval_95(group["error_rate_pct"]),
            }
        )

    summary_df = pd.DataFrame(summary_rows).sort_values(
        ["architecture", "pool_max_size"]
    )
    summary_df.to_csv(os.path.join(output_dir, "pool_sweep_summary.csv"), index=False)
    print("  Saved: pool_sweep_summary.csv")

    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    metrics = [
        (
            "throughput_mean",
            "throughput_ci95",
            "Throughput (req/s)",
            "Throughput vs Pool Size",
        ),
        (
            "p95_latency_mean",
            "p95_latency_ci95",
            "P95 Latency (ms)",
            "P95 Latency vs Pool Size",
        ),
        (
            "error_rate_mean",
            "error_rate_ci95",
            "Error Rate (%)",
            "Error Rate vs Pool Size",
        ),
    ]

    for ax, (mean_col, ci_col, ylabel, title) in zip(axes, metrics):
        for arch, color in [
            ("Monolith", COLORS["monolith"]),
            ("Microservices", COLORS["microservices"]),
        ]:
            arch_df = summary_df[summary_df["architecture"] == arch]
            if arch_df.empty:
                continue
            x = arch_df["pool_max_size"].astype(int)
            y = arch_df[mean_col]
            ci = arch_df[ci_col]
            ax.errorbar(x, y, yerr=ci, fmt="o-", capsize=4, label=arch, color=color)

        ax.set_xlabel("Pool Max Size")
        ax.set_ylabel(ylabel)
        ax.set_title(title)
        ax.grid(True, alpha=0.3)

    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=2)
    plt.tight_layout(rect=(0, 0, 1, 0.93))
    plt.savefig(os.path.join(output_dir, "pool_sweep_metrics.png"), bbox_inches="tight")
    plt.close()
    print("  Saved: pool_sweep_metrics.png")


def _load_scenario_metadata(scenario_dir: Path) -> dict:
    """Load scenario metadata from scenario_config.csv if present."""
    metadata_file = scenario_dir / "scenario_config.csv"
    if not metadata_file.exists():
        return {}

    try:
        metadata_df = pd.read_csv(metadata_file)
        if metadata_df.empty:
            return {}
        return metadata_df.iloc[0].to_dict()
    except Exception as exc:  # pragma: no cover
        print(f"  Warning: failed to read scenario metadata ({metadata_file}): {exc}")
        return {}


def _analyze_scenario_data(
    scenario_dir: Path, warmup: int, scenario_name: str
) -> tuple[
    pd.DataFrame, pd.DataFrame, pd.DataFrame, list[pd.DataFrame], list[pd.DataFrame]
]:
    """Load all runs for one scenario and return run-level + combined dataframes."""
    monolith_files, microservices_files = discover_experiment_runs(str(scenario_dir))

    if not monolith_files:
        raise FileNotFoundError(
            f"No monolith run files found in: {scenario_dir / 'monolith'}"
        )
    if not microservices_files:
        raise FileNotFoundError(
            f"No microservices run files found in: {scenario_dir / 'microservices'}"
        )

    print(f"\nScenario: {scenario_name}")
    print(f"  Monolith runs:      {len(monolith_files)}")
    print(f"  Microservices runs: {len(microservices_files)}")

    metadata = _load_scenario_metadata(scenario_dir)

    run_rows = []
    monolith_dfs = []
    microservices_dfs = []

    for arch, files in [
        ("Monolith", monolith_files),
        ("Microservices", microservices_files),
    ]:
        for file_path in files:
            run_no = _run_number_from_name(file_path)
            df = load_jtl(str(file_path), warmup_seconds=warmup)
            m = compute_metrics(df)
            m["architecture"] = arch
            m["run"] = run_no
            m["file"] = str(file_path)
            m["scenario"] = scenario_name

            for key, value in metadata.items():
                m[key] = value

            run_rows.append(m)

            if arch == "Monolith":
                monolith_dfs.append(df)
            else:
                microservices_dfs.append(df)

    per_run_df = (
        pd.DataFrame(run_rows)
        .sort_values(["architecture", "run"])
        .reset_index(drop=True)
    )
    monolith_all = _concat_runs_contiguous(monolith_dfs)
    microservices_all = _concat_runs_contiguous(microservices_dfs)
    return per_run_df, monolith_all, microservices_all, monolith_dfs, microservices_dfs


def _generate_scenario_outputs(
    per_run_df: pd.DataFrame,
    monolith_all: pd.DataFrame,
    microservices_all: pd.DataFrame,
    monolith_runs: list[pd.DataFrame],
    microservices_runs: list[pd.DataFrame],
    output_dir: str,
):
    """Generate outputs for a single scenario directory."""
    os.makedirs(output_dir, exist_ok=True)

    per_run_df.to_csv(os.path.join(output_dir, "per_run_summary.csv"), index=False)
    print("  Saved: per_run_summary.csv")

    numeric_cols = [
        "total_requests",
        "duration_seconds",
        "throughput_rps",
        "avg_latency_ms",
        "median_latency_ms",
        "p90_latency_ms",
        "p95_latency_ms",
        "p99_latency_ms",
        "max_latency_ms",
        "min_latency_ms",
        "error_count",
        "error_rate_pct",
        "avg_bytes",
    ]
    aggregate_df = (
        per_run_df.groupby("architecture")[numeric_cols]
        .agg(["mean", "std", "min", "max"])
        .round(4)
    )
    aggregate_df.columns = [f"{col}_{stat}" for col, stat in aggregate_df.columns]
    aggregate_df = aggregate_df.reset_index()
    aggregate_df.to_csv(os.path.join(output_dir, "aggregate_summary.csv"), index=False)
    print("  Saved: aggregate_summary.csv")

    print("\nGenerating multi-run charts...")
    _plot_multi_run_series(
        per_run_df,
        "throughput_rps",
        "Throughput (req/s)",
        "Throughput Across Runs",
        "throughput_per_run.png",
        output_dir,
    )
    _plot_multi_run_series(
        per_run_df,
        "p95_latency_ms",
        "P95 Latency (ms)",
        "P95 Latency Across Runs",
        "p95_latency_per_run.png",
        output_dir,
    )
    _plot_multi_run_series(
        per_run_df,
        "error_rate_pct",
        "Error Rate (%)",
        "Error Rate Across Runs",
        "error_rate_per_run.png",
        output_dir,
    )

    _plot_multi_run_boxplot(
        per_run_df,
        "throughput_rps",
        "Throughput (req/s)",
        "Run-Level Throughput Distribution",
        "throughput_boxplot_runs.png",
        output_dir,
    )
    _plot_multi_run_boxplot(
        per_run_df,
        "p95_latency_ms",
        "P95 Latency (ms)",
        "Run-Level P95 Latency Distribution",
        "p95_latency_boxplot_runs.png",
        output_dir,
    )
    _plot_multi_run_boxplot(
        per_run_df,
        "error_rate_pct",
        "Error Rate (%)",
        "Run-Level Error Rate Distribution",
        "error_rate_boxplot_runs.png",
        output_dir,
    )

    print("\nGenerating architecture comparison charts (combined runs)...")
    mono_m = compute_metrics(monolith_all)
    micro_m = compute_metrics(microservices_all)
    print_summary("Monolith (all runs)", mono_m)
    print_summary("Microservices (all runs)", micro_m)

    plot_latency_comparison(monolith_all, microservices_all, output_dir)
    plot_latency_distribution(monolith_all, microservices_all, output_dir)
    plot_throughput_over_time_avg(monolith_runs, microservices_runs, output_dir)
    plot_per_endpoint_comparison(monolith_all, microservices_all, output_dir)
    plot_error_rate_comparison(monolith_all, microservices_all, output_dir)
    plot_latency_over_time_avg(monolith_runs, microservices_runs, output_dir)
    plot_throughput_bar(monolith_all, microservices_all, output_dir)
    plot_latency_boxplot(monolith_all, microservices_all, output_dir)
    plot_endpoint_latency_over_time_avg(monolith_runs, microservices_runs, output_dir)

    print("\nGenerating architecture comparison reports...")
    generate_csv_report(monolith_all, microservices_all, output_dir)
    plot_per_endpoint_error_rate(monolith_all, microservices_all, output_dir)

    print("\nGenerating scenario-level research visuals...")
    _plot_scenario_metric_ci(per_run_df, output_dir)
    _plot_scenario_boxplots(per_run_df, output_dir)


def run_experiment(experiment_dir: str, output_dir: str, warmup: int = 0):
    """Analyze one experiment directory (one scenario at a time).

    Expected structure:
      <experiment_dir>/monolith/run_1.jtl
      <experiment_dir>/microservices/run_1.jtl

    If a root directory is passed (contains multiple scenario subdirectories),
    this function generates cross-scenario aggregate outputs from existing
    per-scenario chart summaries.
    """
    os.makedirs(output_dir, exist_ok=True)
    experiment_path = Path(experiment_dir)

    # Root-level cross-scenario aggregation mode.
    monolith_dir = experiment_path / "monolith"
    microservices_dir = experiment_path / "microservices"
    if not monolith_dir.is_dir() and not microservices_dir.is_dir():
        scenario_dirs = discover_scenario_dirs(experiment_path)
        if scenario_dirs:
            print("\nDetected experiment root with scenario directories")
            _generate_cross_scenario_outputs(experiment_path, output_dir)
            print(f"\nAll outputs saved to: {output_dir}")
            return

    scenario_name = experiment_path.name
    per_run_df, monolith_all, microservices_all, monolith_runs, microservices_runs = (
        _analyze_scenario_data(experiment_path, warmup, scenario_name)
    )
    _generate_scenario_outputs(
        per_run_df,
        monolith_all,
        microservices_all,
        monolith_runs,
        microservices_runs,
        output_dir,
    )
    _generate_research_tables(per_run_df, output_dir)

    # Scenario-specialized visuals only when applicable.
    if scenario_name.startswith("pool_exhaustion"):
        _plot_pool_exhaustion_sweep(per_run_df, output_dir)

    print(f"\nAll outputs saved to: {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Benchmark Visualization: Monolith vs Microservices",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze one scenario directory:
  python visualize.py --experiment-dir results/2026-04-10_12-34-56/baseline

  # Analyze experiment root for cross-scenario aggregation:
  python visualize.py --experiment-dir results/2026-04-10_12-34-56

  # With custom output directory:
  python visualize.py --experiment-dir results/2026-04-10_12-34-56 --output results/2026-04-10_12-34-56/charts
        """,
    )
    parser.add_argument(
        "--experiment-dir",
        required=True,
        help="Scenario dir (monolith/run_*.jtl + microservices/run_*.jtl) or experiment root",
    )
    parser.add_argument(
        "--output", default="results/charts", help="Output directory for charts"
    )
    parser.add_argument(
        "--warmup",
        type=int,
        default=0,
        help="Seconds of warmup data to discard from the start (default: 0)",
    )

    args = parser.parse_args()
    print(f"Experiment Directory: {args.experiment_dir}")
    run_experiment(args.experiment_dir, args.output, warmup=args.warmup)


if __name__ == "__main__":
    main()
