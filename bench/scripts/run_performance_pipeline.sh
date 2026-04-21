#!/usr/bin/env bash
set -euo pipefail

# Orchestrate multi-step benchmark workflows by composing the narrower scripts.
#
# What this script does:
# - exposes one top-level entrypoint for common benchmark workflow modes;
# - delegates single-purpose work to the narrower scripts;
# - offers a readable "campaign" mode that can:
#   - run a benchmark suite,
#   - compare the new raw output against an older raw output,
#   - collect focused profiles,
#   - emit chart-ready compare CSV when requested.
#
# What this script does not do:
# - it does not reimplement benchmark collection, comparison, or profiling
#   internals;
# - it does not interpret benchmark results;
# - it does not manage git revisions or check out historical code.
#
# Workflow role:
# - use this script when you want one command that coordinates the maintained
#   benchmark tooling without turning the shell layer into a larger framework.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_MODE="campaign"
readonly CAMPAIGN_DEFAULT_COMPARE_FORMAT="${DEFAULT_COMPARE_FORMAT}"
readonly CAMPAIGN_DEFAULT_PROFILE_MODE="${DEFAULT_PROFILE_MODE}"
readonly RUNNER_SCRIPT="${BENCH_SCRIPTS_DIR}/run_benchmarks.sh"
readonly COMPARE_SCRIPT="${BENCH_SCRIPTS_DIR}/compare_benchmarks.sh"
readonly PROFILE_SCRIPT="${BENCH_SCRIPTS_DIR}/profile_benchmarks.sh"

MODE="${DEFAULT_MODE}"

CAMPAIGN_SUITE="${DEFAULT_RUN_SUITE}"
CAMPAIGN_NAME=""
CAMPAIGN_COUNT="${DEFAULT_RUN_COUNT}"
CAMPAIGN_PACKAGES="${DEFAULT_RUN_PACKAGES}"
CAMPAIGN_BENCH=""
CAMPAIGN_CPU=""
CAMPAIGN_BENCHTIME=""

COMPARE_OLD=""
COMPARE_NAME=""
COMPARE_FORMAT="${CAMPAIGN_DEFAULT_COMPARE_FORMAT}"

PROFILE_BENCH=""
PROFILE_NAME=""
PROFILE_PACKAGES=""
PROFILE_COUNT="${DEFAULT_PROFILE_COUNT}"
PROFILE_CPU=""
PROFILE_BENCHTIME=""
PROFILE_MODE="${CAMPAIGN_DEFAULT_PROFILE_MODE}"

# usage documents both the narrow delegation modes and the richer campaign
# mode that composes maintained scripts.
#
# The help text acts as the operator-facing map of the shell tooling layer, so
# it is intentionally more detailed than the narrower entrypoints.
usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} <mode> [mode options]

Modes:
  run        delegate directly to run_benchmarks.sh
  compare    delegate directly to compare_benchmarks.sh
  profile    delegate directly to profile_benchmarks.sh
  campaign   run a benchmark suite and optionally compare and/or profile

Examples:
  ${SCRIPT_NAME} run --suite all --name baseline --count 10
  ${SCRIPT_NAME} compare --old bench/raw/baseline.txt --new bench/raw/candidate.txt --name delta
  ${SCRIPT_NAME} profile --bench '^BenchmarkCompare_Parallel/' --name parallel-focus
  ${SCRIPT_NAME} campaign --suite all --name candidate --compare-old bench/raw/baseline.txt
  ${SCRIPT_NAME} campaign --suite parallel --name candidate --compare-old bench/raw/baseline.txt --compare-format csv --profile-bench '^BenchmarkCompare_Parallel/'

Campaign options:
  --suite <name>           benchmark suite; default ${DEFAULT_RUN_SUITE}
  --name <stem>            run artifact stem; default <suite>-<timestamp>
  --count <n>              benchmark run count; default ${DEFAULT_RUN_COUNT}
  --packages <pattern>     benchmark package selector; default ${DEFAULT_RUN_PACKAGES}
  --bench <pattern>        explicit benchmark pattern override
  --cpu <matrix>           benchmark CPU matrix or "all"
  --benchtime <value>      benchmark benchtime override
  --compare-old <file>     compare the new raw output against this older raw output
  --compare-name <stem>    comparison artifact stem; default <run-name>-compare
  --compare-format <fmt>   text or csv; default ${CAMPAIGN_DEFAULT_COMPARE_FORMAT}
  --profile-bench <pat>    benchmark pattern to profile after the run
  --profile-name <stem>    profile artifact stem; default <run-name>-profile
  --profile-packages <pkg> explicit profile package; default inferred by profile_benchmarks.sh
  --profile-count <n>      profile run count; default ${DEFAULT_PROFILE_COUNT}
  --profile-cpu <matrix>   profile CPU matrix or "all"
  --profile-benchtime <v>  profile benchtime override
  --profile-mode <mode>    cpu | mem | both; default ${CAMPAIGN_DEFAULT_PROFILE_MODE}
  -h, --help               show this help text

Artifacts:
  - campaign runs create raw outputs under ${BENCH_RAW_DIR}/
  - optional compare steps create outputs under ${BENCH_COMPARE_DIR}/
  - optional profile steps create outputs under ${BENCH_PROFILES_DIR}/

Notes:
  - chart preparation is supported through --compare-format csv
  - compare mode depends on benchstat through compare_benchmarks.sh
EOF
}

# delegate_mode forwards one narrow workflow mode directly to the owning
# entrypoint script.
#
# This keeps the orchestration layer small: it composes maintained scripts
# rather than reimplementing their internals.
#
# Delegation also preserves each script's own validation and help behavior.
delegate_mode() {
  local delegated_mode="$1"
  shift

  case "${delegated_mode}" in
    run)
      "${RUNNER_SCRIPT}" "$@"
      ;;
    compare)
      "${COMPARE_SCRIPT}" "$@"
      ;;
    profile)
      "${PROFILE_SCRIPT}" "$@"
      ;;
    *)
      usage >&2
      die "unknown mode: ${delegated_mode}"
      ;;
  esac
}

# parse_campaign_args gathers the multi-step campaign configuration.
#
# Campaign mode stays explicit: every flag here maps directly to one of the
# underlying runner, compare, or profile scripts.
parse_campaign_args() {
  while (($#)); do
    case "$1" in
      --suite)
        require_option_value "$1" "$#" "${2:-}"
        CAMPAIGN_SUITE="$2"
        shift 2
        ;;
      --name)
        require_option_value "$1" "$#" "${2:-}"
        CAMPAIGN_NAME="$2"
        shift 2
        ;;
      --count)
        require_option_value "$1" "$#" "${2:-}"
        CAMPAIGN_COUNT="$2"
        shift 2
        ;;
      --packages)
        require_option_value "$1" "$#" "${2:-}"
        CAMPAIGN_PACKAGES="$2"
        shift 2
        ;;
      --bench)
        require_option_value "$1" "$#" "${2:-}"
        CAMPAIGN_BENCH="$2"
        shift 2
        ;;
      --cpu)
        require_option_value "$1" "$#" "${2:-}"
        CAMPAIGN_CPU="$2"
        shift 2
        ;;
      --benchtime)
        require_option_value "$1" "$#" "${2:-}"
        CAMPAIGN_BENCHTIME="$2"
        shift 2
        ;;
      --compare-old)
        require_option_value "$1" "$#" "${2:-}"
        COMPARE_OLD="$2"
        shift 2
        ;;
      --compare-name)
        require_option_value "$1" "$#" "${2:-}"
        COMPARE_NAME="$2"
        shift 2
        ;;
      --compare-format)
        require_option_value "$1" "$#" "${2:-}"
        COMPARE_FORMAT="$2"
        shift 2
        ;;
      --profile-bench)
        require_option_value "$1" "$#" "${2:-}"
        PROFILE_BENCH="$2"
        shift 2
        ;;
      --profile-name)
        require_option_value "$1" "$#" "${2:-}"
        PROFILE_NAME="$2"
        shift 2
        ;;
      --profile-packages)
        require_option_value "$1" "$#" "${2:-}"
        PROFILE_PACKAGES="$2"
        shift 2
        ;;
      --profile-count)
        require_option_value "$1" "$#" "${2:-}"
        PROFILE_COUNT="$2"
        shift 2
        ;;
      --profile-cpu)
        require_option_value "$1" "$#" "${2:-}"
        PROFILE_CPU="$2"
        shift 2
        ;;
      --profile-benchtime)
        require_option_value "$1" "$#" "${2:-}"
        PROFILE_BENCHTIME="$2"
        shift 2
        ;;
      --profile-mode)
        require_option_value "$1" "$#" "${2:-}"
        PROFILE_MODE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown campaign argument: $1"
        ;;
    esac
  done
}

# resolve_campaign_defaults fills in the naming links between run, compare, and
# profile steps so related artifacts remain obviously grouped.
#
# Derived stems keep campaign artifacts visually connected without forcing the
# caller to name every output by hand.
resolve_campaign_defaults() {
  validate_suite_name "${CAMPAIGN_SUITE}"

  if [[ -z "${CAMPAIGN_NAME}" ]]; then
    CAMPAIGN_NAME="$(timestamped_stem "${CAMPAIGN_SUITE}")"
  fi

  if [[ -z "${COMPARE_NAME}" && -n "${COMPARE_OLD}" ]]; then
    COMPARE_NAME="${CAMPAIGN_NAME}-compare"
  fi

  if [[ -z "${PROFILE_NAME}" && -n "${PROFILE_BENCH}" ]]; then
    PROFILE_NAME="${CAMPAIGN_NAME}-profile"
  fi
}

# validate_campaign_args checks the complete campaign configuration after
# defaults have been resolved.
#
# Each validation rule mirrors a downstream script constraint so the pipeline
# fails before it starts executing multi-step work.
validate_campaign_args() {
  validate_artifact_stem "${CAMPAIGN_NAME}"
  validate_suite_name "${CAMPAIGN_SUITE}"
  validate_positive_integer "${CAMPAIGN_COUNT}" "--count"
  validate_package_selector "${CAMPAIGN_PACKAGES}" "--packages"

  if [[ -n "${CAMPAIGN_BENCH}" ]]; then
    validate_benchmark_pattern "${CAMPAIGN_BENCH}" "--bench"
  fi
  if [[ -n "${CAMPAIGN_CPU}" && "${CAMPAIGN_CPU}" != "all" ]]; then
    validate_cpu_matrix "${CAMPAIGN_CPU}"
  fi
  if [[ -n "${CAMPAIGN_BENCHTIME}" ]] && [[ "${CAMPAIGN_BENCHTIME}" == *$'\n'* ]]; then
    die "--benchtime must be a single-line value"
  fi

  if [[ -n "${COMPARE_OLD}" ]]; then
    validate_existing_file "${COMPARE_OLD}" "old benchmark"
    validate_compare_format "${COMPARE_FORMAT}"
    validate_artifact_stem "${COMPARE_NAME}"
  fi

  if [[ -n "${PROFILE_BENCH}" ]]; then
    validate_benchmark_pattern "${PROFILE_BENCH}" "--profile-bench"
    validate_profile_mode "${PROFILE_MODE}"
    validate_positive_integer "${PROFILE_COUNT}" "--profile-count"
    validate_artifact_stem "${PROFILE_NAME}"

    if [[ -n "${PROFILE_PACKAGES}" ]]; then
      validate_profile_packages "${PROFILE_PACKAGES}"
    fi
    if [[ -n "${PROFILE_CPU}" && "${PROFILE_CPU}" != "all" ]]; then
      validate_cpu_matrix "${PROFILE_CPU}"
    fi
    if [[ -n "${PROFILE_BENCHTIME}" ]] && [[ "${PROFILE_BENCHTIME}" == *$'\n'* ]]; then
      die "--profile-benchtime must be a single-line value"
    fi
  fi
}

# run_campaign composes the narrower scripts in repository workflow order:
# 1. raw benchmark collection;
# 2. optional comparison;
# 3. optional profiling.
#
# The order matters: compare consumes the new raw output, while profiling is a
# follow-up investigation rather than part of baseline data collection.
run_campaign() {
  local run_cmd compare_cmd profile_cmd

  # Start with the canonical raw runner invocation, then layer optional
  # overrides on top so the resulting command remains easy to audit.
  run_cmd=("${RUNNER_SCRIPT}" --suite "${CAMPAIGN_SUITE}" --name "${CAMPAIGN_NAME}" --count "${CAMPAIGN_COUNT}" --packages "${CAMPAIGN_PACKAGES}")
  if [[ -n "${CAMPAIGN_BENCH}" ]]; then
    run_cmd+=(--bench "${CAMPAIGN_BENCH}")
  fi
  if [[ -n "${CAMPAIGN_CPU}" ]]; then
    run_cmd+=(--cpu "${CAMPAIGN_CPU}")
  fi
  if [[ -n "${CAMPAIGN_BENCHTIME}" ]]; then
    run_cmd+=(--benchtime "${CAMPAIGN_BENCHTIME}")
  fi

  log_info "running benchmark campaign: ${CAMPAIGN_NAME}"
  "${run_cmd[@]}"

  if [[ -n "${COMPARE_OLD}" ]]; then
    compare_cmd=(
      "${COMPARE_SCRIPT}"
      --old "${COMPARE_OLD}"
      --new "$(raw_output_path "${CAMPAIGN_NAME}")"
      --name "${COMPARE_NAME}"
      --format "${COMPARE_FORMAT}"
    )

    log_info "comparing ${COMPARE_OLD} against $(raw_output_path "${CAMPAIGN_NAME}")"
    "${compare_cmd[@]}"
  fi

  if [[ -n "${PROFILE_BENCH}" ]]; then
    profile_cmd=(
      "${PROFILE_SCRIPT}"
      --bench "${PROFILE_BENCH}"
      --name "${PROFILE_NAME}"
      --count "${PROFILE_COUNT}"
      --profile "${PROFILE_MODE}"
    )

    # Profiling inherits only the parameters that matter to the focused profile
    # step rather than blindly forwarding the benchmark-run configuration.
    if [[ -n "${PROFILE_PACKAGES}" ]]; then
      profile_cmd+=(--packages "${PROFILE_PACKAGES}")
    fi
    if [[ -n "${PROFILE_CPU}" ]]; then
      profile_cmd+=(--cpu "${PROFILE_CPU}")
    fi
    if [[ -n "${PROFILE_BENCHTIME}" ]]; then
      profile_cmd+=(--benchtime "${PROFILE_BENCHTIME}")
    fi

    log_info "collecting profiles for benchmark pattern: ${PROFILE_BENCH}"
    "${profile_cmd[@]}"
  fi
}

# main dispatches to either one delegated narrow mode or the richer campaign
# mode that composes several maintained entrypoints.
#
# The dispatcher stays explicit rather than dynamic so supported modes remain
# obvious in code review and in help text.
main() {
  if (($# == 0)); then
    usage >&2
    exit 1
  fi

  MODE="$1"
  shift

  case "${MODE}" in
    -h|--help)
      usage
      ;;
    run|compare|profile)
      delegate_mode "${MODE}" "$@"
      ;;
    campaign)
      parse_campaign_args "$@"
      resolve_campaign_defaults
      validate_campaign_args
      run_campaign
      ;;
    *)
      usage >&2
      die "unknown mode: ${MODE}"
      ;;
  esac
}

main "$@"
