#!/usr/bin/env bash

set -euo pipefail

fault_name="${1:-net-cut}"
proxy_api="${STACK_LAB_TOXIPROXY_API:-http://127.0.0.1:8474}"
proxy_name="${STACK_LAB_TOXIPROXY_PROXY:-postgres}"

case "$fault_name" in
  net-cut)
    curl -fsS -X POST "$proxy_api/proxies/$proxy_name/toxics" \
      -H "Content-Type: application/json" \
      -d '{"name":"stack_lab_net_cut","type":"timeout","stream":"downstream","attributes":{"timeout":10000}}'
    ;;
  high-latency)
    curl -fsS -X POST "$proxy_api/proxies/$proxy_name/toxics" \
      -H "Content-Type: application/json" \
      -d '{"name":"stack_lab_high_latency","type":"latency","stream":"downstream","attributes":{"latency":2500,"jitter":250}}'
    ;;
  clear)
    curl -fsS -X DELETE "$proxy_api/proxies/$proxy_name/toxics/stack_lab_net_cut" || true
    curl -fsS -X DELETE "$proxy_api/proxies/$proxy_name/toxics/stack_lab_high_latency" || true
    ;;
  *)
    echo "unknown fault: $fault_name" >&2
    exit 1
    ;;
esac
