#!/usr/bin/env bash
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
set -euo pipefail

# Collect CPU and/or memory profiles for one benchmark pattern in one package.
#
# What this script does:
# - selects one benchmark pattern and one package;
# - builds one profiling-oriented go test command;
# - writes CPU and/or memory profiles under bench/profiles/;
# - writes matching environment metadata under bench/profiles/.
#
# What this script does not do:
# - it does not compare results;
# - it does not support multi-package profiling;
# - it does not infer benchmark meaning from the pattern it profiles.
#
# Inputs:
# - one benchmark pattern;
# - optional package path, count, CPU matrix, benchtime, profile mode, and stem.
#
# Outputs:
# - one environment capture file under bench/profiles/;
# - zero or one CPU profile under bench/profiles/cpu/;
# - zero or one memory profile under bench/profiles/mem/.
#
# Workflow role:
# - use this script after a benchmark run identifies a focused question that
#   needs profile evidence.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_COUNT="${DEFAULT_PROFILE_COUNT}"
readonly DEFAULT_PROFILE_SELECTION="${DEFAULT_PROFILE_MODE}"
readonly DEFAULT_OUTPUT_STEM_PREFIX="${DEFAULT_PROFILE_STEM_PREFIX}"

BENCH_PATTERN=""
OUTPUT_STEM=""
PACKAGE_SELECTOR=""
RUN_COUNT="${DEFAULT_COUNT}"
CPU_MATRIX=""
BENCHTIME=""
PROFILE_MODE="${DEFAULT_PROFILE_SELECTION}"

# usage explains the one-pattern, one-package profiling model and the artifact
# set created by each profiling run.
#
# Profiling has tighter constraints than raw benchmark collection, so the help
# text spells those rules out directly instead of leaving them implicit.
usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} --bench <pattern> [options]

Options:
  --bench <pattern>      benchmark pattern to profile; required
  --name <stem>          artifact stem; default ${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>
  --packages <pattern>   exactly one package path; default inferred from --bench
  --count <n>            go test -count value; default ${DEFAULT_COUNT}
  --cpu <matrix>         comma-separated CPU matrix or "all"
  --benchtime <value>    pass -benchtime through to go test
  --profile <mode>       cpu | mem | both; default ${DEFAULT_PROFILE_SELECTION}
  -h, --help             show this help text

Package selection:
  - backend benchmark patterns default to ./internal/backend
  - all other patterns default to ./
  - wildcard selectors such as ./... are intentionally rejected

Default artifacts:
  environment: $(profile_env_output_path "${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>")
  CPU profile: $(profile_cpu_output_path "${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>")
  MEM profile: $(profile_mem_output_path "${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>")

Workflow role:
  use this script for one focused benchmark question at a time.
  It writes raw profiles under ${BENCH_PROFILES_DIR}/ and does not interpret them.
EOF
}

# parse_args gathers the user-controlled parts of one profiling request before
# defaults are resolved.
#
# Keeping parsing separate from default inference makes it clear which values
# came from the caller and which ones come from repository policy.
parse_args() {
  while (($#)); do
    case "$1" in
      --bench)
        require_option_value "$1" "$#" "${2:-}"
        BENCH_PATTERN="$2"
        shift 2
        ;;
      --name)
        require_option_value "$1" "$#" "${2:-}"
        OUTPUT_STEM="$2"
        shift 2
        ;;
      --packages)
        require_option_value "$1" "$#" "${2:-}"
        PACKAGE_SELECTOR="$2"
        shift 2
        ;;
      --count)
        require_option_value "$1" "$#" "${2:-}"
        RUN_COUNT="$2"
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
      --profile)
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
        die "unknown argument: $1"
        ;;
    esac
  done
}

# resolve_defaults fills in the pieces the caller may reasonably omit:
# artifact stem, inferred package, and resolved CPU matrix.
#
# Package inference happens only after the benchmark pattern is known so backend
# and pool-level benchmarks can follow different defaults.
resolve_defaults() {
  if [[ -z "${OUTPUT_STEM}" ]]; then
    OUTPUT_STEM="$(timestamped_stem "${DEFAULT_OUTPUT_STEM_PREFIX}")"
  fi

  if [[ -z "${PACKAGE_SELECTOR}" ]]; then
    PACKAGE_SELECTOR="$(default_profile_packages "${BENCH_PATTERN}")"
  fi

  CPU_MATRIX="$(resolve_cpu_matrix "${CPU_MATRIX}")"
}

# validate_args enforces the one-pattern, one-package profiling model.
#
# The profiling wrapper rejects ambiguous package selectors up front because Go
# profile flags do not yield coherent multi-package artifacts.
validate_args() {
  validate_benchmark_pattern "${BENCH_PATTERN}" "--bench"
  validate_positive_integer "${RUN_COUNT}" "--count"
  validate_profile_mode "${PROFILE_MODE}"
  validate_profile_packages "${PACKAGE_SELECTOR}"
  validate_artifact_stem "${OUTPUT_STEM}"

  if [[ -n "${BENCHTIME}" ]] && [[ "${BENCHTIME}" == *$'\n'* ]]; then
    die "--benchtime must be a single-line value"
  fi
}

# build_command constructs exactly one profiling-oriented `go test` command.
#
# Keeping the command in one array avoids word-splitting bugs and makes it easy
# to record the exact invocation in the matching environment artifact.
#
# Profiling stays focused on one benchmark family so resulting profiles remain
# attributable to one performance question.
build_command() {
  read -r -a PACKAGE_ARGS <<<"${PACKAGE_SELECTOR}"

  GO_TEST_CMD=(go test -run '^$' -bench "${BENCH_PATTERN}" -benchmem -count "${RUN_COUNT}")

  if [[ -n "${BENCHTIME}" ]]; then
    # benchtime is passed through verbatim so focused investigations can choose
    # their own stability-versus-duration tradeoff.
    GO_TEST_CMD+=(-benchtime "${BENCHTIME}")
  fi
  if [[ -n "${CPU_MATRIX}" ]]; then
    # Profiling may still explore more than one CPU count when the caller is
    # investigating parallel scaling under one focused benchmark family.
    GO_TEST_CMD+=(-cpu "${CPU_MATRIX}")
  fi

  case "${PROFILE_MODE}" in
    cpu)
      GO_TEST_CMD+=(-cpuprofile "$(profile_cpu_output_path "${OUTPUT_STEM}")")
      ;;
    mem)
      GO_TEST_CMD+=(-memprofile "$(profile_mem_output_path "${OUTPUT_STEM}")")
      ;;
    both)
      GO_TEST_CMD+=(
        -cpuprofile "$(profile_cpu_output_path "${OUTPUT_STEM}")"
        -memprofile "$(profile_mem_output_path "${OUTPUT_STEM}")"
      )
      ;;
  esac

  GO_TEST_CMD+=("${PACKAGE_ARGS[@]}")
}

# run_profiles writes the matching environment capture first, then executes the
# profiling command, and finally reports every artifact that was created.
#
# Writing environment metadata first means an interrupted or failed run still
# leaves behind the intended command and host context for debugging.
run_profiles() {
  local env_output
  env_output="$(profile_env_output_path "${OUTPUT_STEM}")"

  write_env_capture "${env_output}" "${GO_TEST_CMD[@]}"
  "${GO_TEST_CMD[@]}"

  log_artifact "${env_output}"
  case "${PROFILE_MODE}" in
    cpu)
      log_artifact "$(profile_cpu_output_path "${OUTPUT_STEM}")"
      ;;
    mem)
      log_artifact "$(profile_mem_output_path "${OUTPUT_STEM}")"
      ;;
    both)
      log_artifact "$(profile_cpu_output_path "${OUTPUT_STEM}")"
      log_artifact "$(profile_mem_output_path "${OUTPUT_STEM}")"
      ;;
  esac
}

# main keeps the profiling workflow linear and explicit:
# 1. verify dependencies and directories;
# 2. parse args;
# 3. require a benchmark pattern;
# 4. resolve defaults and validate;
# 5. build and run the profiling command.
#
# The flow is intentionally flat so a maintainer can audit a profiling request
# from top to bottom without chasing hidden control flow.
main() {
  require_command go
  ensure_artifact_dirs
  ensure_go_runtime_dirs

  parse_args "$@"

  if [[ -z "${BENCH_PATTERN}" ]]; then
    usage >&2
    die "--bench is required"
  fi

  resolve_defaults
  validate_args
  build_command
  run_profiles
}

main "$@"
