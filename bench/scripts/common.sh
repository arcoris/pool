#!/usr/bin/env bash
#
# Shared operational helpers for the benchmark shell layer.
#
# This module is sourced by the entrypoint scripts under bench/scripts/.
# It centralizes:
# - canonical defaults;
# - path-aware artifact naming;
# - benchmark suite resolution;
# - logging and failure helpers;
# - argument and input validation;
# - environment capture helpers.
#
# The intent is to keep the shell layer small and explicit while avoiding
# copy-pasted operational logic in each entrypoint script.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "common.sh is a sourced helper module and must not be executed directly." >&2
  exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths.sh"

# Shared defaults stay here so every entrypoint script can surface the same
# policy in help text and command construction.
readonly DEFAULT_RUN_SUITE="all"
readonly DEFAULT_RUN_COUNT="10"
readonly DEFAULT_RUN_PACKAGES="./..."
readonly DEFAULT_PROFILE_COUNT="1"
readonly DEFAULT_PROFILE_MODE="both"
readonly DEFAULT_COMPARE_FORMAT="text"

readonly DEFAULT_ENV_STEM_PREFIX="env"
readonly DEFAULT_COMPARE_STEM_PREFIX="compare"
readonly DEFAULT_PROFILE_STEM_PREFIX="profile"

readonly SUPPORTED_SUITES_TEXT="all | controlled-serial | realistic-serial | parallel | compare | backend | baselines | paths | shapes | metrics"

# Logging helpers keep error formatting and progress messages consistent across
# the benchmark shell layer.
# log_info prints a lightweight progress line for multi-step workflows.
#
# The shell layer intentionally keeps logging simple. This helper exists so
# orchestration scripts can surface progress without inventing their own output
# format.
log_info() {
  printf 'info: %s\n' "$*" >&2
}

# log_warn prints a non-fatal warning line.
#
# Warnings are expected to be rare, but keeping a dedicated helper avoids
# ad hoc formatting when a script needs to highlight a surprising condition.
log_warn() {
  printf 'warning: %s\n' "$*" >&2
}

# die prints a user-facing error and terminates immediately.
#
# Centralizing failures keeps validation and runtime errors consistent across
# every shell entrypoint.
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Artifact directory creation is explicit and centralized so every script
# writes into the same maintained directory tree.
#
# The directory layout is part of the repository performance workflow, so
# entrypoint scripts should all create the same tree instead of issuing local
# mkdir calls with subtly different path sets.
ensure_artifact_dirs() {
  mkdir -p \
    "${BENCH_RAW_DIR}" \
    "${BENCH_COMPARE_DIR}" \
    "${BENCH_CPU_PROFILES_DIR}" \
    "${BENCH_MEM_PROFILES_DIR}" \
    "${BENCH_CHARTS_DIR}"
}

# Benchmark runs write build cache and temporary files outside the repository
# when the caller did not already define those locations.
#
# This keeps the repository clean and avoids surprising writes to unrelated
# user directories during reproducible benchmark campaigns.
ensure_go_runtime_dirs() {
  if [[ -z "${GOCACHE:-}" ]]; then
    # Prefer a deterministic external cache location unless the caller pinned
    # one explicitly.
    export GOCACHE="${TMPDIR:-/tmp}/arcoris-pool-go-build"
  fi
  if [[ -z "${GOTMPDIR:-}" ]]; then
    # Keep go test temporary files out of the repository worktree.
    export GOTMPDIR="${TMPDIR:-/tmp}/arcoris-pool-go-tmp"
  fi

  mkdir -p "${GOCACHE}" "${GOTMPDIR}"
}

# timestamp_utc returns a filesystem-safe UTC timestamp used in artifact stems.
timestamp_utc() {
  date -u +"%Y%m%dT%H%M%SZ"
}

# Artifact stems are the stable naming unit for raw outputs, comparison
# outputs, and profiles. They are intentionally restricted to filesystem-safe
# characters so scripts do not silently generate nested paths or ambiguous
# file names.
validate_artifact_stem() {
  local stem="$1"

  if [[ ! "${stem}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "invalid artifact stem: ${stem}; use letters, digits, '.', '_' or '-'"
  fi
}

# timestamped_stem applies the repository naming convention:
# <prefix>-<utc timestamp>.
#
# Scripts use the stem as the join key between related artifacts such as one
# raw output, its environment capture, and any follow-up compare output.
timestamped_stem() {
  local prefix="$1"
  printf '%s-%s\n' "${prefix}" "$(timestamp_utc)"
}

# raw_output_path returns the canonical raw benchmark output path for one stem.
#
# Centralizing raw naming keeps collection, comparison, and documentation
# aligned on one artifact convention.
raw_output_path() {
  local stem="$1"
  printf '%s/%s.txt\n' "${BENCH_RAW_DIR}" "${stem}"
}

# raw_env_output_path returns the matching environment-capture path for a raw
# benchmark artifact stem.
#
# The shared stem makes it trivial to pair a raw result with the exact host and
# toolchain context that produced it.
raw_env_output_path() {
  local stem="$1"
  printf '%s/%s.env.txt\n' "${BENCH_RAW_DIR}" "${stem}"
}

# compare_output_path returns the canonical compare-artifact path for one stem
# and one supported format.
#
# The format affects only the extension. The stem remains the stable campaign
# identifier reused by reports and higher-level orchestration.
compare_output_path() {
  local stem="$1"
  local format="$2"
  local extension="txt"

  if [[ "${format}" == "csv" ]]; then
    extension="csv"
  fi

  printf '%s/%s.%s\n' "${BENCH_COMPARE_DIR}" "${stem}" "${extension}"
}

# profile_cpu_output_path returns the CPU profile artifact path for one stem.
#
# CPU and memory profiles are stored in separate directories so consumers do
# not need to infer profile type from the filename alone.
profile_cpu_output_path() {
  local stem="$1"
  printf '%s/%s.prof\n' "${BENCH_CPU_PROFILES_DIR}" "${stem}"
}

# profile_mem_output_path returns the memory profile artifact path for one
# profile stem.
#
# The stem matches the CPU profile and environment capture so one profiling run
# remains a coherent artifact set.
profile_mem_output_path() {
  local stem="$1"
  printf '%s/%s.prof\n' "${BENCH_MEM_PROFILES_DIR}" "${stem}"
}

# profile_env_output_path returns the environment-capture path paired with one
# profiling run.
#
# Profile environment artifacts live under bench/profiles/ because they describe
# a focused profiling session rather than the raw benchmark collection phase.
profile_env_output_path() {
  local stem="$1"
  printf '%s/%s.env.txt\n' "${BENCH_PROFILES_DIR}" "${stem}"
}

# ensure_parent_dir creates the parent directory of one output path.
#
# This matters when a caller overrides the default artifact location with a
# custom path that may not exist yet.
ensure_parent_dir() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
}

# require_command verifies that a required external dependency is present on
# PATH before a script tries to use it.
require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "missing required command: $1"
  fi
}

# require_option_value ensures that a flag expecting a following value really
# got one.
#
# The helper rejects both missing values and the common mistake where the next
# token is another long option.
require_option_value() {
  local option="$1"
  local argc="$2"
  local next_value="${3:-}"

  if (( argc < 2 )) || [[ -z "${next_value}" ]] || [[ "${next_value}" == --* ]]; then
    die "missing value for ${option}"
  fi
}

# validate_non_empty is the narrowest shared string validation helper.
validate_non_empty() {
  local value="$1"
  local what="$2"

  if [[ -z "${value}" ]]; then
    die "${what} must not be empty"
  fi
}

# validate_positive_integer is used for repeat counts and similar numeric
# controls where zero would not make sense.
validate_positive_integer() {
  local value="$1"
  local flag_name="$2"

  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    die "${flag_name} must be a positive integer: got ${value}"
  fi
}

# validate_package_selector checks the raw package selector string before any
# script expands it into shell words.
validate_package_selector() {
  local packages="$1"
  local flag_name="$2"

  validate_non_empty "${packages}" "${flag_name}"
  if [[ "${packages}" == *$'\n'* ]]; then
    die "${flag_name} must be a single shell word or a space-separated package list"
  fi
}

# validate_benchmark_pattern ensures that benchmark selectors are present and
# remain one logical line.
validate_benchmark_pattern() {
  local pattern="$1"
  local flag_name="$2"

  validate_non_empty "${pattern}" "${flag_name}"
  if [[ "${pattern}" == *$'\n'* ]]; then
    die "${flag_name} must be a single-line go test benchmark pattern"
  fi
}

# validate_compare_format restricts compare outputs to the maintained text and
# CSV variants.
validate_compare_format() {
  local format="$1"

  case "${format}" in
    text|csv)
      ;;
    *)
      die "unknown compare format: ${format}; expected text or csv"
      ;;
  esac
}

# validate_profile_mode restricts profile collection to the explicitly
# supported modes.
validate_profile_mode() {
  local mode="$1"

  case "${mode}" in
    cpu|mem|both)
      ;;
    *)
      die "unknown profile mode: ${mode}; expected cpu, mem, or both"
      ;;
  esac
}

# validate_cpu_matrix checks literal CPU matrices after the special "all"
# keyword has already been resolved separately.
validate_cpu_matrix() {
  local matrix="$1"

  if [[ -z "${matrix}" ]]; then
    return
  fi

  if [[ ! "${matrix}" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]]; then
    die "invalid CPU matrix: ${matrix}; expected comma-separated positive integers or 'all'"
  fi
}

# validate_existing_file verifies that an input artifact exists before a script
# tries to consume it.
validate_existing_file() {
  local path="$1"
  local label="$2"

  if [[ ! -f "${path}" ]]; then
    die "${label} file does not exist: ${path}"
  fi
}

# validate_suite_name keeps the public suite vocabulary centralized in one
# shared place.
validate_suite_name() {
  local suite="$1"

  case "${suite}" in
    all|controlled-serial|realistic-serial|parallel|compare|backend|baselines|paths|shapes|metrics)
      ;;
    *)
      die "unknown suite: ${suite}; expected one of: ${SUPPORTED_SUITES_TEXT}"
      ;;
  esac
}

# logical_cpu_count returns the best available estimate of the host's logical
# CPU count using common platform tools.
#
# The helper stays intentionally lightweight because benchmark tooling only
# needs a pragmatic host estimate, not a full hardware inventory subsystem.
logical_cpu_count() {
  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
    return
  fi
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.logicalcpu 2>/dev/null && return
  fi
  echo 1
}

# cpu_model returns a human-readable CPU description for environment capture.
#
# The value is diagnostic metadata rather than a machine-stable identifier, so
# this helper prefers simple best-effort strings over heavy normalization.
cpu_model() {
  if command -v lscpu >/dev/null 2>&1; then
    lscpu | awk -F: '/Model name/ { gsub(/^[ \t]+/, "", $2); print $2; exit }'
    return
  fi
  if [[ -r /proc/cpuinfo ]]; then
    awk -F: '/model name/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo
    return
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null && return
    sysctl -n hw.model 2>/dev/null && return
  fi
  echo "unknown"
}

# The default parallel matrix intentionally spans low, medium, and full-machine
# concurrency points without assuming that every host has the same CPU count.
#
# This is a repository default, not a universal truth. It exists to give
# realistic parallel runs a sensible first-pass sweep without forcing every
# caller to handcraft a machine-specific matrix.
default_parallel_cpu_matrix() {
  local total half
  local values=()

  total="$(logical_cpu_count)"
  half=$(( total / 2 ))

  # add_cpu_candidate keeps the default matrix valid and unique while
  # preserving the intended low/medium/high sweep shape.
  add_cpu_candidate() {
    local candidate="$1"
    local existing

    if (( candidate < 1 || candidate > total )); then
      return
    fi

    for existing in "${values[@]}"; do
      if [[ "${existing}" == "${candidate}" ]]; then
        return
      fi
    done

    values+=("${candidate}")
  }

  add_cpu_candidate 1
  add_cpu_candidate 2
  add_cpu_candidate 4
  # Midpoint and full-machine entries help expose scaling shape changes that
  # single-point serial or 1-CPU parallel runs cannot show.
  add_cpu_candidate "${half}"
  add_cpu_candidate "${total}"

  local joined=""
  local value
  for value in "${values[@]}"; do
    if [[ -n "${joined}" ]]; then
      joined+=","
    fi
    joined+="${value}"
  done

  echo "${joined}"
}

# resolve_cpu_matrix expands the special user-facing "all" selector and
# validates explicit matrices.
#
# Entry-point scripts call this helper so CPU normalization rules stay
# centralized instead of being reimplemented in multiple parsers.
resolve_cpu_matrix() {
  local requested="$1"

  if [[ -z "${requested}" ]]; then
    echo ""
    return
  fi

  if [[ "${requested}" == "all" ]]; then
    logical_cpu_count
    return
  fi

  validate_cpu_matrix "${requested}"
  echo "${requested}"
}

# Benchmark suite names are part of the shell-layer contract. They map one
# human-facing suite selector to one stable go test -bench pattern.
#
# These mappings must stay aligned with docs/performance/. Changing them is a
# repository workflow change, not merely a local shell implementation detail.
suite_pattern() {
  local suite="$1"

  validate_suite_name "${suite}"

  case "${suite}" in
    all)
      # All maintained benchmark families across the repository.
      echo '^(BenchmarkSyncPool_|BenchmarkBaseline_|BenchmarkPaths_|BenchmarkShapes_|BenchmarkParallel_|BenchmarkCompare_|BenchmarkMetrics_)'
      ;;
    controlled-serial)
      # Controlled serial upper-bound cases that bias toward steady-state
      # hot-path measurements instead of broader operational behavior.
      echo '^(BenchmarkSyncPool_ControlledGetPut_(Pointer|Value)|BenchmarkBaseline_Controlled_(RawSyncPool|ARCORISPool)_(Pointer|Value)|BenchmarkPaths_Controlled(Accepted|ResetHeavy)|BenchmarkShapes_Controlled(PointerSmall|PointerWithSlices|ValueSmall|ValueLarge)|BenchmarkMetrics_ControlledAcceptedWarmPath)$'
      ;;
    realistic-serial)
      # Serial scenarios that still exercise misses, admissions, and denials
      # without crossing into parallel scheduler effects.
      echo '^(BenchmarkSyncPool_GetMiss|BenchmarkBaseline_AllocOnly_(Pointer|Value)|BenchmarkPaths_(RealisticAccepted|RealisticRejected|RealisticDropObserved)|BenchmarkShapes_AlwaysOversizedRejected|BenchmarkMetrics_Realistic(RejectedSteadyState|MixedReuse))$'
      ;;
    parallel)
      # Parallel scenarios are isolated because their CPU-matrix defaults and
      # interpretation rules differ from serial suites.
      echo '^(BenchmarkSyncPool_RealisticParallel|BenchmarkParallel_Realistic)'
      ;;
    compare)
      echo '^BenchmarkCompare_'
      ;;
    backend)
      echo '^BenchmarkSyncPool_'
      ;;
    baselines)
      echo '^BenchmarkBaseline_'
      ;;
    paths)
      echo '^BenchmarkPaths_'
      ;;
    shapes)
      echo '^BenchmarkShapes_'
      ;;
    metrics)
      echo '^BenchmarkMetrics_'
      ;;
  esac
}

# Profiling must target exactly one package because go test profile flags do
# not support multi-package runs.
# default_profile_packages infers the profiling package from the benchmark
# family when the caller did not specify one explicitly.
#
# The inference is intentionally conservative: backend benchmark names map to
# the backend package, while all pool-level families default to the root
# package where those benchmarks live.
default_profile_packages() {
  local bench_pattern="$1"

  case "${bench_pattern}" in
    *BenchmarkSyncPool_*)
      echo "./internal/backend"
      ;;
    *)
      echo "./"
      ;;
  esac
}

# validate_profile_packages enforces the one-package invariant required by Go's
# profiling flags.
validate_profile_packages() {
  local packages="$1"

  validate_package_selector "${packages}" "--packages"

  if [[ "${packages}" == *"..."* ]]; then
    die "profile runs must target exactly one package; wildcard patterns are not supported: ${packages}"
  fi

  read -r -a _package_args <<<"${packages}"
  if (( ${#_package_args[@]} != 1 )); then
    die "profile runs must target exactly one package: got ${packages}"
  fi
}

# command_string renders one shell-escaped command line for logs and environment
# capture files.
#
# Shell escaping matters here because artifacts should preserve the exact
# command shape even when selectors or paths contain punctuation.
command_string() {
  printf '%q ' "$@"
}

# Environment capture is intentionally textual and grep-friendly so reports can
# cite it directly and humans can inspect it without extra tooling.
#
# The file uses simple key=value lines because it is meant to be durable,
# scriptable, and easy to diff during report preparation or review.
write_env_capture() {
  local output="$1"
  shift

  ensure_parent_dir "${output}"

  {
    echo "date_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "repository=${REPO_ROOT}"
    # Git metadata is best-effort so archive exports or detached worktrees do
    # not prevent environment capture from being written.
    echo "git_revision=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "go_version=$(go version)"
    echo "goos=$(go env GOOS)"
    echo "goarch=$(go env GOARCH)"
    echo "gocache=${GOCACHE:-default}"
    echo "gotmpdir=${GOTMPDIR:-default}"
    echo "cpu_model=$(cpu_model)"
    echo "logical_cpus=$(logical_cpu_count)"
    echo "gomaxprocs=${GOMAXPROCS:-default}"
    echo "hostname=$(hostname 2>/dev/null || uname -n)"
    echo "uname=$(uname -a)"
    # Store the exact invocation so later compare and reporting steps can see
    # how the artifact was produced without reconstructing command history.
    echo "command=$(command_string "$@")"
  } >"${output}"
}

# log_artifact prints one successful artifact write line.
#
# Scripts call this only after the artifact exists so the message can double as
# a reliable pointer for users and higher-level automation logs.
log_artifact() {
  printf 'wrote %s\n' "$1"
}
