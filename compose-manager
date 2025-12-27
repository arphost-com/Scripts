#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# compose-manager.sh
# Discover + manage docker compose projects under a root directory.
# Supports .inactive marker files to skip projects by default.
# -------------------------------------------------------------------

# Defaults
ROOT="/docker"
INACTIVE_MARKER=".inactive"
INCLUDE_INACTIVE=0
ONLY_INACTIVE=0
DRY_RUN=0
DO_PRUNE=0
VERBOSE=0

declare -a EXCLUDES=()
declare -a ONLY=()
declare -a CLI_PROJECTS=()

# Colors (only if TTY)
if [[ -t 1 ]]; then
  WHITE=$(tput setaf 7); CYAN=$(tput setaf 6); MAGENTA=$(tput setaf 5); BLUE=$(tput setaf 4)
  YELLOW=$(tput setaf 3); GREEN=$(tput setaf 2); RED=$(tput setaf 1); BLACK=$(tput setaf 0)
  NC=$(tput sgr0)
else
  WHITE=""; CYAN=""; MAGENTA=""; BLUE=""; YELLOW=""; GREEN=""; RED=""; BLACK=""; NC=""
fi

log_hdr() { echo -e "${GREEN}-----------------------------------------------------------------------------${NC}"; }
say()     { echo -e "$*"; }
warn()    { echo -e "${YELLOW}WARN:${NC} $*" >&2; }
err()     { echo -e "${RED}ERROR:${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [global options] <command> [project ...]
Commands:
  list            List discovered projects + running containers per project
  status          Show 'docker compose ps' per project
  check           Check for image updates (pull + summarized report; no up)
  pull            Pull images for projects
  update          Pull + up -d for projects
  restart         Restart services for projects
  down            docker compose down for projects
  prune           Run docker prune (images, networks, volumes)

Global options:
  -r, --root <path>        Root folder containing projects (default: /docker)
  -x, --exclude <name>     Exclude a project by folder name (repeatable)
  -o, --only <name>        Only include a project by folder name (repeatable)
      --include-inactive   Include projects with a .inactive marker file
      --only-inactive      Only include projects with a .inactive marker file
  -n, --dry-run            Show what would be done (no changes)
  -p, --prune              Run prune at the end (after pull/update/etc.)
  -v, --verbose            More output (shows skip reasons)
  -h, --help               Show help

Notes:
  - A project is any directory (ROOT itself or one level below ROOT) containing:
      compose.yml | compose.yaml | docker-compose.yml | docker-compose.yaml
  - To mark a project inactive:
      touch <project>/.inactive
    To re-enable:
      rm <project>/.inactive

Examples:
  $(basename "$0") --root /home/bstetler/docker list
  $(basename "$0") --root /home/bstetler/docker update
  $(basename "$0") --root /home/bstetler/docker update sonarr radarr
  $(basename "$0") --root /home/bstetler/docker --exclude homeassistant update
  $(basename "$0") --root /home/bstetler/docker check
  $(basename "$0") --root /home/bstetler/docker --include-inactive list
  $(basename "$0") --root /home/bstetler/docker --only-inactive list
EOF
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

contains() { # contains <needle> <hay...>
  local needle="$1"; shift
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

run() {
  if (( DRY_RUN )); then
    say "${CYAN}[dry-run]${NC} $*"
  else
    eval "$@"
  fi
}

compose_file_for_dir() {
  local d="$1"
  local f
  for f in "compose.yml" "compose.yaml" "docker-compose.yml" "docker-compose.yaml"; do
    if [[ -f "$d/$f" ]]; then
      echo "$d/$f"
      return 0
    fi
  done
  echo ""
}

is_inactive_project() {
  local dir="$1"
  [[ -f "$dir/$INACTIVE_MARKER" ]]
}

project_header() {
  local name="$1" dir="$2"
  log_hdr
  say "${YELLOW}${name}${NC}  ${MAGENTA}${dir}${NC}"
  log_hdr
}

compose_cmd() {
  local dir="$1"
  local cf
  cf="$(compose_file_for_dir "$dir")"
  [[ -n "$cf" ]] || return 1
  # Set -p to folder name so each folder is its own project name
  echo "docker compose -f \"$cf\" -p \"$(basename "$dir")\""
}

discover_projects() {
  local root="$1"
  [[ -d "$root" ]] || { err "Root does not exist: $root"; exit 1; }

  # Include ROOT itself if it has a compose file
  local cf
  cf="$(compose_file_for_dir "$root")"
  [[ -n "$cf" ]] && echo "$root"

  # One level down
  local d
  while IFS= read -r -d '' d; do
    cf="$(compose_file_for_dir "$d")"
    [[ -n "$cf" ]] && echo "$d"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 | sort -z)
}

filter_projects() {
  local -a projects=("$@")
  local -a out=()

  for p in "${projects[@]}"; do
    local base inactive
    base="$(basename "$p")"
    inactive=0
    is_inactive_project "$p" && inactive=1

    # Inactive selection
    if (( ONLY_INACTIVE )); then
      (( inactive )) || { (( VERBOSE )) && warn "Skipping $base (not inactive)"; continue; }
    else
      if (( inactive )) && (( ! INCLUDE_INACTIVE )); then
        (( VERBOSE )) && warn "Skipping $base (marked inactive: $INACTIVE_MARKER)"
        continue
      fi
    fi

    # CLI project args act like "only these"
    if [[ ${#CLI_PROJECTS[@]} -gt 0 ]]; then
      contains "$base" "${CLI_PROJECTS[@]}" || { (( VERBOSE )) && warn "Skipping $base (not in CLI list)"; continue; }
    fi

    # --only filters
    if [[ ${#ONLY[@]} -gt 0 ]]; then
      contains "$base" "${ONLY[@]}" || { (( VERBOSE )) && warn "Skipping $base (not in --only list)"; continue; }
    fi

    # --exclude filters
    if [[ ${#EXCLUDES[@]} -gt 0 ]]; then
      contains "$base" "${EXCLUDES[@]}" && { (( VERBOSE )) && warn "Skipping $base (excluded)"; continue; }
    fi

    out+=("$p")
  done

  printf '%s\n' "${out[@]}"
}

running_containers_for_project() {
  local dir="$1"
  local ccmd
  ccmd="$(compose_cmd "$dir" || true)"
  [[ -n "$ccmd" ]] || return 0
  bash -lc "$ccmd ps -q" 2>/dev/null || true
}

cmd_list() {
  local -a projects=("$@")
  say "${YELLOW}Compose projects under:${NC} ${MAGENTA}${ROOT}${NC}"
  say "${YELLOW}Inactive marker:${NC} ${MAGENTA}${INACTIVE_MARKER}${NC} (skipped by default)"
  log_hdr

  for dir in "${projects[@]}"; do
    local name inactive
    name="$(basename "$dir")"
    inactive=""
    is_inactive_project "$dir" && inactive=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "${name}${inactive}" "$dir"

    local ids
    ids="$(running_containers_for_project "$dir")"
    if [[ -z "$ids" ]]; then
      say "${RED}Not running.${NC}"
      continue
    fi

    say "${CYAN}Running containers:${NC}"
    # shellcheck disable=SC2086
    docker ps --format '  - {{.Names}}  ({{.Image}})' --filter "id=$ids" 2>/dev/null || true
  done
}

cmd_status() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive
    name="$(basename "$dir")"
    inactive=""
    is_inactive_project "$dir" && inactive=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "${name}${inactive}" "$dir"
    run "bash -lc '$ccmd ps'"
  done
}

cmd_pull() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive
    name="$(basename "$dir")"
    inactive=""
    is_inactive_project "$dir" && inactive=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Pulling: ${name}${inactive}" "$dir"
    run "bash -lc '$ccmd pull'"
  done
}

cmd_update() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive
    name="$(basename "$dir")"
    inactive=""
    is_inactive_project "$dir" && inactive=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Updating: ${name}${inactive}" "$dir"
    run "bash -lc '$ccmd pull'"
    run "bash -lc '$ccmd up -d'"
  done
}

cmd_restart() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive
    name="$(basename "$dir")"
    inactive=""
    is_inactive_project "$dir" && inactive=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Restarting: ${name}${inactive}" "$dir"
    run "bash -lc '$ccmd restart'"
  done
}

cmd_down() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive
    name="$(basename "$dir")"
    inactive=""
    is_inactive_project "$dir" && inactive=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Stopping: ${name}${inactive}" "$dir"
    run "bash -lc '$ccmd down'"
  done
}

cmd_check() {
  local -a projects=("$@")
  say "${YELLOW}Checking for image updates (pull + report).${NC}"
  say "${CYAN}Note:${NC} This downloads newer images if available, but does NOT restart containers."
  log_hdr

  for dir in "${projects[@]}"; do
    local name inactive
    name="$(basename "$dir")"
    inactive=""
    is_inactive_project "$dir" && inactive=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Checking: ${name}${inactive}" "$dir"

    if (( DRY_RUN )); then
      say "${CYAN}[dry-run]${NC} would run: $ccmd pull"
      continue
    fi

    local out
    out="$(bash -lc "$ccmd pull" 2>&1 || true)"

    if echo "$out" | grep -qi 'Downloaded newer image'; then
      say "${GREEN}Update found: newer images pulled.${NC}"
    elif echo "$out" | grep -qiE 'Pull complete|Image is up to date|Already exists'; then
      say "${CYAN}No updates detected (up-to-date).${NC}"
    else
      say "${YELLOW}Pull output was inconclusive (see lines below).${NC}"
    fi

    # Show the most relevant lines
    echo "$out" | grep -E 'Downloaded newer image|Pull complete|Image is up to date|Already exists|error|Error' || true
  done
}

do_prune() {
  project_header "Pruning docker resources" "system-wide"
  run "yes | docker image prune"
  run "yes | docker network prune"
  run "yes | docker volume prune"
}

# -----------------------------
# Parse args
# -----------------------------
if [[ $# -lt 1 ]]; then usage; exit 1; fi

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    -r|--root) ROOT="${2:-}"; shift 2;;
    -x|--exclude) EXCLUDES+=("${2:-}"); shift 2;;
    -o|--only) ONLY+=("${2:-}"); shift 2;;
    --include-inactive) INCLUDE_INACTIVE=1; shift;;
    --only-inactive) ONLY_INACTIVE=1; shift;;
    -n|--dry-run) DRY_RUN=1; shift;;
    -p|--prune) DO_PRUNE=1; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    -*)
      err "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

CMD="${1:-}"; shift || true
CLI_PROJECTS=("$@")

need_bin docker

# Discover + filter
ALL_PROJECTS=()
while IFS= read -r p; do ALL_PROJECTS+=("$p"); done < <(discover_projects "$ROOT")

if [[ ${#ALL_PROJECTS[@]} -eq 0 ]]; then
  err "No compose projects found under: $ROOT"
  exit 1
fi

PROJECTS=()
while IFS= read -r p; do PROJECTS+=("$p"); done < <(filter_projects "${ALL_PROJECTS[@]}")

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  err "No matching projects after filters. Check names/--root/--exclude/--only or inactive flags."
  exit 1
fi

# -----------------------------
# Execute command
# -----------------------------
case "$CMD" in
  list)    cmd_list "${PROJECTS[@]}" ;;
  status)  cmd_status "${PROJECTS[@]}" ;;
  check)   cmd_check "${PROJECTS[@]}" ;;
  pull)    cmd_pull "${PROJECTS[@]}" ;;
  update)  cmd_update "${PROJECTS[@]}" ;;
  restart) cmd_restart "${PROJECTS[@]}" ;;
  down)    cmd_down "${PROJECTS[@]}" ;;
  prune)   DO_PRUNE=1; cmd_list "${PROJECTS[@]}" ;;  # prune-only still shows what's selected
  *)
    err "Unknown command: $CMD"
    usage
    exit 1
    ;;
esac

if (( DO_PRUNE )); then
  do_prune
fi

log_hdr
say "${GREEN}Done.${NC}"
