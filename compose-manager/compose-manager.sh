#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# compose-manager.sh
# Discover + manage Docker Compose projects under a root directory.
# Supports .inactive marker files to skip projects by default,
# and provides convenience commands:
#   inactive on <project> / inactive off <project>
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
  list                  List discovered projects + running containers per project
  status                Show 'docker compose ps' per project
  check                 Check for image updates (pull + summarized report; no up)
  pull                  Pull images for projects
  update                Pull + up -d for projects
  restart               Restart services for projects
  down                  docker compose down for projects
  prune                 Run docker prune (images, networks, volumes)

Inactive management:
  inactive list         List projects marked inactive
  inactive on  <name>   Mark a project inactive (creates .inactive)
  inactive off <name>   Mark a project active (removes .inactive)

Global options:
  -r, --root <path>        Root folder containing projects (default: /docker)
  -x, --exclude <name>     Exclude a project by folder name (repeatable)
  -o, --only <name>        Only include a project by folder name (repeatable)
      --include-inactive   Include projects with .inactive marker (normally skipped)
      --only-inactive      Only include projects with .inactive marker
  -n, --dry-run            Show what would be done (no changes)
  -p, --prune              Run prune at the end (after pull/update/etc.)
  -v, --verbose            More output (shows skip reasons)
  -h, --help               Show help

Notes:
  - A project is any directory (ROOT itself or one level below ROOT) containing:
      compose.yml | compose.yaml | docker-compose.yml | docker-compose.yaml
  - Mark a project inactive by creating:
      <project>/.inactive

Examples:
  $(basename "$0") --root /home/bstetler/docker list
  $(basename "$0") --root /home/bstetler/docker update
  $(basename "$0") --root /home/bstetler/docker update sonarr radarr
  $(basename "$0") --root /home/bstetler/docker --exclude homeassistant update
  $(basename "$0") --root /home/bstetler/docker check
  $(basename "$0") --root /home/bstetler/docker inactive on stable-diffusion-webui
  $(basename "$0") --root /home/bstetler/docker inactive off stable-diffusion-webui
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

project_dir_by_name() {
  # Finds a project directory by folder name (within discovery scope)
  local name="$1"
  local -a all=()
  while IFS= read -r p; do all+=("$p"); done < <(discover_projects "$ROOT")

  local p base
  for p in "${all[@]}"; do
    base="$(basename "$p")"
    if [[ "$base" == "$name" ]]; then
      echo "$p"
      return 0
    fi
  done

  echo ""
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
    local name inactive_tag
    name="$(basename "$dir")"
    inactive_tag=""
    is_inactive_project "$dir" && inactive_tag=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "${name}${inactive_tag}" "$dir"

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
    local name inactive_tag
    name="$(basename "$dir")"
    inactive_tag=""
    is_inactive_project "$dir" && inactive_tag=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "${name}${inactive_tag}" "$dir"
    run "bash -lc '$ccmd ps'"
  done
}

cmd_pull() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive_tag
    name="$(basename "$dir")"
    inactive_tag=""
    is_inactive_project "$dir" && inactive_tag=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Pulling: ${name}${inactive_tag}" "$dir"
    run "bash -lc '$ccmd pull'"
  done
}

cmd_update() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive_tag
    name="$(basename "$dir")"
    inactive_tag=""
    is_inactive_project "$dir" && inactive_tag=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Updating: ${name}${inactive_tag}" "$dir"
    run "bash -lc '$ccmd pull'"
    run "bash -lc '$ccmd up -d'"
  done
}

cmd_restart() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive_tag
    name="$(basename "$dir")"
    inactive_tag=""
    is_inactive_project "$dir" && inactive_tag=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Restarting: ${name}${inactive_tag}" "$dir"
    run "bash -lc '$ccmd restart'"
  done
}

cmd_down() {
  local -a projects=("$@")
  for dir in "${projects[@]}"; do
    local name inactive_tag
    name="$(basename "$dir")"
    inactive_tag=""
    is_inactive_project "$dir" && inactive_tag=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Stopping: ${name}${inactive_tag}" "$dir"
    run "bash -lc '$ccmd down'"
  done
}

cmd_check() {
  local -a projects=("$@")
  say "${YELLOW}Checking for image updates (pull + report).${NC}"
  say "${CYAN}Note:${NC} This downloads newer images if available, but does NOT restart containers."
  log_hdr

  for dir in "${projects[@]}"; do
    local name inactive_tag
    name="$(basename "$dir")"
    inactive_tag=""
    is_inactive_project "$dir" && inactive_tag=" ${YELLOW}[inactive]${NC}"

    local ccmd
    ccmd="$(compose_cmd "$dir" || true)"
    [[ -n "$ccmd" ]] || { (( VERBOSE )) && warn "Skipping (no compose file): $dir"; continue; }

    project_header "Checking: ${name}${inactive_tag}" "$dir"

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

    echo "$out" | grep -E 'Downloaded newer image|Pull complete|Image is up to date|Already exists|error|Error' || true
  done
}

do_prune() {
  project_header "Pruning docker resources" "system-wide"
  run "yes | docker image prune"
  run "yes | docker network prune"
  run "yes | docker volume prune"
}

cmd_inactive_list() {
  local -a all=()
  while IFS= read -r p; do all+=("$p"); done < <(discover_projects "$ROOT")

  say "${YELLOW}Inactive projects under:${NC} ${MAGENTA}${ROOT}${NC}"
  log_hdr

  local found=0
  for dir in "${all[@]}"; do
    if is_inactive_project "$dir"; then
      found=1
      say "  - ${MAGENTA}$(basename "$dir")${NC}  (${dir})"
    fi
  done

  if (( ! found )); then
    say "${CYAN}None marked inactive.${NC}"
  fi
}

cmd_inactive_on() {
  local name="${1:-}"
  [[ -n "$name" ]] || { err "inactive on requires a project name"; exit 1; }

  local dir
  dir="$(project_dir_by_name "$name")"
  [[ -n "$dir" ]] || { err "Project not found under $ROOT: $name"; exit 1; }

  if (( DRY_RUN )); then
    say "${CYAN}[dry-run]${NC} would create: $dir/$INACTIVE_MARKER"
    return 0
  fi

  touch "$dir/$INACTIVE_MARKER"
  say "${GREEN}Marked inactive:${NC} ${MAGENTA}$name${NC}  (created $INACTIVE_MARKER)"
}

cmd_inactive_off() {
  local name="${1:-}"
  [[ -n "$name" ]] || { err "inactive off requires a project name"; exit 1; }

  local dir
  dir="$(project_dir_by_name "$name")"
  [[ -n "$dir" ]] || { err "Project not found under $ROOT: $name"; exit 1; }

  if (( DRY_RUN )); then
    say "${CYAN}[dry-run]${NC} would remove: $dir/$INACTIVE_MARKER"
    return 0
  fi

  if [[ -f "$dir/$INACTIVE_MARKER" ]]; then
    rm -f "$dir/$INACTIVE_MARKER"
    say "${GREEN}Marked active:${NC} ${MAGENTA}$name${NC}  (removed $INACTIVE_MARKER)"
  else
    say "${CYAN}Already active:${NC} ${MAGENTA}$name${NC}  (no $INACTIVE_MARKER found)"
  fi
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

need_bin docker

# Special: inactive subcommands don’t need full filtering logic
if [[ "$CMD" == "inactive" ]]; then
  sub="${1:-}"; shift || true
  case "$sub" in
    list) cmd_inactive_list ;;
    on)   cmd_inactive_on "${1:-}" ;;
    off)  cmd_inactive_off "${1:-}" ;;
    *) err "Unknown inactive command: ${sub:-<none>}"; usage; exit 1 ;;
  esac
  exit 0
fi

# Remaining args are project names
CLI_PROJECTS=("$@")

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

# Execute command
case "$CMD" in
  list)    cmd_list "${PROJECTS[@]}" ;;
  status)  cmd_status "${PROJECTS[@]}" ;;
  check)   cmd_check "${PROJECTS[@]}" ;;
  pull)    cmd_pull "${PROJECTS[@]}" ;;
  update)  cmd_update "${PROJECTS[@]}" ;;
  restart) cmd_restart "${PROJECTS[@]}" ;;
  down)    cmd_down "${PROJECTS[@]}" ;;
  prune)   DO_PRUNE=1; cmd_list "${PROJECTS[@]}" ;;
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
