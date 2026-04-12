set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

up-single:
  docker compose -f tools/compose/single-node.yml up -d

up-multi:
  docker compose -f tools/compose/multi-node.yml up -d

down:
  docker compose -f tools/compose/single-node.yml down --remove-orphans || true
  docker compose -f tools/compose/multi-node.yml down --remove-orphans || true

reset-db:
  docker compose -f tools/compose/single-node.yml down -v --remove-orphans || true
  docker compose -f tools/compose/multi-node.yml down -v --remove-orphans || true

fault name="net-cut":
  ./scripts/fault.sh {{name}}

logs:
  docker compose -f tools/compose/single-node.yml logs -f
