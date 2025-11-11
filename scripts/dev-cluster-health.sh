#!/usr/bin/env bash
set -euo pipefail

REFRESH="${REFRESH:-3}"
MODE="single"

if [[ "${1:-}" == "--watch" ]]; then
  MODE="watch"
  shift
fi

NS="${1:-echo-dev}"

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found" >&2
    exit 1
  fi
}

section() {
  printf '\n=== %s ===\n' "$1"
}

parse_top() {
  local svc cpu mem
  awk '
  function mem_to_mi(raw) {
    if (raw ~ /Ki$/) { sub("Ki", "", raw); return raw / 1024 }
    if (raw ~ /Mi$/) { sub("Mi", "", raw); return raw }
    if (raw ~ /Gi$/) { sub("Gi", "", raw); return raw * 1024 }
    return raw
  }
  function cpu_to_m(raw) {
    if (raw ~ /m$/) { sub("m", "", raw); return raw }
    return raw * 1000
  }
  {
    split($1, parts, "-")
    svc = (parts[2] == "" ? parts[1] : parts[2])
    cpu = cpu_to_m($2)
    mem = mem_to_mi($3)
    pod_count[svc]++
    cpu_sum[svc] += cpu
    mem_sum[svc] += mem
  }
  END {
    for (svc in pod_count) {
      printf "%-18s pods=%-2d avg_cpu=%6.1fm avg_mem=%6.1fMi\n", svc, pod_count[svc], cpu_sum[svc] / pod_count[svc], mem_sum[svc] / pod_count[svc]
    }
  }' <<<"$1" | sort
}

if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
  echo "Namespace $NS not found" >&2
  exit 1
fi

check_command kubectl

run_once() {
  local top_output
  top_output="$(kubectl top pods -n "$NS" --no-headers 2>/dev/null || true)"

  section "Deployment Rollout"
  kubectl get deploy -n "$NS"

  section "Horizontal Pod Autoscalers"
  kubectl get hpa -n "$NS"

  section "Pods"
  kubectl get pods -n "$NS"

  if [[ -n "$top_output" ]]; then
    section "Average Resource Usage per Service"
    parse_top "$top_output"
  else
    section "Average Resource Usage per Service"
    echo "kubectl top pods returned no metrics (metrics server missing?)"
  fi

  section "Pods by Status"
  kubectl get pods -n "$NS" --no-headers | awk '{status[$3]++} END {for (s in status) printf "%s: %d\n", s, status[s]}' | sort

  section "Top Resource Consumers"
  if [[ -n "$top_output" ]]; then
    echo "$top_output" | sort -k2 -nr | head -5 | awk '{printf "CPU %-22s %s %s\n", $1, $2, $3}'
    echo
    echo "$top_output" | sort -k3 -nr | head -5 | awk '{printf "MEM %-22s %s %s\n", $1, $2, $3}'
  else
    echo "kubectl top pods returned no metrics (metrics server missing?)"
  fi
}

case "$MODE" in
  single)
    run_once
    ;;
  watch)
    while true; do
      clear
      printf 'Timestamp: %s  (namespace: %s, refresh: %ss)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$NS" "$REFRESH"
      run_once
      sleep "$REFRESH"
    done
    ;;
esac
