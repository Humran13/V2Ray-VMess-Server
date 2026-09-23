#!/usr/bin/env bash
# users.sh - VMess user store (JSON), atomic and lock-protected.
# Schema: {"users":[{"name":str,"uuid":str,"enabled":bool,"created":ISO8601}]}

if [[ -n "${VMESS_USERS_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_USERS_LOADED=1

VMESS_USERS_LOCK="${VMESS_STATE_DIR}/.users.lock"

users_init() {
  if [[ ! -f "$VMESS_USERS_FILE" ]]; then
    atomic_write "$VMESS_USERS_FILE" '{"users":[]}' 0640
  fi
}

users_exists() {
  local name=$1
  jq -e --arg n "$name" '.users[] | select(.name==$n)' "$VMESS_USERS_FILE" >/dev/null 2>&1
}

users_uuid_exists() {
  local uuid=$1
  jq -e --arg u "$uuid" '.users[] | select(.uuid==$u)' "$VMESS_USERS_FILE" >/dev/null 2>&1
}

users_add() {
  local name=$1 uuid=${2:-}
  require_valid "$name" valid_username "username"
  users_init
  with_lock "$VMESS_USERS_LOCK" _users_add_locked "$name" "$uuid"
}

_users_add_locked() {
  local name=$1 uuid=$2
  if users_exists "$name"; then die "User already exists: $name"; fi
  if [[ -z "$uuid" ]]; then uuid=$(uuidgen); fi
  require_valid "$uuid" valid_uuid "UUID"
  if users_uuid_exists "$uuid"; then die "UUID already assigned to another user."; fi
  local created new
  created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  new=$(jq --arg n "$name" --arg u "$uuid" --arg c "$created" \
    '.users += [{name:$n, uuid:$u, enabled:true, created:$c}]' "$VMESS_USERS_FILE")
  atomic_write "$VMESS_USERS_FILE" "$new" 0640
  echo "$uuid"
}

users_list() {
  jq -r '.users[] | [.name, .uuid, (.enabled|tostring), .created] | @tsv' "$VMESS_USERS_FILE"
}

users_get_json() {
  local name=$1
  jq -e --arg n "$name" '.users[] | select(.name==$n)' "$VMESS_USERS_FILE"
}

users_get_uuid() {
  local name=$1
  jq -r --arg n "$name" '.users[] | select(.name==$n) | .uuid' "$VMESS_USERS_FILE"
}

users_set_enabled() {
  local name=$1 enabled=$2
  users_exists "$name" || die "No such user: $name"
  with_lock "$VMESS_USERS_LOCK" _users_set_enabled_locked "$name" "$enabled"
}

_users_set_enabled_locked() {
  local name=$1 enabled=$2 new
  new=$(jq --arg n "$name" --argjson e "$enabled" \
    '(.users[] | select(.name==$n) | .enabled) = $e' "$VMESS_USERS_FILE")
  atomic_write "$VMESS_USERS_FILE" "$new" 0640
}

users_delete() {
  local name=$1
  users_exists "$name" || die "No such user: $name"
  with_lock "$VMESS_USERS_LOCK" _users_delete_locked "$name"
}

_users_delete_locked() {
  local name=$1 new
  new=$(jq --arg n "$name" '.users |= map(select(.name != $n))' "$VMESS_USERS_FILE")
  atomic_write "$VMESS_USERS_FILE" "$new" 0640
}

# Enabled users only, as JSON array of {id, email} for the Xray VMess inbound clients list.
users_enabled_clients_json() {
  jq -c '[.users[] | select(.enabled==true) | {id: .uuid, email: .name}]' "$VMESS_USERS_FILE"
}

users_count() {
  jq -r '.users | length' "$VMESS_USERS_FILE"
}
