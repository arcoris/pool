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

# Capture benchmark environment metadata without running benchmarks.
#
# What this script does:
# - records repository, Go toolchain, host, CPU, and command metadata;
# - writes one text artifact that can be stored next to raw benchmark output.
#
# What this script does not do:
# - it does not run benchmarks;
# - it does not compare results;
# - it does not collect profiles.
#
# Inputs:
# - optional output path;
# - optional command context recorded verbatim in the environment artifact.
#
# Outputs:
# - one environment capture file, by default under bench/raw/.
#
# Workflow role:
# - use this script when you need a standalone environment snapshot;
# - benchmark runner and profile scripts also reuse the same capture format.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_OUTPUT_STEM_PREFIX="${DEFAULT_ENV_STEM_PREFIX}"

OUTPUT_PATH=""
COMMAND_ARGS=()

# usage prints the contract of this narrow utility script.
#
# The help text repeats the default artifact location and the captured metadata
# set so a caller can understand the output without reading common.sh.
usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [options]

Options:
  --output <path>        write the environment capture to an explicit path
  --command <cmd>...     record the associated command context in the artifact
  -h, --help             show this help text

Default output:
  $(raw_env_output_path "${DEFAULT_OUTPUT_STEM_PREFIX}-<timestamp>")

Captured fields:
  - repository root and git revision
  - go version, GOOS, and GOARCH
  - CPU model and logical CPU count
  - hostname and uname
  - GOMAXPROCS, GOCACHE, and GOTMPDIR values
  - optional command context

Artifact:
  environment capture text under ${BENCH_RAW_DIR}/ by default
EOF
}

# parse_args handles the small flag surface of this script.
#
# `--command` is special: everything after it is treated as command context to
# be recorded verbatim rather than parsed as additional script flags.
#
# That behavior makes the script useful for documenting external commands whose
# own flags would otherwise collide with this script's parser.
parse_args() {
  while (($#)); do
    case "$1" in
      --output)
        require_option_value "$1" "$#" "${2:-}"
        OUTPUT_PATH="$2"
        shift 2
        ;;
      --command)
        # The remaining arguments belong to the command context snapshot.
        shift
        COMMAND_ARGS=("$@")
        break
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

# resolve_output_path applies the repository naming convention when the caller
# did not provide an explicit destination path.
#
# Keeping default resolution here instead of in parse_args keeps argument
# parsing focused on user input rather than derived policy.
resolve_output_path() {
  if [[ -n "${OUTPUT_PATH}" ]]; then
    return
  fi

  OUTPUT_PATH="$(raw_env_output_path "$(timestamped_stem "${DEFAULT_OUTPUT_STEM_PREFIX}")")"
}

# main keeps the flow deliberately small:
# 1. verify Go is present for environment capture;
# 2. ensure artifact directories exist;
# 3. parse and resolve arguments;
# 4. write one environment artifact.
#
# The script always writes exactly one file, which makes it safe to call from
# larger orchestration workflows without hidden side effects.
main() {
  require_command go
  ensure_artifact_dirs

  parse_args "$@"
  resolve_output_path

  write_env_capture "${OUTPUT_PATH}" "${COMMAND_ARGS[@]}"
  log_artifact "${OUTPUT_PATH}"
}

main "$@"
