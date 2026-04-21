#!/usr/bin/env bash
set -euo pipefail

# Run benchmark suites and capture raw output plus matching environment data.
#
# What this script does:
# - resolves one benchmark suite or an explicit benchmark pattern;
# - builds the canonical go test command for benchmark collection;
# - writes raw output under bench/raw/;
# - writes matching environment metadata under bench/raw/.
#
# What this script does not do:
# - it does not compare two runs;
# - it does not collect CPU or memory profiles;
# - it does not interpret benchmark results.
#
# Inputs:
# - benchmark suite name or explicit benchmark pattern;
# - optional package selector, CPU matrix, benchtime, count, and artifact stem.
#
# Outputs:
# - one raw benchmark output file under bench/raw/;
# - one environment capture file under bench/raw/.
#
# Workflow role:
# - this is the canonical raw benchmark collection entrypoint for the
#   repository performance layer.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_SUITE="${DEFAULT_RUN_SUITE}"
readonly DEFAULT_COUNT="${DEFAULT_RUN_COUNT}"
readonly DEFAULT_PACKAGES="${DEFAULT_RUN_PACKAGES}"

SUITE_NAME="${DEFAULT_SUITE}"
OUTPUT_STEM=""
RUN_COUNT="${DEFAULT_COUNT}"
PACKAGE_SELECTOR="${DEFAULT_PACKAGES}"
BENCH_PATTERN=""
CPU_MATRIX=""
BENCHTIME=""

# usage describes the canonical raw benchmark collection workflow and the
# repository defaults that shape it.
#
# This is the main benchmark runner, so the help text makes the suite model and
# CPU behavior explicit instead of expecting callers to read the code.
usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [options]

Options:
  --suite <name>         benchmark suite; default ${DEFAULT_SUITE}
                         supported suites: ${SUPPORTED_SUITES_TEXT}
  --name <stem>          artifact stem; default <suite>-<timestamp>
  --count <n>            go test -count value; default ${DEFAULT_COUNT}
  --packages <pattern>   package selector; default ${DEFAULT_PACKAGES}
  --bench <pattern>      override the suite-derived benchmark pattern
  --cpu <matrix>         comma-separated CPU matrix or "all"
  --benchtime <value>    pass -benchtime through to go test
  -h, --help             show this help text

CPU behavior:
  - when --suite parallel is used without --cpu, the default matrix is
    $(default_parallel_cpu_matrix)
  - for non-parallel suites, CPU matrix is omitted unless explicitly requested

Default artifacts:
  raw output: $(raw_output_path "${DEFAULT_SUITE}-<timestamp>")
  environment: $(raw_env_output_path "${DEFAULT_SUITE}-<timestamp>")

Workflow role:
  use this script to collect repeated raw benchmark evidence.
  Comparison and profiling belong to compare_benchmarks.sh and
  profile_benchmarks.sh.
EOF
}

# parse_args reads user-supplied run controls without yet deciding which
# defaults or suite-derived values need to be filled in.
#
# This keeps user input handling straightforward and leaves repository policy
# decisions such as suite expansion to resolve_defaults.
parse_args() {
  while (($#)); do
    case "$1" in
      --suite)
        require_option_value "$1" "$#" "${2:-}"
        SUITE_NAME="$2"
        shift 2
        ;;
      --name)
        require_option_value "$1" "$#" "${2:-}"
        OUTPUT_STEM="$2"
        shift 2
        ;;
      --count)
        require_option_value "$1" "$#" "${2:-}"
        RUN_COUNT="$2"
        shift 2
        ;;
      --packages)
        require_option_value "$1" "$#" "${2:-}"
        PACKAGE_SELECTOR="$2"
        shift 2
        ;;
      --bench)
        require_option_value "$1" "$#" "${2:-}"
        BENCH_PATTERN="$2"
        shift 2
        ;;
      --cpu)
        require_option_value "$1" "$#" "${2:-}"
        CPU_MATRIX="$2"
        shift 2
        ;;
      --benchtime)
        require_option_value "$1" "$#" "${2:-}"
        BENCHTIME="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
  done
}

# resolve_defaults turns a partial user request into a fully specified run:
# - resolve suite to benchmark pattern when --bench was omitted;
# - apply the richer default CPU sweep only for the parallel suite;
# - expand the special "all" CPU selector;
# - generate the default artifact stem when needed.
#
# This is the point where user intent becomes a concrete repository benchmark
# request.
resolve_defaults() {
  validate_suite_name "${SUITE_NAME}"

  if [[ -z "${BENCH_PATTERN}" ]]; then
    BENCH_PATTERN="$(suite_pattern "${SUITE_NAME}")"
  fi

  if [[ "${CPU_MATRIX}" == "" && "${SUITE_NAME}" == "parallel" ]]; then
    # Parallel scenarios treat CPU exploration as part of the benchmark mode,
    # so the script supplies a multi-point default matrix here.
    CPU_MATRIX="$(default_parallel_cpu_matrix)"
  else
    CPU_MATRIX="$(resolve_cpu_matrix "${CPU_MATRIX}")"
  fi

  if [[ -z "${OUTPUT_STEM}" ]]; then
    OUTPUT_STEM="$(timestamped_stem "${SUITE_NAME}")"
  fi
}

# validate_args checks the fully resolved run configuration before command
# assembly starts.
#
# Validation runs after defaults are filled in so failures reflect the actual
# command shape the script is about to execute.
validate_args() {
  validate_artifact_stem "${OUTPUT_STEM}"
  validate_positive_integer "${RUN_COUNT}" "--count"
  validate_package_selector "${PACKAGE_SELECTOR}" "--packages"
  validate_benchmark_pattern "${BENCH_PATTERN}" "--bench"

  if [[ -n "${BENCHTIME}" ]] && [[ "${BENCHTIME}" == *$'\n'* ]]; then
    die "--benchtime must be a single-line value"
  fi
}

# build_command constructs the canonical raw benchmark collection command.
#
# As with profiling, the command stays in one array so it can be executed
# safely and recorded verbatim in environment metadata.
#
# The runner intentionally stops at raw evidence collection. Interpretation,
# comparison, and profiling remain separate steps.
build_command() {
  read -r -a PACKAGE_ARGS <<<"${PACKAGE_SELECTOR}"

  GO_TEST_CMD=(go test -run '^$' -bench "${BENCH_PATTERN}" -benchmem -count "${RUN_COUNT}")
  if [[ -n "${BENCHTIME}" ]]; then
    GO_TEST_CMD+=(-benchtime "${BENCHTIME}")
  fi
  if [[ -n "${CPU_MATRIX}" ]]; then
    # CPU matrices are optional for most suites, but parallel scenarios treat
    # them as part of the benchmark definition.
    GO_TEST_CMD+=(-cpu "${CPU_MATRIX}")
  fi
  GO_TEST_CMD+=("${PACKAGE_ARGS[@]}")
}

# run_benchmarks writes the environment capture alongside the raw output so a
# later comparison or report can always recover the execution context of the
# run.
#
# The shared stem between the raw output and env capture is intentional: those
# files are designed to travel together through compare and reporting workflows.
run_benchmarks() {
  local raw_output env_output

  raw_output="$(raw_output_path "${OUTPUT_STEM}")"
  env_output="$(raw_env_output_path "${OUTPUT_STEM}")"

  write_env_capture "${env_output}" "${GO_TEST_CMD[@]}"
  "${GO_TEST_CMD[@]}" >"${raw_output}"

  log_artifact "${raw_output}"
  log_artifact "${env_output}"
  printf 'command: %s\n' "$(command_string "${GO_TEST_CMD[@]}")"
}

# main is the canonical benchmark collection flow:
# 1. verify dependencies;
# 2. ensure directories exist;
# 3. parse, resolve, validate, build, and execute one run.
#
# Keeping the flow flat makes changes to benchmark collection behavior easy to
# audit in review.
main() {
  require_command go
  ensure_artifact_dirs
  ensure_go_runtime_dirs

  parse_args "$@"
  resolve_defaults
  validate_args
  build_command
  run_benchmarks
}

main "$@"
