#!/usr/bin/env bash
set -euo pipefail

# Reproduces and compares memory growth patterns in long-lived `unison mcp` stdio
# processes across different MCP request scenarios.
#
# Usage:
#   scripts/mcp-memory-repro.sh
#
# Environment overrides:
#   UCM_BIN=./result/bin/unison
#   ITERATIONS=200
#   SAMPLE_EVERY=50
#   RESPONSE_TIMEOUT_SECONDS=30
#   OUTDIR=.run/mcp-memory-repro-<timestamp>
#   SCENARIOS=resources-list,tool-get-current-project-context,tool-list-local-projects,tool-list-project-branches
#   Optional scenarios: tool-share-project-search,tool-share-project-info

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

UCM_BIN="${UCM_BIN:-./result/bin/unison}"
ITERATIONS="${ITERATIONS:-200}"
SAMPLE_EVERY="${SAMPLE_EVERY:-50}"
RESPONSE_TIMEOUT_SECONDS="${RESPONSE_TIMEOUT_SECONDS:-30}"
OUTDIR="${OUTDIR:-.run/mcp-memory-repro-$(date +%Y%m%d-%H%M%S)}"
SCENARIOS="${SCENARIOS:-resources-list,tool-get-current-project-context,tool-list-local-projects,tool-list-project-branches}"

if [[ ! -x "$UCM_BIN" ]]; then
  echo "error: UCM binary is not executable: $UCM_BIN" >&2
  exit 1
fi

mkdir -p "$OUTDIR"
SUMMARY_CSV="$OUTDIR/summary.csv"
echo "scenario,iterations,successes,failures,rss_before_kib,rss_after_kib,rss_delta_kib,rss_delta_per_call_kib,anon_before_kib,anon_after_kib,anon_delta_kib,anon_delta_per_call_kib,threads_before,threads_after,zombies_before,zombies_after,fds_before,fds_after,elapsed_ms" > "$SUMMARY_CSV"

trim_whitespace() {
  tr -d '[:space:]'
}

status_metric_kib() {
  local pid="$1"
  local key="$2"
  awk -v key="$key" '$1 == key ":" { print $2 }' "/proc/$pid/status" 2>/dev/null
}

thread_count() {
  local pid="$1"
  awk '$1 == "Threads:" { print $2 }' "/proc/$pid/status" 2>/dev/null
}

fd_count() {
  local pid="$1"
  find "/proc/$pid/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | trim_whitespace
}

zombie_children() {
  local pid="$1"
  ps --ppid "$pid" -o stat= 2>/dev/null | awk '$1 ~ /^Z/ { c++ } END { print c + 0 }'
}

now_ms() {
  date +%s%3N
}

request_json() {
  local scenario="$1"
  local id="$2"
  case "$scenario" in
    resources-list)
      jq -cn --argjson id "$id" '{"jsonrpc":"2.0","id":$id,"method":"resources/list","params":{}}'
      ;;
    tool-get-current-project-context)
      jq -cn --argjson id "$id" '{"jsonrpc":"2.0","id":$id,"method":"tools/call","params":{"name":"get-current-project-context","arguments":{}}}'
      ;;
    tool-share-project-search)
      jq -cn --argjson id "$id" '{"jsonrpc":"2.0","id":$id,"method":"tools/call","params":{"name":"share-project-search","arguments":{"query":"base"}}}'
      ;;
    tool-share-project-info)
      jq -cn --argjson id "$id" '{"jsonrpc":"2.0","id":$id,"method":"tools/call","params":{"name":"share-project-info","arguments":{"projectName":"@unison/base"}}}'
      ;;
    tool-list-local-projects)
      jq -cn --argjson id "$id" '{"jsonrpc":"2.0","id":$id,"method":"tools/call","params":{"name":"list-local-projects","arguments":{}}}'
      ;;
    tool-list-project-branches)
      jq -cn --argjson id "$id" '{"jsonrpc":"2.0","id":$id,"method":"tools/call","params":{"name":"list-project-branches","arguments":{"projectName":"scratch"}}}'
      ;;
    *)
      echo "error: unsupported scenario: $scenario" >&2
      return 1
      ;;
  esac
}

run_scenario() {
  local scenario="$1"
  local scenario_dir="$OUTDIR/$scenario"
  local cb_dir="$scenario_dir/codebase"
  local in_fifo="$scenario_dir/in.fifo"
  local out_fifo="$scenario_dir/out.fifo"
  local metrics_csv="$scenario_dir/metrics.csv"
  local stderr_log="$scenario_dir/stderr.log"
  local events_log="$scenario_dir/events.log"

  mkdir -p "$scenario_dir" "$cb_dir"
  rm -f "$in_fifo" "$out_fifo"
  mkfifo "$in_fifo" "$out_fifo"

  "$UCM_BIN" -C "$cb_dir" mcp < "$in_fifo" > "$out_fifo" 2> "$stderr_log" &
  local pid="$!"

  exec 3>"$in_fifo"
  exec 4<"$out_fifo"

  local cleaned_up=0
  cleanup() {
    if [[ "$cleaned_up" -eq 1 ]]; then
      return
    fi
    cleaned_up=1
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exec 3>&- || true
    exec 4<&- || true
    rm -f "$in_fifo" "$out_fifo"
  }
  trap cleanup EXIT

  send_json_line() {
    local json="$1"
    printf '%s\n' "$json" >&3
  }

  # MCP stdio in this build emits one JSON object per line.
  # Startup banners may be prefixed before the first JSON object; strip them.
  read_response_for_id() {
    local wanted_id="$1"
    local deadline=$((SECONDS + RESPONSE_TIMEOUT_SECONDS))
    local line json
    while (( SECONDS < deadline )); do
      if IFS= read -r -t 1 line <&4; then
        [[ "$line" == *"{"* ]] || continue
        json="{${line#*\{}"
        if echo "$json" | jq -e --argjson id "$wanted_id" '.id == $id' >/dev/null 2>&1; then
          printf '%s\n' "$json"
          return 0
        fi
      fi
    done
    return 1
  }

  echo "ts_iso,iter,rss_kib,anon_kib,swap_kib,threads,fds,zombie_children" > "$metrics_csv"

  sample_metrics() {
    local iter="$1"
    local ts
    ts="$(date -Is)"
    local rss anon swap threads fds zombies
    rss="$(status_metric_kib "$pid" "VmRSS")"
    anon="$(status_metric_kib "$pid" "RssAnon")"
    swap="$(status_metric_kib "$pid" "VmSwap")"
    threads="$(thread_count "$pid")"
    fds="$(fd_count "$pid")"
    zombies="$(zombie_children "$pid")"
    echo "$ts,$iter,$rss,$anon,$swap,$threads,$fds,$zombies" >> "$metrics_csv"
  }

  local init_req
  init_req="$(jq -cn '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mcp-memory-repro","version":"0.1"}}}')"
  send_json_line "$init_req"
  if ! read_response_for_id 1 > "$scenario_dir/initialize.json"; then
    echo "initialize_timeout scenario=$scenario" >> "$events_log"
    return 1
  fi
  send_json_line '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'

  local rss_before anon_before threads_before zombies_before fds_before
  rss_before="$(status_metric_kib "$pid" "VmRSS")"
  anon_before="$(status_metric_kib "$pid" "RssAnon")"
  threads_before="$(thread_count "$pid")"
  zombies_before="$(zombie_children "$pid")"
  fds_before="$(fd_count "$pid")"
  if [[ -z "$rss_before" || -z "$anon_before" ]]; then
    echo "pid_metrics_unavailable scenario=$scenario pid=$pid" >> "$events_log"
    return 1
  fi

  sample_metrics 0

  local scenario_start_ms
  scenario_start_ms="$(now_ms)"
  local success_count=0
  local failure_count=0

  local i req_id req_json req_start_ms req_end_ms req_elapsed_ms
  for ((i = 1; i <= ITERATIONS; i++)); do
    req_id=$((10000 + i))
    req_json="$(request_json "$scenario" "$req_id")"
    req_start_ms="$(now_ms)"
    send_json_line "$req_json"
    if read_response_for_id "$req_id" > "$scenario_dir/response-$i.json"; then
      req_end_ms="$(now_ms)"
      req_elapsed_ms=$((req_end_ms - req_start_ms))
      if jq -e '.error != null or (.result.isError? == true)' "$scenario_dir/response-$i.json" >/dev/null 2>&1; then
        failure_count=$((failure_count + 1))
        echo "response_error iter=$i id=$req_id elapsed_ms=$req_elapsed_ms" >> "$events_log"
      else
        success_count=$((success_count + 1))
      fi
    else
      req_end_ms="$(now_ms)"
      req_elapsed_ms=$((req_end_ms - req_start_ms))
      failure_count=$((failure_count + 1))
      echo "response_timeout iter=$i id=$req_id elapsed_ms=$req_elapsed_ms" >> "$events_log"
    fi

    if (( i % SAMPLE_EVERY == 0 )); then
      sample_metrics "$i"
    fi
  done

  local scenario_end_ms elapsed_ms
  scenario_end_ms="$(now_ms)"
  elapsed_ms=$((scenario_end_ms - scenario_start_ms))

  sample_metrics "$ITERATIONS"

  local rss_after anon_after threads_after zombies_after fds_after
  rss_after="$(status_metric_kib "$pid" "VmRSS")"
  anon_after="$(status_metric_kib "$pid" "RssAnon")"
  threads_after="$(thread_count "$pid")"
  zombies_after="$(zombie_children "$pid")"
  fds_after="$(fd_count "$pid")"

  local rss_delta anon_delta
  rss_delta=$((rss_after - rss_before))
  anon_delta=$((anon_after - anon_before))

  local rss_delta_per_call anon_delta_per_call
  rss_delta_per_call="$(awk -v d="$rss_delta" -v n="$ITERATIONS" 'BEGIN { if (n == 0) print 0; else printf "%.2f", d / n }')"
  anon_delta_per_call="$(awk -v d="$anon_delta" -v n="$ITERATIONS" 'BEGIN { if (n == 0) print 0; else printf "%.2f", d / n }')"

  echo "$scenario,$ITERATIONS,$success_count,$failure_count,$rss_before,$rss_after,$rss_delta,$rss_delta_per_call,$anon_before,$anon_after,$anon_delta,$anon_delta_per_call,$threads_before,$threads_after,$zombies_before,$zombies_after,$fds_before,$fds_after,$elapsed_ms" >> "$SUMMARY_CSV"

  trap - EXIT
  cleanup
}

IFS=',' read -r -a scenario_list <<< "$SCENARIOS"

for scenario in "${scenario_list[@]}"; do
  scenario="$(echo "$scenario" | trim_whitespace)"
  if [[ -z "$scenario" ]]; then
    continue
  fi
  echo "== scenario: $scenario =="
  if ! run_scenario "$scenario"; then
    echo "scenario_failed: $scenario (see $OUTDIR/$scenario/events.log)" >&2
  fi
done

echo
echo "Summary CSV: $SUMMARY_CSV"
echo
awk -F',' '
  NR == 1 {
    printf "%-36s %8s %8s %8s %13s %13s %14s %12s\n", "scenario", "iters", "ok", "fail", "rss_delta_kib", "anon_delta_kib", "rss_kib/call", "elapsed_ms";
    next;
  }
  {
    printf "%-36s %8s %8s %8s %13s %13s %14s %12s\n", $1, $2, $3, $4, $7, $11, $8, $19;
  }
' "$SUMMARY_CSV"
