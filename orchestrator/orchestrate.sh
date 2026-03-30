#!/usr/bin/env bash
# orchestrator/orchestrate.sh
#
# NixCTF VM Lifecycle Orchestrator
#
# Manages the full lifecycle of per-participant challenge VMs:
#   launch   — Build (if needed) and start a participant's VM
#   reset    — Destroy and re-launch a participant's VM (clean state)
#   destroy  — Stop and remove a participant's VM process
#   status   — Show running VMs and their ports
#   list     — List all known participant configurations
#
# Usage:
#   nixctf-orchestrate launch  <flake-ref> <participant-id>
#   nixctf-orchestrate reset   <flake-ref> <participant-id>
#   nixctf-orchestrate destroy <participant-id>
#   nixctf-orchestrate status
#   nixctf-orchestrate list    <flake-ref>
#
# <flake-ref> is a Nix flake reference, e.g. "/path/to/CTF" or
#             "github:0x6a64/CTF".
#
# The orchestrator stores PIDs and metadata in NIXCTF_STATE_DIR
# (default: /var/lib/nixctf).
#
# Example:
#   nixctf-orchestrate launch /etc/nixctf player1
#   nixctf-orchestrate status
#   nixctf-orchestrate reset  /etc/nixctf player1
#   nixctf-orchestrate destroy player1
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
NIXCTF_STATE_DIR="${NIXCTF_STATE_DIR:-/var/lib/nixctf}"
NIXCTF_LOG_DIR="${NIXCTF_LOG_DIR:-/var/log/nixctf}"
NIXCTF_INACTIVITY_TIMEOUT="${NIXCTF_INACTIVITY_TIMEOUT:-3600}"  # seconds

mkdir -p "$NIXCTF_STATE_DIR" "$NIXCTF_LOG_DIR"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date -u +%FT%TZ)] [nixctf] $*" >&2; }

die() { log "ERROR: $*"; exit 1; }

# Validate participant IDs to prevent path traversal and shell injection.
# IDs may only contain alphanumerics, hyphens, and underscores.
validate_id() {
    local id="$1"
    if [[ ! "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        die "Invalid participant ID '$id': must match [a-zA-Z0-9_-]+"
    fi
}

pid_file()  { echo "$NIXCTF_STATE_DIR/$1.pid"; }
port_file() { echo "$NIXCTF_STATE_DIR/$1.port"; }
meta_file() { echo "$NIXCTF_STATE_DIR/$1.json"; }

is_running() {
    local pid_path
    pid_path="$(pid_file "$1")"
    [[ -f "$pid_path" ]] || return 1
    local pid
    pid="$(cat "$pid_path")"
    kill -0 "$pid" 2>/dev/null
}

vm_runner_attr() {
    # Returns the Nix attribute path for the declared runner of a VM.
    # nixosConfigurations.<id>.config.microvm.declaredRunner
    local flake_ref="$1" participant_id="$2"
    echo "${flake_ref}#nixosConfigurations.${participant_id}.config.microvm.declaredRunner"
}

# ---------------------------------------------------------------------------
# launch
# ---------------------------------------------------------------------------
cmd_launch() {
    local flake_ref="$1" participant_id="$2"
    validate_id "$participant_id"
    local attr
    attr="$(vm_runner_attr "$flake_ref" "$participant_id")"

    if is_running "$participant_id"; then
        log "VM for '$participant_id' is already running (PID $(cat "$(pid_file "$participant_id")"))"
        return 0
    fi

    log "Building runner for '$participant_id' from $attr ..."
    local store_path
    store_path="$(nix build --no-link --print-out-paths "$attr" 2>&1 | tee -a "$NIXCTF_LOG_DIR/${participant_id}.log" | tail -1)"

    # Locate the runner executable.  microvm's declaredRunner is a
    # writeShellScriptBin derivation with the binary at bin/microvm-run.
    local runner=""
    if [[ -x "$store_path" ]]; then
        runner="$store_path"
    elif [[ -x "$store_path/bin/microvm-run" ]]; then
        runner="$store_path/bin/microvm-run"
    else
        # Fallback: find any executable in the output.
        runner="$(find "$store_path" -maxdepth 3 -type f -executable 2>/dev/null | head -1 || true)"
    fi

    [[ -n "$runner" && -x "$runner" ]] \
        || die "Could not locate executable runner in '$store_path'"

    log "Launching VM for '$participant_id' ..."
    "$runner" \
        >> "$NIXCTF_LOG_DIR/${participant_id}.log" 2>&1 &
    local vm_pid=$!
    echo "$vm_pid" > "$(pid_file "$participant_id")"

    # Persist metadata.
    local port
    port="$(cat "$(port_file "$participant_id")" 2>/dev/null || echo "unknown")"
    jq -n \
        --arg id        "$participant_id" \
        --arg pid       "$vm_pid" \
        --arg port      "$port" \
        --arg started   "$(date -u +%FT%TZ)" \
        --arg flake_ref "$flake_ref" \
        '{id: $id, pid: $pid, port: $port, started: $started, flake_ref: $flake_ref}' \
        > "$(meta_file "$participant_id")"

    log "VM for '$participant_id' started (PID $vm_pid)"
}

# ---------------------------------------------------------------------------
# destroy
# ---------------------------------------------------------------------------
cmd_destroy() {
    local participant_id="$1"
    validate_id "$participant_id"
    local pid_path
    pid_path="$(pid_file "$participant_id")"

    if ! is_running "$participant_id"; then
        log "No running VM found for '$participant_id'"
        rm -f "$pid_path" "$(meta_file "$participant_id")"
        return 0
    fi

    local pid
    pid="$(cat "$pid_path")"
    log "Stopping VM for '$participant_id' (PID $pid) ..."
    kill "$pid" 2>/dev/null || true

    # Wait up to 10 seconds for graceful shutdown, then force.
    local i
    for i in $(seq 1 10); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true

    rm -f "$pid_path" "$(meta_file "$participant_id")"
    log "VM for '$participant_id' destroyed."
}

# ---------------------------------------------------------------------------
# reset
# ---------------------------------------------------------------------------
cmd_reset() {
    local flake_ref="$1" participant_id="$2"
    log "Resetting VM for '$participant_id' ..."
    cmd_destroy "$participant_id"
    # Ephemeral overlay is discarded when the process exits — no extra cleanup.
    cmd_launch "$flake_ref" "$participant_id"
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
cmd_status() {
    echo "NixCTF VM Status"
    echo "================"
    local found=0
    for meta in "$NIXCTF_STATE_DIR"/*.json; do
        [[ -f "$meta" ]] || continue
        found=1
        local id pid port started
        id="$(jq -r .id      "$meta")"
        pid="$(jq -r .pid     "$meta")"
        port="$(jq -r .port    "$meta")"
        started="$(jq -r .started "$meta")"
        if kill -0 "$pid" 2>/dev/null; then
            echo "  ✔ $id  PID=$pid  SSH-port=$port  started=$started"
        else
            echo "  ✘ $id  (not running, stale PID=$pid)"
        fi
    done
    if [[ $found -eq 0 ]]; then
        echo "  (no VMs registered)"
    fi
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
cmd_list() {
    local flake_ref="$1"
    log "Evaluating flake to list participants: $flake_ref ..."
    nix eval --json "${flake_ref}#nixosConfigurations" --apply 'cfgs: builtins.attrNames cfgs' \
        | jq -r '.[]'
}

# ---------------------------------------------------------------------------
# set-port  (internal helper — record the port for a participant)
# ---------------------------------------------------------------------------
cmd_set_port() {
    local participant_id="$1" port="$2"
    validate_id "$participant_id"
    echo "$port" > "$(port_file "$participant_id")"
}

# ---------------------------------------------------------------------------
# Inactivity watchdog
#
# Run this as a systemd timer or cron job.  It destroys any VM whose log has
# not been written to in $NIXCTF_INACTIVITY_TIMEOUT seconds.
# ---------------------------------------------------------------------------
cmd_watchdog() {
    log "Running inactivity watchdog (timeout=${NIXCTF_INACTIVITY_TIMEOUT}s) ..."
    for meta in "$NIXCTF_STATE_DIR"/*.json; do
        [[ -f "$meta" ]] || continue
        local id
        id="$(jq -r .id "$meta")"
        local log_file="$NIXCTF_LOG_DIR/${id}.log"
        if [[ -f "$log_file" ]]; then
            # stat -c is GNU coreutils syntax; this script is Linux-only.
            local last_write
            last_write="$(stat -c %Y "$log_file")"
            local now
            now="$(date +%s)"
            local age=$(( now - last_write ))
            if (( age > NIXCTF_INACTIVITY_TIMEOUT )); then
                log "VM '$id' inactive for ${age}s — destroying."
                cmd_destroy "$id"
            fi
        fi
    done
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: nixctf-orchestrate <command> [args...]

Commands:
  launch   <flake-ref> <participant-id>   Build and start a VM
  reset    <flake-ref> <participant-id>   Destroy and re-launch a VM
  destroy  <participant-id>               Stop a VM
  status                                  Show all VMs
  list     <flake-ref>                    List participant IDs in a flake
  set-port <participant-id> <port>        Record the SSH port for a participant
  watchdog                                Destroy VMs inactive > timeout

Environment variables:
  NIXCTF_STATE_DIR           State directory  (default: /var/lib/nixctf)
  NIXCTF_LOG_DIR             Log directory    (default: /var/log/nixctf)
  NIXCTF_INACTIVITY_TIMEOUT  Seconds before inactivity GC (default: 3600)
EOF
}

case "${1:-}" in
    launch)   cmd_launch   "${2:?flake-ref required}"  "${3:?participant-id required}" ;;
    reset)    cmd_reset    "${2:?flake-ref required}"  "${3:?participant-id required}" ;;
    destroy)  cmd_destroy  "${2:?participant-id required}" ;;
    status)   cmd_status ;;
    list)     cmd_list     "${2:?flake-ref required}" ;;
    set-port) cmd_set_port "${2:?participant-id required}" "${3:?port required}" ;;
    watchdog) cmd_watchdog ;;
    *)        usage; exit 1 ;;
esac
