#!/usr/bin/env bash
_v24_config_requested_path="${QS_SETTINGS:-}"
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"
CONFIG_SETTINGS_JSON="${_v24_config_requested_path:-$QS_SETTINGS}"
unset _v24_config_requested_path

_config_ensure_settings() (
    mkdir -p -- "$(dirname -- "$CONFIG_SETTINGS_JSON")" || return
    exec 9>"${CONFIG_SETTINGS_JSON}.lock"
    flock 9 || return
    # Existing empty/corrupt files are never reset by a reader.
    if [[ ! -e "$CONFIG_SETTINGS_JSON" ]]; then
        local tmp
        tmp=$(mktemp "${CONFIG_SETTINGS_JSON}.tmp.XXXXXX") || return
        printf '{}' > "$tmp"
        chmod 600 "$tmp"
        mv -f -- "$tmp" "$CONFIG_SETTINGS_JSON"
    fi
)

get_setting() {
    local key="$1" fallback="${2:-}" val
    val=$(jq -r --arg k "$key" 'if has($k) and .[$k] != null then .[$k] else "__MISSING__" end' "$CONFIG_SETTINGS_JSON" 2>/dev/null) || val="__MISSING__"
    if [[ "$val" == "__MISSING__" ]]; then printf '%s' "$fallback"; else printf '%s' "$val"; fi
}

update_settings_bulk() (
    local json_obj="$1" backup="${CONFIG_SETTINGS_JSON}.v24-last-good" tmp backup_tmp source_path
    _config_ensure_settings || return
    exec 9>"${CONFIG_SETTINGS_JSON}.lock"
    flock 9 || return
    source_path="$CONFIG_SETTINGS_JSON"
    if ! jq -e 'type == "object"' "$source_path" >/dev/null 2>&1; then
        jq -e 'type == "object"' "$backup" >/dev/null 2>&1 || return 65
        source_path="$backup"
    fi
    jq -e 'type == "object"' <<< "$json_obj" >/dev/null 2>&1 || return 65
    tmp=$(mktemp "${CONFIG_SETTINGS_JSON}.tmp.XXXXXX") || return
    trap 'rm -f -- "$tmp" "${backup_tmp:-}"' EXIT
    jq --argjson patch "$json_obj" '. + $patch' "$source_path" > "$tmp" || return
    jq -e 'type == "object"' "$tmp" >/dev/null || return
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$CONFIG_SETTINGS_JSON" || return
    backup_tmp=$(mktemp "${backup}.tmp.XXXXXX") || return
    cp -f -- "$CONFIG_SETTINGS_JSON" "$backup_tmp" || return
    chmod 600 "$backup_tmp"
    mv -f -- "$backup_tmp" "$backup"
)

set_setting() {
    local key="$1" value="$2" json_value patch
    if jq -e . <<< "$value" >/dev/null 2>&1; then json_value="$value"; else json_value=$(jq -Rn --arg v "$value" '$v'); fi
    patch=$(jq -cn --arg k "$key" --argjson v "$json_value" '{($k): $v}') || return
    update_settings_bulk "$patch"
}
