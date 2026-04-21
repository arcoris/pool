
#
# Copyright 2026 The ARCORIS Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
"""
plot_benchmarks.py

Generate repository-friendly SVG benchmark charts from benchmark artifacts.

This script is the chart-generation step of the benchmark workflow used by
`arcoris.dev/pool`. It sits after benchmark collection and comparison:

    benchmark source files -> bench/raw -> bench/compare -> bench/charts

Its responsibility is intentionally narrow:
- read benchmark artifacts that already exist on disk;
- parse either comparison-oriented CSV or raw benchmark snapshots;
- render static chart artifacts as SVG files;
- place those charts under the repository's chart artifact directory.

It does not:
- run benchmarks;
- compare raw benchmark outputs itself;
- interpret benchmark results;
- modify reports;
- infer benchmark methodology from scratch.

The script supports two explicit workflows.

1. Compare mode
   Input:
   - one or more CSV files exported from `benchstat`, or from a controlled
     transformation with a compatible table layout.
   Output:
   - comparison charts with old/new bars and optional delta labels.

2. Snapshot mode
   Input:
   - one or more raw `go test -bench` output files.
   Output:
   - one or more single-snapshot charts grouped by benchmark family and metric.

The script is deliberately explicit about the distinction because compare
charts and snapshot charts answer different presentation needs.

Compare input model
-------------------

Compare mode expects one or more CSV tables. Each table should contain:
- one header row;
- one leading benchmark-name column;
- one "old ..." column;
- one "new ..." column;
- optionally one delta column;
- zero or more benchmark rows.

Multiple tables may appear in one CSV file, separated by blank rows.

Snapshot input model
--------------------

Snapshot mode expects raw benchmark lines compatible with canonical
`go test -bench` output, for example:

    BenchmarkBaseline_AllocOnly_Pointer-12                 1000000    1200 ns/op    256 B/op    2 allocs/op
    BenchmarkBaseline_Controlled_ARCORISPool_Pointer-12    3000000     220 ns/op      0 B/op    0 allocs/op

Supported assumptions for snapshot parsing:
- one benchmark result per line;
- the first field is a benchmark name beginning with `Benchmark`;
- the second field is the iteration count;
- the remaining fields are alternating numeric-value and metric-unit pairs;
- non-benchmark lines such as `goos:`, `pkg:`, `PASS`, and `ok` are ignored.

Raw snapshot collection in this repository intentionally uses repeated runs,
for example `go test -bench ... -count 10`. A single snapshot file therefore
contains multiple samples for the same benchmark and metric. Snapshot charts do
not plot every raw line directly. Instead, snapshot mode:

- groups repeated samples by normalized benchmark name and metric;
- aggregates those repeated values into one representative value;
- uses median by default because it is robust and report-friendly;
- groups the resulting representative rows by benchmark family and metric.

This parser is intentionally conservative. It does not try to infer meaning
from arbitrary text logs or partially malformed benchmark lines.

Output model
------------

For every parsed comparison table or snapshot chart group, the script writes
one or more SVG files to the output chart directory. Snapshot output file names
include the source stem, benchmark family, and metric. Output files are still
chunked when a chart would otherwise contain too many benchmark rows, but
family-plus-metric grouping keeps chunking as a fallback instead of the normal
case.

The generated charts are intentionally simple and GitHub-friendly:
- static SVG by default;
- one figure per compare table or per snapshot family-plus-metric group;
- horizontal bars for readable benchmark labels;
- benchmark names on the Y axis;
- old/new bars plus delta labels in compare mode;
- one value bar per benchmark in snapshot mode.

Repository integration
----------------------

Repository paths are loaded from `bench/scripts/paths.sh`, which is treated as
the single source of truth for benchmark-related repository layout. This keeps
the chart-generation script aligned with the shell tooling layer instead of
recomputing its own path model in Python.

Recommended layout from the canonical shell path layer:
- raw snapshot input: bench/raw/*.txt
- input CSV:  bench/compare/*.csv
- output SVG: bench/charts/*.svg

Typical use:

    python3 bench/scripts/plot_benchmarks.py \
        --mode compare \
        --input bench/compare/baseline-vs-candidate.csv

    python3 bench/scripts/plot_benchmarks.py \
        --mode snapshot \
        --input bench/raw/initial-baseline.txt

    python3 bench/scripts/plot_benchmarks.py \
        --mode snapshot \
        --input bench/raw/initial-baseline.txt \
        --snapshot-aggregate median

    python3 bench/scripts/plot_benchmarks.py \
        --mode snapshot \
        --input bench/raw/*.txt \
        --snapshot-include-compare

Once charts are generated, they can be referenced from:
- README.md
- docs/performance/README.md
- docs/performance/reports/*.md

Implementation notes
--------------------

The script uses matplotlib for chart generation because the repository needs
static, high-quality SVG artifacts that render cleanly on GitHub.

The script loads repository paths by sourcing `paths.sh` in a small Bash
subprocess. If that fails, the script exits with a clear error rather than
silently falling back to a second, duplicated repository layout model.
"""

import argparse
import csv
import glob
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from statistics import mean, median
from typing import Callable, Iterable, List, Optional, Sequence, TypeVar


# ---------------------------------------------------------------------------
# Repository path configuration
# ---------------------------------------------------------------------------

SCRIPT_PATH = Path(__file__).resolve()
PATHS_SH = SCRIPT_PATH.with_name("paths.sh")

SHELL_PATH_VARIABLES = (
    "REPO_ROOT",
    "BENCH_DIR",
    "BENCH_RAW_DIR",
    "BENCH_COMPARE_DIR",
    "BENCH_CHARTS_DIR",
    "DOCS_PERFORMANCE_DIR",
    "REPORTS_DIR",
)

MODE_COMPARE = "compare"
MODE_SNAPSHOT = "snapshot"
DEFAULT_MODE = MODE_COMPARE

DEFAULT_COMPARE_INPUT_GLOB = "*.csv"
DEFAULT_SNAPSHOT_INPUT_GLOB = "*.txt"
DEFAULT_OUTPUT_FORMAT = "svg"
DEFAULT_MAX_ROWS_PER_CHART = 20
DEFAULT_LABEL_FONT_SIZE = 9
DEFAULT_TITLE_FONT_SIZE = 12
DEFAULT_FIGURE_ROW_HEIGHT = 0.48
DEFAULT_FIGURE_MIN_HEIGHT = 2.8
DEFAULT_FIGURE_WIDTH = 12.0
DEFAULT_NUMERIC_PRECISION = 3
EXIT_RENDER_FAILURE = 1
EXIT_CONFIGURATION_FAILURE = 2

SNAPSHOT_AGGREGATE_MEDIAN = "median"
SNAPSHOT_AGGREGATE_MEAN = "mean"
SNAPSHOT_AGGREGATE_MIN = "min"
SNAPSHOT_AGGREGATE_MAX = "max"
SNAPSHOT_AGGREGATION_CHOICES = (
    SNAPSHOT_AGGREGATE_MEDIAN,
    SNAPSHOT_AGGREGATE_MEAN,
    SNAPSHOT_AGGREGATE_MIN,
    SNAPSHOT_AGGREGATE_MAX,
)
DEFAULT_SNAPSHOT_AGGREGATE = SNAPSHOT_AGGREGATE_MEDIAN

SNAPSHOT_FAMILY_BACKEND = "backend"
SNAPSHOT_FAMILY_BASELINES = "baselines"
SNAPSHOT_FAMILY_PATHS = "paths"
SNAPSHOT_FAMILY_SHAPES = "shapes"
SNAPSHOT_FAMILY_PARALLEL = "parallel"
SNAPSHOT_FAMILY_METRICS = "metrics"
SNAPSHOT_FAMILY_COMPARE = "compare"
SNAPSHOT_FAMILY_OTHER = "other"

SNAPSHOT_FAMILY_ORDER = (
    SNAPSHOT_FAMILY_BACKEND,
    SNAPSHOT_FAMILY_BASELINES,
    SNAPSHOT_FAMILY_PATHS,
    SNAPSHOT_FAMILY_SHAPES,
    SNAPSHOT_FAMILY_PARALLEL,
    SNAPSHOT_FAMILY_METRICS,
    SNAPSHOT_FAMILY_COMPARE,
    SNAPSHOT_FAMILY_OTHER,
)

SNAPSHOT_FAMILY_PREFIXES = (
    ("BenchmarkSyncPool_", SNAPSHOT_FAMILY_BACKEND),
    ("BenchmarkBaseline_", SNAPSHOT_FAMILY_BASELINES),
    ("BenchmarkPaths_", SNAPSHOT_FAMILY_PATHS),
    ("BenchmarkShapes_", SNAPSHOT_FAMILY_SHAPES),
    ("BenchmarkParallel_", SNAPSHOT_FAMILY_PARALLEL),
    ("BenchmarkMetrics_", SNAPSHOT_FAMILY_METRICS),
    ("BenchmarkCompare_", SNAPSHOT_FAMILY_COMPARE),
)


@dataclass(frozen=True)
class RepositoryPaths:
    """Canonical repository locations used by the chart-generation script.

    The values come from `bench/scripts/paths.sh`, which remains the repository
    source of truth for benchmark-related path layout.
    """

    repo_root: Path
    bench_dir: Path
    bench_raw_dir: Path
    bench_compare_dir: Path
    bench_charts_dir: Path
    docs_performance_dir: Path
    reports_dir: Path


def _parse_shell_path_output(raw_output: bytes) -> dict[str, Path]:
    """Parse NUL-delimited `name=value` records emitted by the shell loader.

    The Bash side emits one record per exported path variable. NUL separation
    avoids ambiguity if a path ever contains spaces.
    """

    values: dict[str, Path] = {}

    for raw_record in raw_output.split(b"\0"):
        if not raw_record:
            continue

        text = raw_record.decode("utf-8", errors="replace")
        if "=" not in text:
            raise RuntimeError(
                "failed to parse canonical repository paths from paths.sh: "
                f"malformed record {text!r}"
            )

        name, value = text.split("=", 1)
        if not value:
            raise RuntimeError(
                "failed to parse canonical repository paths from paths.sh: "
                f"empty value for {name}"
            )

        path = Path(value)
        if not path.is_absolute():
            raise RuntimeError(
                "failed to parse canonical repository paths from paths.sh: "
                f"{name} is not absolute: {value}"
            )

        values[name] = path

    return values


def load_repository_paths_from_shell() -> RepositoryPaths:
    """Load canonical repository paths from `bench/scripts/paths.sh`.

    `paths.sh` is the single source of truth for repository layout used by the
    benchmark tooling layer. This helper sources that shell module in a small
    Bash subprocess, reads back the exported path variables, and converts them
    into a Python-side configuration object.

    The loader fails explicitly if:
    - `paths.sh` cannot be found;
    - Bash cannot be launched;
    - sourcing `paths.sh` fails;
    - one of the required exported variables is missing or empty.
    """

    if not PATHS_SH.is_file():
        raise RuntimeError(f"canonical shell path module not found: {PATHS_SH}")

    requested_names = " ".join(SHELL_PATH_VARIABLES)
    # The shell side remains intentionally small: source the canonical path
    # module, verify that every required export exists, and emit NUL-delimited
    # key=value records for Python to consume.
    shell_program = f"""
set -euo pipefail
source {shlex.quote(str(PATHS_SH))}
for name in {requested_names}; do
  if [[ -z "${{!name:-}}" ]]; then
    printf 'missing exported variable: %s\\n' "$name" >&2
    exit 1
  fi
  printf '%s=%s\\0' "$name" "${{!name}}"
done
"""

    try:
        result = subprocess.run(
            ["bash", "-lc", shell_program],
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise RuntimeError(
            f"failed to launch bash while loading canonical paths from {PATHS_SH}: {exc}"
        ) from exc

    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        details = stderr or f"shell exited with status {result.returncode}"
        raise RuntimeError(
            f"failed to load canonical repository paths from {PATHS_SH}: {details}"
        )

    values = _parse_shell_path_output(result.stdout)

    missing = [name for name in SHELL_PATH_VARIABLES if name not in values]
    if missing:
        raise RuntimeError(
            "failed to load canonical repository paths from paths.sh: "
            f"missing variables: {', '.join(missing)}"
        )

    return RepositoryPaths(
        repo_root=values["REPO_ROOT"],
        bench_dir=values["BENCH_DIR"],
        bench_raw_dir=values["BENCH_RAW_DIR"],
        bench_compare_dir=values["BENCH_COMPARE_DIR"],
        bench_charts_dir=values["BENCH_CHARTS_DIR"],
        docs_performance_dir=values["DOCS_PERFORMANCE_DIR"],
        reports_dir=values["REPORTS_DIR"],
    )


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class BenchmarkRow:
    """One comparable benchmark row from a comparison table.

    Attributes:
        name: Human-readable benchmark row name.
        old_value: Baseline numeric value.
        new_value: Candidate numeric value.
        delta_label: Optional human-readable delta string as supplied by the
            source table, such as "-12.4%" or "+3.1%".
    """

    name: str
    old_value: float
    new_value: float
    delta_label: Optional[str]


@dataclass(frozen=True)
class ComparisonTable:
    """A parsed comparison table suitable for chart generation.

    Attributes:
        metric_label: Metric title fragment, usually something like
            "time/op", "allocs/op", or "B/op".
        source_stem: Input file stem used as a chart file-name prefix.
        title: Human-readable chart title.
        rows: Comparable rows extracted from the CSV table.
        table_index: Zero-based table index within the input file.
    """

    metric_label: str
    source_stem: str
    title: str
    rows: List[BenchmarkRow]
    table_index: int


@dataclass(frozen=True)
class SnapshotBenchmarkSample:
    """One raw benchmark sample parsed from `go test -bench` output.

    Snapshot files in this repository intentionally contain repeated benchmark
    samples produced by `-count N`. This structure preserves the raw sample
    before any aggregation is applied.

    Attributes:
        name: Benchmark name with the Go benchmark CPU suffix removed.
        family: Repository-specific benchmark family classification.
        iterations: Iteration count reported by the benchmark run.
        metrics: Metric values exactly as they appeared on the line, keyed by
            metric label such as `ns/op`, `B/op`, `allocs/op`, or `news/op`.
    """

    name: str
    family: str
    iterations: int
    metrics: dict[str, float]


@dataclass(frozen=True)
class AggregatedSnapshotMetricRow:
    """One representative benchmark value after collapsing repeated samples.

    Snapshot charts should represent one current benchmark state, not every raw
    `-count` sample separately. This row therefore stores the aggregated value
    for one benchmark and one metric.
    """

    name: str
    family: str
    value: float
    sample_count: int


@dataclass(frozen=True)
class SnapshotChartGroup:
    """One curated snapshot chart group for one family and one metric.

    Snapshot mode first aggregates repeated samples, then groups the resulting
    representative values by repository benchmark family and metric. Each group
    becomes one or more rendered charts depending on row count.
    """

    family: str
    metric_label: str
    source_stem: str
    aggregation_mode: str
    title: str
    rows: List[AggregatedSnapshotMetricRow]


@dataclass(frozen=True)
class TableColumns:
    """Resolved column layout for one benchstat-style comparison table.

    The parser keeps this structure explicit instead of passing around a set of
    loosely related integer indexes. That makes it clearer which columns are
    mandatory and which one is optional.
    """

    name_idx: int
    old_idx: int
    new_idx: int
    delta_idx: Optional[int]


# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------


def build_parser(paths: RepositoryPaths) -> argparse.ArgumentParser:
    """Build the command-line parser for the chart generation script.

    The parser receives shell-derived repository paths so its defaults and help
    text match the rest of the benchmark tooling layer.
    """
    epilog = f"""Examples:
  Compare mode:
    python3 bench/scripts/plot_benchmarks.py \\
      --mode compare \\
      --input {paths.bench_compare_dir}/baseline-vs-candidate.csv

  Snapshot mode:
    python3 bench/scripts/plot_benchmarks.py \\
      --mode snapshot \\
      --input {paths.bench_raw_dir}/initial-baseline.txt

    python3 bench/scripts/plot_benchmarks.py \\
      --mode snapshot \\
      --input {paths.bench_raw_dir}/initial-baseline.txt \\
      --snapshot-aggregate {DEFAULT_SNAPSHOT_AGGREGATE}

  All snapshot files:
    python3 bench/scripts/plot_benchmarks.py \\
      --mode snapshot \\
      --input '{paths.bench_raw_dir}/*.txt'

    python3 bench/scripts/plot_benchmarks.py \\
      --mode snapshot \\
      --input {paths.bench_raw_dir}/initial-baseline.txt \\
      --snapshot-include-compare

Default input locations:
  compare mode:  {paths.bench_compare_dir}/{DEFAULT_COMPARE_INPUT_GLOB}
  snapshot mode: {paths.bench_raw_dir}/{DEFAULT_SNAPSHOT_INPUT_GLOB} (excluding *.env.txt)

Default output directory:
  {paths.bench_charts_dir}
"""
    parser = argparse.ArgumentParser(
        description=(
            "Generate SVG benchmark charts from either compare CSV or curated raw benchmark snapshots."
        ),
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--mode",
        choices=[MODE_COMPARE, MODE_SNAPSHOT],
        default=DEFAULT_MODE,
        help=(
            "Input workflow: compare mode reads benchstat-style CSV; "
            "snapshot mode reads raw go test -bench output, aggregates repeated "
            "samples, and groups charts by benchmark family and metric. "
            f"Default: {DEFAULT_MODE}"
        ),
    )
    parser.add_argument(
        "--input",
        "-i",
        nargs="+",
        required=False,
        help=(
            "One or more input files or glob patterns to plot. "
            "If omitted, the script uses the canonical mode-specific default "
            "under bench/compare/ or bench/raw/."
        ),
    )
    parser.add_argument(
        "--output-dir",
        "-o",
        type=Path,
        default=paths.bench_charts_dir,
        help=(
            "Directory where generated chart files will be written. "
            f"Default: {paths.bench_charts_dir}"
        ),
    )
    parser.add_argument(
        "--format",
        choices=["svg", "png"],
        default=DEFAULT_OUTPUT_FORMAT,
        help="Output image format. SVG is recommended for repository use.",
    )
    parser.add_argument(
        "--max-rows-per-chart",
        type=int,
        default=DEFAULT_MAX_ROWS_PER_CHART,
        help=(
            "Maximum number of benchmark rows per chart. If a table contains more "
            "rows, it will be split into multiple charts."
        ),
    )
    parser.add_argument(
        "--snapshot-aggregate",
        choices=SNAPSHOT_AGGREGATION_CHOICES,
        default=DEFAULT_SNAPSHOT_AGGREGATE,
        help=(
            "Representative value used to collapse repeated raw benchmark samples "
            "in snapshot mode. Default: "
            f"{DEFAULT_SNAPSHOT_AGGREGATE}"
        ),
    )
    parser.add_argument(
        "--snapshot-include-compare",
        action="store_true",
        help=(
            "Include BenchmarkCompare_* families in snapshot charts. "
            "By default they are excluded because compare benches are grouping "
            "surfaces rather than current-state snapshot evidence."
        ),
    )
    parser.add_argument(
        "--title-prefix",
        default="",
        help="Optional title prefix prepended to every generated chart title.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed progress information.",
    )
    return parser


# ---------------------------------------------------------------------------
# Input discovery
# ---------------------------------------------------------------------------


def expand_input_pattern(pattern: str) -> List[Path]:
    """Expand one CLI input token into candidate artifact paths.

    The chart script accepts either:
    - a literal file path; or
    - a glob pattern such as `bench/compare/*.csv` or `bench/raw/*.txt`.

    Python's `glob` module is used here instead of `Path.glob()` because the
    repository tooling allows both relative and absolute patterns.
    """

    if any(ch in pattern for ch in "*?[]"):
        return [Path(match) for match in glob.glob(pattern)]
    return [Path(pattern)]


def is_compare_input_file(path: Path) -> bool:
    """Return whether one path is a supported compare-mode input file."""

    return path.suffix.lower() == ".csv"


def is_snapshot_input_file(path: Path) -> bool:
    """Return whether one path is a supported snapshot-mode input file.

    Snapshot mode targets raw benchmark output artifacts. Matching
    environment-capture files such as `*.env.txt` are intentionally excluded.
    """

    return path.suffix.lower() == ".txt" and not path.name.endswith(".env.txt")


def resolve_mode_input_paths(
    mode: str,
    patterns: Optional[Sequence[str]],
    *,
    paths: RepositoryPaths,
) -> List[Path]:
    """Resolve mode-specific CLI inputs into a stable list of existing files.

    The resolution rules are intentionally explicit:
    - compare mode defaults to the canonical compare directory and accepts CSV;
    - snapshot mode defaults to the canonical raw directory and accepts raw
      benchmark text files, excluding environment captures.
    """

    if mode == MODE_COMPARE:
        default_patterns = [str(paths.bench_compare_dir / DEFAULT_COMPARE_INPUT_GLOB)]
        predicate = is_compare_input_file
    elif mode == MODE_SNAPSHOT:
        default_patterns = [str(paths.bench_raw_dir / DEFAULT_SNAPSHOT_INPUT_GLOB)]
        predicate = is_snapshot_input_file
    else:
        raise RuntimeError(f"unsupported chart mode: {mode}")

    raw_patterns = list(patterns) if patterns else default_patterns

    resolved: List[Path] = []
    seen: set[Path] = set()

    for pattern in raw_patterns:
        for match in expand_input_pattern(pattern):
            path = match.resolve()
            if not path.exists() or path.is_dir():
                continue
            if not predicate(path):
                continue
            if path in seen:
                continue
            seen.add(path)
            resolved.append(path)

    resolved.sort()
    return resolved


# ---------------------------------------------------------------------------
# CSV parsing helpers
# ---------------------------------------------------------------------------


def split_csv_tables(rows: Iterable[List[str]]) -> List[List[List[str]]]:
    """Split a CSV stream into logical tables separated by blank rows.

    Benchstat-style CSV output may contain multiple tables in one file. The
    simplest portable delimiter across CSV readers is a fully blank row.
    """
    tables: List[List[List[str]]] = []
    current: List[List[str]] = []

    for row in rows:
        normalized = [cell.strip() for cell in row]
        if not any(normalized):
            if current:
                tables.append(current)
                current = []
            continue
        current.append(normalized)

    if current:
        tables.append(current)

    return tables


_METRIC_FROM_HEADER_RE = re.compile(r"name\s*\\\s*(.+)$", re.IGNORECASE)


def detect_metric_label(header: Sequence[str]) -> str:
    """Detect a human-readable metric label from a CSV header row.

    Preferred sources, in order:
    1. first cell of form "name \\ time/op"
    2. old/new columns such as "old time/op" or "new allocs/op"
    3. fallback string "metric"
    """
    if not header:
        return "metric"

    first = header[0].strip()
    match = _METRIC_FROM_HEADER_RE.match(first)
    if match:
        return sanitize_metric_label(match.group(1).strip())

    for cell in header[1:]:
        lowered = cell.strip().lower()
        if lowered.startswith("old "):
            return sanitize_metric_label(cell.strip()[4:])
        if lowered.startswith("new "):
            return sanitize_metric_label(cell.strip()[4:])

    return "metric"


def sanitize_metric_label(label: str) -> str:
    """Normalize a metric label for display and file naming.

    This keeps user-facing titles readable while ensuring stable chart names.
    """
    return re.sub(r"\s+", " ", label).strip() or "metric"


def find_column_index(
    header: Sequence[str], predicate: Callable[[str], bool]
) -> Optional[int]:
    """Return the first column index whose stripped text matches predicate.

    The CSV parser uses a predicate-based helper instead of hard-coding exact
    header positions because benchstat CSV may vary slightly in surrounding
    columns while still preserving the old/new naming pattern.
    """
    for idx, cell in enumerate(header):
        if predicate(cell.strip()):
            return idx
    return None


_NUMBER_RE = re.compile(r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")


def parse_numeric_cell(cell: str) -> Optional[float]:
    """Extract a numeric value from a benchstat-style cell.

    Cells may contain values such as:
    - "38.21"
    - "38.21 ± 2%"
    - "1.23e+06"

    The function extracts the first numeric token and converts it to float.
    If no numeric token is present, it returns None.
    """
    match = _NUMBER_RE.search(cell)
    if not match:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def detect_table_columns(header: Sequence[str]) -> Optional[TableColumns]:
    """Resolve the mandatory old/new layout of one comparison table header.

    The repository intentionally supports a narrow CSV shape:
    - the benchmark name is the first column;
    - one `old ...` column must exist;
    - one `new ...` column must exist;
    - one `delta` column may exist.

    Tables outside this shape are ignored rather than interpreted heuristically.
    """

    if len(header) < 3:
        return None

    old_idx = find_column_index(header, lambda c: c.lower().startswith("old "))
    new_idx = find_column_index(header, lambda c: c.lower().startswith("new "))
    delta_idx = find_column_index(header, lambda c: c.lower() == "delta")

    if old_idx is None or new_idx is None:
        return None

    return TableColumns(
        name_idx=0,
        old_idx=old_idx,
        new_idx=new_idx,
        delta_idx=delta_idx,
    )


def parse_comparison_table(
    raw_table: List[List[str]], *, source_stem: str, table_index: int
) -> Optional[ComparisonTable]:
    """Parse one logical CSV table into a ComparisonTable.

    The parser intentionally supports a narrow, repository-friendly subset:
    - one row-name column;
    - one old-value column;
    - one new-value column;
    - optional delta column.

    Tables that do not match this model are skipped rather than guessed at
    aggressively.
    """
    if not raw_table:
        return None

    header = raw_table[0]
    columns = detect_table_columns(header)
    if columns is None:
        return None

    metric = detect_metric_label(header)
    rows: List[BenchmarkRow] = []

    for raw_row in raw_table[1:]:
        if len(raw_row) <= max(columns.name_idx, columns.old_idx, columns.new_idx):
            continue

        name = raw_row[columns.name_idx].strip()
        if not name:
            continue

        old_value = parse_numeric_cell(raw_row[columns.old_idx])
        new_value = parse_numeric_cell(raw_row[columns.new_idx])
        if old_value is None or new_value is None:
            continue

        delta_label = None
        if columns.delta_idx is not None and columns.delta_idx < len(raw_row):
            text = raw_row[columns.delta_idx].strip()
            delta_label = text or None

        rows.append(
            BenchmarkRow(
                name=name,
                old_value=old_value,
                new_value=new_value,
                delta_label=delta_label,
            )
        )

    if not rows:
        return None

    title = f"{source_stem}: {metric}"
    return ComparisonTable(metric_label=metric, source_stem=source_stem, title=title, rows=rows, table_index=table_index)


# ---------------------------------------------------------------------------
# Raw benchmark snapshot parsing
# ---------------------------------------------------------------------------


_RAW_BENCHMARK_CPU_SUFFIX_RE = re.compile(r"-\d+$")

SNAPSHOT_METRIC_PRIORITY = (
    "ns/op",
    "time/op",
    "B/op",
    "bytes/op",
    "allocs/op",
    "news/op",
    "drops/op",
    "reuse_denials/op",
)


def normalize_raw_benchmark_name(raw_name: str) -> str:
    """Strip the trailing Go CPU suffix from one raw benchmark name.

    Raw benchmark output encodes the current CPU count as the final `-N`
    suffix. That suffix is useful in the raw artifact but usually not useful in
    chart labels, where the benchmark identity should stay stable across hosts.
    """

    return _RAW_BENCHMARK_CPU_SUFFIX_RE.sub("", raw_name)


def parse_numeric_token(token: str) -> Optional[float]:
    """Parse one raw metric token from benchmark output.

    Raw benchmark output uses machine-oriented numeric tokens rather than the
    richer benchstat cells parsed elsewhere in this script. The token must be a
    standalone numeric literal, not free-form text.
    """

    try:
        return float(token)
    except ValueError:
        return None


def parse_snapshot_metric_pairs(metric_tokens: Sequence[str]) -> dict[str, float]:
    """Parse alternating raw benchmark metric tokens into a metric map.

    Supported shape:
    - value1 unit1 value2 unit2 ...

    The parser rejects odd token counts and duplicate metric labels so chart
    generation does not silently guess which value belongs to which metric.
    """

    if not metric_tokens or len(metric_tokens) % 2 != 0:
        raise ValueError(
            "expected alternating metric value and unit pairs after the iteration count"
        )

    metrics: dict[str, float] = {}

    for index in range(0, len(metric_tokens), 2):
        raw_value = metric_tokens[index]
        metric_label = metric_tokens[index + 1].strip()

        value = parse_numeric_token(raw_value)
        if value is None:
            raise ValueError(f"unsupported metric value token: {raw_value!r}")
        if not metric_label:
            raise ValueError("encountered an empty metric label")
        if metric_label in metrics:
            raise ValueError(f"duplicate metric label in one benchmark row: {metric_label}")

        metrics[metric_label] = value

    return metrics


def classify_snapshot_benchmark_family(benchmark_name: str) -> str:
    """Classify one benchmark into the repository's snapshot chart families.

    Snapshot charts are repository-specific presentation artifacts, not generic
    benchmark dashboards. The family model therefore follows the benchmark
    naming contract used by this repository's benchmark suites.

    Unknown benchmark prefixes are assigned to `other` instead of being merged
    silently into an unrelated family.
    """

    for prefix, family in SNAPSHOT_FAMILY_PREFIXES:
        if benchmark_name.startswith(prefix):
            return family
    return SNAPSHOT_FAMILY_OTHER


def parse_snapshot_benchmark_line(line: str) -> Optional[SnapshotBenchmarkSample]:
    """Parse one raw `go test -bench` result line.

    Non-benchmark lines are ignored by returning None. Benchmark-like lines
    with unsupported shapes raise `ValueError` so the caller can report a clear
    problem instead of silently treating the file as empty.
    """

    stripped = line.strip()
    if not stripped or not stripped.startswith("Benchmark"):
        return None

    tokens = stripped.split()
    if len(tokens) < 4:
        raise ValueError(
            "benchmark line is too short; expected name, iterations, and at least one metric pair"
        )

    benchmark_name = tokens[0]
    iteration_token = tokens[1]

    if not iteration_token.isdigit():
        raise ValueError(
            "benchmark iteration field is not a positive integer: "
            f"{iteration_token!r}"
        )

    metrics = parse_snapshot_metric_pairs(tokens[2:])
    normalized_name = normalize_raw_benchmark_name(benchmark_name)
    return SnapshotBenchmarkSample(
        name=normalized_name,
        family=classify_snapshot_benchmark_family(normalized_name),
        iterations=int(iteration_token),
        metrics=metrics,
    )


def order_snapshot_metric_labels(rows: Sequence[SnapshotBenchmarkSample]) -> List[str]:
    """Return snapshot metric labels in repository-friendly chart order.

    Core metrics come first so raw snapshot output consistently starts with the
    most commonly cited benchmark dimensions:
    - time
    - bytes
    - allocations
    - repository-specific per-op counters

    Additional metrics keep first-seen order after that priority block.
    """

    first_seen: dict[str, int] = {}

    for row in rows:
        for metric_label in row.metrics:
            if metric_label not in first_seen:
                first_seen[metric_label] = len(first_seen)

    priority_index = {
        label: index for index, label in enumerate(SNAPSHOT_METRIC_PRIORITY)
    }

    return sorted(
        first_seen,
        key=lambda label: (
            priority_index.get(label, len(priority_index)),
            first_seen[label],
        ),
    )


def aggregate_snapshot_values(values: Sequence[float], aggregation_mode: str) -> float:
    """Collapse repeated raw snapshot values into one representative number.

    Raw snapshot files intentionally contain repeated samples from `-count`.
    Snapshot charts should show one representative benchmark state, not every
    sample line. Median is the default because it is robust to outliers and is
    generally the most report-friendly summary for repeated microbenchmark runs.
    """

    if not values:
        raise ValueError("cannot aggregate an empty snapshot value set")

    if aggregation_mode == SNAPSHOT_AGGREGATE_MEDIAN:
        return float(median(values))
    if aggregation_mode == SNAPSHOT_AGGREGATE_MEAN:
        return float(mean(values))
    if aggregation_mode == SNAPSHOT_AGGREGATE_MIN:
        return float(min(values))
    if aggregation_mode == SNAPSHOT_AGGREGATE_MAX:
        return float(max(values))

    raise ValueError(f"unsupported snapshot aggregation mode: {aggregation_mode}")


def order_snapshot_families(samples: Sequence[SnapshotBenchmarkSample]) -> List[str]:
    """Return families in the repository's preferred snapshot-chart order."""

    present = {sample.family for sample in samples}
    priority = {family: index for index, family in enumerate(SNAPSHOT_FAMILY_ORDER)}

    return sorted(
        present,
        key=lambda family: (
            priority.get(family, len(priority)),
            family,
        ),
    )


def build_snapshot_chart_groups(
    samples: Sequence[SnapshotBenchmarkSample],
    *,
    source_stem: str,
    aggregation_mode: str,
    include_compare: bool,
) -> tuple[List[SnapshotChartGroup], List[str]]:
    """Build curated family-plus-metric snapshot groups from raw samples.

    The pipeline is intentionally explicit:

    raw benchmark lines
    -> parsed samples
    -> grouped by benchmark name and metric
    -> repeated values aggregated
    -> grouped by family and metric
    -> rendered, with chunking only as a fallback for large groups

    Compare-family benchmarks are excluded by default because they are report
    grouping surfaces and would otherwise pollute current-state snapshot charts.
    """

    filtered_samples: List[SnapshotBenchmarkSample] = []
    unknown_benchmarks: List[str] = []
    unknown_seen: set[str] = set()

    for sample in samples:
        if sample.family == SNAPSHOT_FAMILY_COMPARE and not include_compare:
            continue
        filtered_samples.append(sample)

        if sample.family == SNAPSHOT_FAMILY_OTHER and sample.name not in unknown_seen:
            unknown_seen.add(sample.name)
            unknown_benchmarks.append(sample.name)

    if not filtered_samples:
        return [], unknown_benchmarks

    metric_order = order_snapshot_metric_labels(filtered_samples)
    metric_priority = {label: index for index, label in enumerate(metric_order)}

    benchmark_first_seen: dict[tuple[str, str], int] = {}
    aggregated_values: dict[tuple[str, str, str], List[float]] = {}

    for sample in filtered_samples:
        benchmark_key = (sample.family, sample.name)
        if benchmark_key not in benchmark_first_seen:
            benchmark_first_seen[benchmark_key] = len(benchmark_first_seen)

        for metric_label, value in sample.metrics.items():
            key = (sample.family, metric_label, sample.name)
            aggregated_values.setdefault(key, []).append(value)

    rows_by_group: dict[tuple[str, str], List[AggregatedSnapshotMetricRow]] = {}
    for (family, metric_label, benchmark_name), values in aggregated_values.items():
        rows_by_group.setdefault((family, metric_label), []).append(
            AggregatedSnapshotMetricRow(
                name=benchmark_name,
                family=family,
                value=aggregate_snapshot_values(values, aggregation_mode),
                sample_count=len(values),
            )
        )

    groups: List[SnapshotChartGroup] = []
    for family in order_snapshot_families(filtered_samples):
        family_metric_labels = sorted(
            {
                metric_label
                for grouped_family, metric_label in rows_by_group
                if grouped_family == family
            },
            key=lambda label: (
                metric_priority.get(label, len(metric_priority)),
                label,
            ),
        )

        for metric_label in family_metric_labels:
            rows = rows_by_group[(family, metric_label)]
            rows.sort(key=lambda row: benchmark_first_seen[(row.family, row.name)])

            groups.append(
                SnapshotChartGroup(
                    family=family,
                    metric_label=metric_label,
                    source_stem=source_stem,
                    aggregation_mode=aggregation_mode,
                    title=(
                        f"{source_stem}: {family} {metric_label} snapshot "
                        f"({aggregation_mode})"
                    ),
                    rows=rows,
                )
            )

    return groups, unknown_benchmarks


# ---------------------------------------------------------------------------
# Chart rendering
# ---------------------------------------------------------------------------


RowT = TypeVar("RowT")


def chunk_rows(rows: Sequence[RowT], chunk_size: int) -> List[List[RowT]]:
    """Split table rows into chart-sized chunks.

    Long tables quickly become unreadable on GitHub. Chunking keeps output files
    usable in repository documentation.
    """
    if chunk_size <= 0:
        raise ValueError("chunk_size must be positive")
    return [list(rows[i : i + chunk_size]) for i in range(0, len(rows), chunk_size)]


def sanitize_filename_component(text: str) -> str:
    """Convert arbitrary text into a repository-safe file-name fragment."""
    slug = text.lower().strip()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug or "chart"


def metric_filename_component(metric_label: str) -> str:
    """Return a stable file-name fragment for one metric label.

    Snapshot and compare artifacts should be easy to reference from Markdown.
    Known metric aliases are normalized to readable names such as `time-op` and
    `bytes-op`, while unknown metrics fall back to generic sanitization.
    """

    aliases = {
        "time/op": "time-op",
        "ns/op": "time-op",
        "b/op": "bytes-op",
        "bytes/op": "bytes-op",
        "allocs/op": "allocs-op",
        "news/op": "news-op",
        "drops/op": "drops-op",
        "reuse_denials/op": "reuse-denials-op",
    }

    normalized = metric_label.strip().lower()
    return aliases.get(normalized, sanitize_filename_component(metric_label))


def build_compare_output_path(
    table: ComparisonTable,
    *,
    chunk_index: int,
    output_dir: Path,
    output_format: str,
) -> Path:
    """Build a stable output path for one compare-mode chart chunk."""

    source_part = sanitize_filename_component(table.source_stem)
    metric_part = metric_filename_component(table.metric_label)
    stem = f"{source_part}-{metric_part}"
    if table.table_index > 0:
        stem += f"-table-{table.table_index+1}"
    if chunk_index > 0:
        stem += f"-part-{chunk_index+1}"
    return output_dir / f"{stem}.{output_format}"


def build_snapshot_output_path(
    table: SnapshotChartGroup,
    *,
    chunk_index: int,
    output_dir: Path,
    output_format: str,
) -> Path:
    """Build a stable output path for one snapshot-mode chart chunk.

    Snapshot artifacts include the source stem, benchmark family, and metric so
    they can be referenced directly from Markdown without requiring surrounding
    prose to explain what each chart contains.
    """

    source_part = sanitize_filename_component(table.source_stem)
    family_part = sanitize_filename_component(table.family)
    metric_part = metric_filename_component(table.metric_label)
    stem = f"{source_part}-{family_part}-{metric_part}"
    if chunk_index > 0:
        stem += f"-part-{chunk_index+1}"
    return output_dir / f"{stem}.{output_format}"


def format_value(value: float) -> str:
    """Format a bar value compactly for annotation.

    Values are rendered in a compact human-readable decimal form because the
    output is intended for charts and markdown reports rather than raw numeric
    interchange.
    """
    if value == 0:
        return "0"
    if abs(value) >= 1_000_000:
        return f"{value/1_000_000:.2f}M"
    if abs(value) >= 1_000:
        return f"{value/1_000:.2f}k"
    if abs(value) >= 100:
        return f"{value:.1f}"
    if abs(value) >= 10:
        return f"{value:.2f}"
    return f"{value:.{DEFAULT_NUMERIC_PRECISION}f}"


@lru_cache(maxsize=1)
def load_matplotlib_pyplot():
    """Load matplotlib lazily and cache the plotting module.

    The chart script keeps `matplotlib` out of module-import time so
    `--help`, path loading, and static checks still work in environments where
    the plotting dependency is absent. Once rendering is actually requested,
    the import is performed once and cached for the remainder of the process.
    """

    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "matplotlib is required to generate benchmark charts; "
            "install it and rerun plot_benchmarks.py"
        ) from exc

    return plt


def render_compare_chart(
    table: ComparisonTable,
    rows: Sequence[BenchmarkRow],
    *,
    output_path: Path,
    title_prefix: str,
) -> None:
    """Render one horizontal grouped-bar comparison chart.

    The chart is deliberately conservative and GitHub-friendly:
    - readable benchmark names on the Y axis;
    - two bars per benchmark row: old and new;
    - optional delta annotations at the right edge;
    - no custom color palette or styling framework.
    """
    plt = load_matplotlib_pyplot()

    # Reverse once at the row level so all later attribute extraction follows
    # the same display order. The first benchmark should appear at the top.
    display_rows = list(reversed(rows))
    names = [row.name for row in display_rows]
    old_values = [row.old_value for row in display_rows]
    new_values = [row.new_value for row in display_rows]
    deltas = [row.delta_label for row in display_rows]

    count = len(rows)
    fig_height = max(DEFAULT_FIGURE_MIN_HEIGHT, DEFAULT_FIGURE_ROW_HEIGHT * count + 1.8)
    fig, ax = plt.subplots(figsize=(DEFAULT_FIGURE_WIDTH, fig_height))

    positions = list(range(count))
    half_bar = 0.18

    ax.barh([p - half_bar for p in positions], old_values, height=0.32, label="old")
    ax.barh([p + half_bar for p in positions], new_values, height=0.32, label="new")

    ax.set_yticks(positions)
    ax.set_yticklabels(names, fontsize=DEFAULT_LABEL_FONT_SIZE)
    ax.set_xlabel(table.metric_label)

    title = table.title
    if title_prefix:
        title = f"{title_prefix} — {title}"
    ax.set_title(title, fontsize=DEFAULT_TITLE_FONT_SIZE)

    # Chart limits reserve extra room for per-bar value annotations and, when
    # present, right-edge delta labels.
    max_value = max(max(old_values), max(new_values), 0.0)
    if max_value <= 0:
        max_value = 1.0

    right_margin = 1.22 if any(deltas) else 1.12
    ax.set_xlim(0, max_value * right_margin)
    ax.legend(loc="lower right")
    ax.grid(axis="x", alpha=0.25)

    for idx, (old_v, new_v, delta) in enumerate(zip(old_values, new_values, deltas)):
        ax.text(
            old_v,
            idx - half_bar,
            f" {format_value(old_v)}",
            va="center",
            ha="left",
            fontsize=8,
        )
        ax.text(
            new_v,
            idx + half_bar,
            f" {format_value(new_v)}",
            va="center",
            ha="left",
            fontsize=8,
        )
        if delta:
            ax.text(
                max_value * 1.03,
                idx,
                delta,
                va="center",
                ha="left",
                fontsize=8,
            )

    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, format=output_path.suffix.lstrip("."), bbox_inches="tight")
    plt.close(fig)


def render_snapshot_chart(
    table: SnapshotChartGroup,
    rows: Sequence[AggregatedSnapshotMetricRow],
    *,
    output_path: Path,
    title_prefix: str,
) -> None:
    """Render one horizontal single-snapshot chart for one metric.

    Snapshot mode answers a different presentation question than compare mode:
    what is the representative current state of one benchmark family for one
    metric?

    By the time this renderer runs, repeated raw samples have already been
    aggregated. The chart therefore renders one representative value per
    benchmark row and keeps the axis and title explicitly tied to one family
    and one metric.
    """

    plt = load_matplotlib_pyplot()

    display_rows = list(reversed(rows))
    names = [row.name for row in display_rows]
    values = [row.value for row in display_rows]

    count = len(rows)
    fig_height = max(DEFAULT_FIGURE_MIN_HEIGHT, DEFAULT_FIGURE_ROW_HEIGHT * count + 1.4)
    fig, ax = plt.subplots(figsize=(DEFAULT_FIGURE_WIDTH, fig_height))

    positions = list(range(count))
    ax.barh(positions, values, height=0.42, label=table.metric_label)

    ax.set_yticks(positions)
    ax.set_yticklabels(names, fontsize=DEFAULT_LABEL_FONT_SIZE)
    ax.set_xlabel(table.metric_label)

    title = table.title
    if title_prefix:
        title = f"{title_prefix} — {title}"
    ax.set_title(title, fontsize=DEFAULT_TITLE_FONT_SIZE)

    max_value = max(max(values), 0.0)
    if max_value <= 0:
        max_value = 1.0
    ax.set_xlim(0, max_value * 1.12)
    ax.grid(axis="x", alpha=0.25)

    for idx, value in enumerate(values):
        ax.text(
            value,
            idx,
            f" {format_value(value)}",
            va="center",
            ha="left",
            fontsize=8,
        )

    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, format=output_path.suffix.lstrip("."), bbox_inches="tight")
    plt.close(fig)


# ---------------------------------------------------------------------------
# Main workflow
# ---------------------------------------------------------------------------


def load_tables_from_csv(path: Path) -> List[ComparisonTable]:
    """Load all parsable comparison tables from one CSV file.

    Unrecognized tables are ignored rather than causing the whole file to fail.
    This lets the script tolerate mildly heterogeneous compare CSV while still
    remaining conservative about what it turns into charts.
    """
    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh)
        raw_tables = split_csv_tables(reader)

    parsed: List[ComparisonTable] = []
    for index, raw_table in enumerate(raw_tables):
        table = parse_comparison_table(
            raw_table,
            source_stem=path.stem,
            table_index=index,
        )
        if table is not None:
            parsed.append(table)
    return parsed


def load_snapshot_samples_from_raw(path: Path) -> List[SnapshotBenchmarkSample]:
    """Load all parsable benchmark samples from one raw benchmark artifact.

    The file may contain ordinary `go test` preamble and epilogue lines such
    as `goos`, `pkg`, `PASS`, and `ok`. Only canonical benchmark result lines
    are turned into samples. If no such rows are found, the function raises a
    clear error instead of silently treating the file as a valid empty snapshot.
    """

    rows: List[SnapshotBenchmarkSample] = []
    parse_errors: List[str] = []

    with path.open("r", encoding="utf-8") as fh:
        for line_number, raw_line in enumerate(fh, start=1):
            try:
                row = parse_snapshot_benchmark_line(raw_line)
            except ValueError as exc:
                if raw_line.lstrip().startswith("Benchmark"):
                    parse_errors.append(f"line {line_number}: {exc}")
                continue

            if row is not None:
                rows.append(row)

    if rows:
        return rows

    if parse_errors:
        raise RuntimeError(
            f"no benchmark rows found in snapshot input {path}; "
            f"first parse error: {parse_errors[0]}"
        )

    raise RuntimeError(f"no benchmark rows found in snapshot input {path}")


def log(verbose: bool, message: str) -> None:
    """Emit a progress log line when verbose mode is enabled."""
    if verbose:
        print(message)


def run_compare_mode(
    input_paths: Sequence[Path],
    *,
    output_dir: Path,
    output_format: str,
    max_rows_per_chart: int,
    title_prefix: str,
    verbose: bool,
) -> int:
    """Generate compare charts from benchstat-style CSV input files."""

    generated = 0

    for input_path in input_paths:
        log(verbose, f"loading compare input {input_path}")
        tables = load_tables_from_csv(input_path)
        if not tables:
            print(
                f"warning: no comparable tables found in compare input {input_path}",
                file=sys.stderr,
            )
            continue

        for table in tables:
            chunks = chunk_rows(table.rows, max_rows_per_chart)
            for chunk_index, chunk in enumerate(chunks):
                output_path = build_compare_output_path(
                    table,
                    chunk_index=chunk_index,
                    output_dir=output_dir,
                    output_format=output_format,
                )
                render_compare_chart(
                    table,
                    chunk,
                    output_path=output_path,
                    title_prefix=title_prefix,
                )
                generated += 1
                log(verbose, f"wrote {output_path}")

    if generated == 0:
        print("warning: no compare charts were generated", file=sys.stderr)
        return EXIT_RENDER_FAILURE

    print(f"generated {generated} compare chart(s) in {output_dir}")
    return 0


def run_snapshot_mode(
    input_paths: Sequence[Path],
    *,
    output_dir: Path,
    output_format: str,
    max_rows_per_chart: int,
    snapshot_aggregate: str,
    snapshot_include_compare: bool,
    title_prefix: str,
    verbose: bool,
) -> int:
    """Generate curated family-plus-metric charts from raw snapshot files."""

    generated = 0

    for input_path in input_paths:
        log(verbose, f"loading snapshot input {input_path}")
        try:
            samples = load_snapshot_samples_from_raw(input_path)
        except RuntimeError as exc:
            print(f"warning: {exc}", file=sys.stderr)
            continue

        groups, unknown_benchmarks = build_snapshot_chart_groups(
            samples,
            source_stem=input_path.stem,
            aggregation_mode=snapshot_aggregate,
            include_compare=snapshot_include_compare,
        )
        if unknown_benchmarks:
            preview = ", ".join(unknown_benchmarks[:3])
            if len(unknown_benchmarks) > 3:
                preview += ", ..."
            print(
                f"warning: snapshot input {input_path} contains unclassified "
                f"benchmark families grouped under 'other': {preview}",
                file=sys.stderr,
            )

        if not groups:
            print(
                f"warning: no snapshot chart groups could be built from {input_path}",
                file=sys.stderr,
            )
            continue

        for group in groups:
            chunks = chunk_rows(group.rows, max_rows_per_chart)
            for chunk_index, chunk in enumerate(chunks):
                output_path = build_snapshot_output_path(
                    group,
                    chunk_index=chunk_index,
                    output_dir=output_dir,
                    output_format=output_format,
                )
                render_snapshot_chart(
                    group,
                    chunk,
                    output_path=output_path,
                    title_prefix=title_prefix,
                )
                generated += 1
                log(verbose, f"wrote {output_path}")

    if generated == 0:
        print("warning: no snapshot charts were generated", file=sys.stderr)
        return EXIT_RENDER_FAILURE

    print(f"generated {generated} snapshot chart(s) in {output_dir}")
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI entrypoint for benchmark chart generation."""
    try:
        paths = load_repository_paths_from_shell()
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_CONFIGURATION_FAILURE

    parser = build_parser(paths)
    args = parser.parse_args(argv)

    input_paths = resolve_mode_input_paths(
        args.mode,
        args.input,
        paths=paths,
    )
    if not input_paths:
        parser.error(f"no {args.mode} input files were found")

    if args.max_rows_per_chart <= 0:
        parser.error("--max-rows-per-chart must be greater than zero")

    output_dir = args.output_dir.resolve()
    if output_dir.exists() and not output_dir.is_dir():
        parser.error(f"--output-dir must be a directory path: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    log(
        args.verbose,
        (
            f"mode={args.mode} inputs={len(input_paths)} output_dir={output_dir} "
            f"snapshot_aggregate={args.snapshot_aggregate} "
            f"snapshot_include_compare={args.snapshot_include_compare}"
        ),
    )

    try:
        if args.mode == MODE_COMPARE:
            return run_compare_mode(
                input_paths,
                output_dir=output_dir,
                output_format=args.format,
                max_rows_per_chart=args.max_rows_per_chart,
                title_prefix=args.title_prefix,
                verbose=args.verbose,
            )
        if args.mode == MODE_SNAPSHOT:
            return run_snapshot_mode(
                input_paths,
                output_dir=output_dir,
                output_format=args.format,
                max_rows_per_chart=args.max_rows_per_chart,
                snapshot_aggregate=args.snapshot_aggregate,
                snapshot_include_compare=args.snapshot_include_compare,
                title_prefix=args.title_prefix,
                verbose=args.verbose,
            )
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_CONFIGURATION_FAILURE

    parser.error(f"unsupported mode: {args.mode}")
    return EXIT_CONFIGURATION_FAILURE


if __name__ == "__main__":
    raise SystemExit(main())
