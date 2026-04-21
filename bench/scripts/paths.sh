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
#
# Canonical repository path definitions for the benchmark shell layer.
#
# This file is the single source of truth for repository and artifact
# locations used by the scripts under bench/scripts/.
#
# The shell entrypoints source it directly. Non-shell tooling such as
# plot_benchmarks.py may also load it through a small Bash subprocess rather
# than duplicating repository path derivation in another language.
#
# Why this file exists:
# - every entrypoint script needs the same repository layout;
# - path recomputation spread across multiple files is easy to drift;
# - keeping canonical locations here makes the artifact model obvious.
#
# This module only defines paths. It does not create directories, validate
# arguments, or execute benchmark commands.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "paths.sh is a sourced helper module and must not be executed directly." >&2
  exit 1
fi

# Resolve the scripts directory first, then derive every other path from that
# anchor. This makes the repository layout dependency explicit in one place.
readonly _ARCORIS_POOL_SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly BENCH_SCRIPTS_DIR="${_ARCORIS_POOL_SHELL_DIR}"
readonly BENCH_DIR="$(cd "${BENCH_SCRIPTS_DIR}/.." && pwd)"
readonly REPO_ROOT="$(cd "${BENCH_DIR}/.." && pwd)"

readonly BENCH_RAW_DIR="${BENCH_DIR}/raw"
readonly BENCH_COMPARE_DIR="${BENCH_DIR}/compare"
readonly BENCH_PROFILES_DIR="${BENCH_DIR}/profiles"
readonly BENCH_CPU_PROFILES_DIR="${BENCH_PROFILES_DIR}/cpu"
readonly BENCH_MEM_PROFILES_DIR="${BENCH_PROFILES_DIR}/mem"
readonly BENCH_CHARTS_DIR="${BENCH_DIR}/charts"

readonly DOCS_DIR="${REPO_ROOT}/docs"
readonly DOCS_PERFORMANCE_DIR="${DOCS_DIR}/performance"
readonly REPORTS_DIR="${DOCS_PERFORMANCE_DIR}/reports"

# Export the canonical locations so entrypoint scripts and any subprocesses
# share the same repository vocabulary without recomputing paths.
export BENCH_SCRIPTS_DIR
export BENCH_DIR
export REPO_ROOT
export BENCH_RAW_DIR
export BENCH_COMPARE_DIR
export BENCH_PROFILES_DIR
export BENCH_CPU_PROFILES_DIR
export BENCH_MEM_PROFILES_DIR
export BENCH_CHARTS_DIR
export DOCS_DIR
export DOCS_PERFORMANCE_DIR
export REPORTS_DIR
