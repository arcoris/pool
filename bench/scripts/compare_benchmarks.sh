#!/usr/bin/env bash
set -euo pipefail

# Compare two raw benchmark outputs with benchstat.
#
# What this script does:
# - validates the two raw input files;
# - runs benchstat in a thin, explicit wrapper;
# - writes either text output or CSV output under bench/compare/ by default.
#
# What this script does not do:
# - it does not run benchmarks;
# - it does not collect profiles;
# - it does not infer benchmark meaning beyond the supplied raw files.
#
# Inputs:
# - one "old" raw benchmark file;
# - one "new" raw benchmark file;
# - optional output stem or explicit output path;
# - optional output format.
#
# Outputs:
# - one comparison artifact under bench/compare/ by default.
#
# Dependency:
# - benchstat must be installed and available on PATH.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_FORMAT="${DEFAULT_COMPARE_FORMAT}"
readonly DEFAULT_OUTPUT_STEM_PREFIX="${DEFAULT_COMPARE_STEM_PREFIX}"

OLD_FILE=""
NEW_FILE=""
OUTPUT_STEM=""
OUTPUT_PATH=""
OUTPUT_FORMAT="${DEFAULT_FORMAT}"

# usage documents this wrapper's narrow responsibility: compare two existing
# raw outputs and emit one comparison artifact.
#
# The help text also makes the benchstat dependency explicit because this is
# the only maintained shell entrypoint that relies on that external tool.
usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} --old <file> --new <file> [options]

Options:
  --old <file>           baseline raw benchmark file to compare
  --new <file>           candidate raw benchmark file to compare
  --name <stem>          artifact stem; default ${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>
  --output <path>        explicit comparison output path
  --format <format>      text or csv; default ${DEFAULT_FORMAT}
  -h, --help             show this help text

Dependency:
  benchstat must be installed and available on PATH.

Default artifacts:
  text output: $(compare_output_path "${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>" "text")
  csv output:  $(compare_output_path "${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>" "csv")

Workflow role:
  use this script after repeated raw outputs already exist in ${BENCH_RAW_DIR}/.
  CSV output is suitable for chart preparation under ${BENCH_CHARTS_DIR}/.
EOF
}

# parse_args collects the old/new files and the optional naming controls for
# the compare artifact.
#
# The argument surface intentionally stays small because comparison should
# remain a thin wrapper over benchstat rather than becoming a second runner.
parse_args() {
  while (($#)); do
    case "$1" in
      --old)
        require_option_value "$1" "$#" "${2:-}"
        OLD_FILE="$2"
        shift 2
        ;;
      --new)
        require_option_value "$1" "$#" "${2:-}"
        NEW_FILE="$2"
        shift 2
        ;;
      --name)
        require_option_value "$1" "$#" "${2:-}"
        OUTPUT_STEM="$2"
        shift 2
        ;;
      --output)
        require_option_value "$1" "$#" "${2:-}"
        OUTPUT_PATH="$2"
        shift 2
        ;;
      --format)
        require_option_value "$1" "$#" "${2:-}"
        OUTPUT_FORMAT="$2"
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

# validate_args checks every property that can be verified before benchstat is
# launched.
#
# Front-loading validation produces clearer failures than delegating malformed
# input directly to benchstat and then interpreting its errors.
validate_args() {
  validate_existing_file "${OLD_FILE}" "old benchmark"
  validate_existing_file "${NEW_FILE}" "new benchmark"
  validate_compare_format "${OUTPUT_FORMAT}"

  if [[ -n "${OUTPUT_STEM}" ]]; then
    validate_artifact_stem "${OUTPUT_STEM}"
  fi
}

# resolve_output_path chooses the default compare artifact path when the caller
# did not supply one explicitly.
#
# Explicit output paths are still allowed, but the default path preserves the
# repository artifact convention used by reports and chart-preparation steps.
resolve_output_path() {
  if [[ -n "${OUTPUT_PATH}" ]]; then
    return
  fi

  if [[ -z "${OUTPUT_STEM}" ]]; then
    OUTPUT_STEM="$(timestamped_stem "${DEFAULT_OUTPUT_STEM_PREFIX}")"
  fi

  OUTPUT_PATH="$(compare_output_path "${OUTPUT_STEM}" "${OUTPUT_FORMAT}")"
}

# run_compare is intentionally thin: it only selects the maintained benchstat
# invocation for the requested output format.
#
# Any richer interpretation belongs in reports and documentation, not in this
# wrapper script.
run_compare() {
  ensure_parent_dir "${OUTPUT_PATH}"

  case "${OUTPUT_FORMAT}" in
    text)
      benchstat "${OLD_FILE}" "${NEW_FILE}" >"${OUTPUT_PATH}"
      ;;
    csv)
      # CSV output exists so later chart-generation steps can consume the same
      # comparison without scraping the human-readable text format.
      benchstat -format csv "${OLD_FILE}" "${NEW_FILE}" >"${OUTPUT_PATH}"
      ;;
  esac
}

# main enforces the wrapper contract:
# - two raw input files are mandatory;
# - benchstat must be present;
# - output naming is resolved only after validation succeeds.
#
# This ordering keeps filesystem writes and external-tool execution out of the
# path until the request is known to be coherent.
main() {
  ensure_artifact_dirs

  parse_args "$@"

  if [[ -z "${OLD_FILE}" || -z "${NEW_FILE}" ]]; then
    usage >&2
    die "--old and --new are required"
  fi

  validate_args
  resolve_output_path
  require_command benchstat

  run_compare
  log_artifact "${OUTPUT_PATH}"
}

main "$@"
