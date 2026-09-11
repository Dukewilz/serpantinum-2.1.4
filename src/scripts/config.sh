#!/usr/bin/env bash

# caching.sh defines QS_SETTINGS for the installed tree. Preserve an explicit
# test/user override before sourcing it so all writers target the same file.
CONFIG_SETTINGS_OVERRIDE="${QS_SETTINGS:-}"
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"
CONFIG_SETTINGS_JSON="${CONFIG_SETTINGS_OVERRIDE:-${QS_SETTINGS:-$HOME/.config/serpantinum/settings.json}}"

_config_valid_object() {
    [[ -s "$1" ]] && jq -e 'type == "object"' "$1" >/dev/null 2>&1
}

_config_backup_unlocked() {
    local backup="${CONFIG_SETTINGS_JSON}.v24-last-good"
    local backup_tmp
    backup_tmp="$(mktemp "${backup}.tmp.XXXXXX")" || return 1
    if cp -f -- "$CONFIG_SETTINGS_JSON" "$backup_tmp" && chmod 600 "$backup_tmp"; then
        mv -f -- "$backup_tmp" "$backup"
    else
        rm -f -- "$backup_tmp"
        return 1
    fi
}

_config_ensure_settings_unlocked() {
    local backup="${CONFIG_SETTINGS_JSON}.v24-last-good"
    if _config_valid_object "$CONFIG_SETTINGS_JSON"; then
        _config_valid_object "$backup" || _config_backup_unlocked
        return
    fi
    if _config_valid_object "$backup"; then
        cp -f -- "$backup" "$CONFIG_SETTINGS_JSON"
        chmod 600 "$CONFIG_SETTINGS_JSON"
        return
    fi
    # Bootstrap only a truly missing file. Existing empty/malformed JSON is a
    # recovery condition and must never be replaced by defaults silently.
    [[ ! -e "$CONFIG_SETTINGS_JSON" ]] || return 1
    local tmp
    tmp="$(mktemp "${CONFIG_SETTINGS_JSON}.tmp.XXXXXX")" || return 1
    printf '{}' > "$tmp"
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$CONFIG_SETTINGS_JSON"
    _config_backup_unlocked
}

_config_ensure_settings() {
    mkdir -p -- "$(dirname -- "$CONFIG_SETTINGS_JSON")" || return 1
    ( flock 8; _config_ensure_settings_unlocked ) 8>"${CONFIG_SETTINGS_JSON}.lock"
}

get_setting() {
    local key="$1"
    local fallback="${2:-}"
    _config_ensure_settings || return 1
    local val
    val="$(
        flock 8
        jq -r --arg k "$key" 'if has($k) then .[$k] else "__MISSING__" end' "$CONFIG_SETTINGS_JSON" 2>/dev/null
    )" 8>"${CONFIG_SETTINGS_JSON}.lock" || return 1
    if [[ "$val" == "__MISSING__" || "$val" == "null" ]]; then
        printf '%s' "$fallback"
    else
        printf '%s' "$val"
    fi
}

set_setting() {
    local key="$1"
    local value="$2"
    mkdir -p -- "$(dirname -- "$CONFIG_SETTINGS_JSON")" || return 1
    (
        flock 8
        _config_ensure_settings_unlocked || exit 1

        local json_value tmp
        if printf '%s' "$value" | jq -e . >/dev/null 2>&1; then
            json_value="$value"
        else
            json_value="$(jq -Rn --arg v "$value" '$v')" || exit 1
        fi

        tmp="$(mktemp "${CONFIG_SETTINGS_JSON}.tmp.XXXXXX")" || exit 1
        trap 'rm -f -- "$tmp"' EXIT
        jq --arg k "$key" --argjson v "$json_value" \
            'if type == "object" then . + {($k): $v} else error("settings root is not an object") end' \
            "$CONFIG_SETTINGS_JSON" > "$tmp" || exit 1
        jq -e 'type == "object"' "$tmp" >/dev/null || exit 1
        chmod 600 "$tmp"
        mv -f -- "$tmp" "$CONFIG_SETTINGS_JSON"
        trap - EXIT
        _config_backup_unlocked
    ) 8>"${CONFIG_SETTINGS_JSON}.lock"
}

update_settings_bulk() {
    local json_obj="$1"
    printf '%s' "$json_obj" | jq -e 'type == "object"' >/dev/null 2>&1 || return 1
    mkdir -p -- "$(dirname -- "$CONFIG_SETTINGS_JSON")" || return 1
    (
        flock 8
        _config_ensure_settings_unlocked || exit 1
        local tmp
        tmp="$(mktemp "${CONFIG_SETTINGS_JSON}.tmp.XXXXXX")" || exit 1
        trap 'rm -f -- "$tmp"' EXIT
        jq --argjson patch "$json_obj" \
            'if type == "object" then . + $patch else error("settings root is not an object") end' \
            "$CONFIG_SETTINGS_JSON" > "$tmp" || exit 1
        jq -e 'type == "object"' "$tmp" >/dev/null || exit 1
        chmod 600 "$tmp"
        mv -f -- "$tmp" "$CONFIG_SETTINGS_JSON"
        trap - EXIT
        _config_backup_unlocked
    ) 8>"${CONFIG_SETTINGS_JSON}.lock"
}
