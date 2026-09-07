#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

CONFIG_SETTINGS_JSON="${QS_SETTINGS:-$HOME/.config/serpantinum/settings.json}"

_config_ensure_settings() {
    local dir
    dir="$(dirname "$CONFIG_SETTINGS_JSON")"
    [[ -d "$dir" ]] || mkdir -p "$dir"
    [[ -s "$CONFIG_SETTINGS_JSON" ]] || echo '{}' > "$CONFIG_SETTINGS_JSON"
}

get_setting() {
    local key="$1"
    local fallback="${2:-}"
    _config_ensure_settings
    local val
    val="$(jq -r --arg k "$key" 'if has($k) then .[$k] else "__MISSING__" end' "$CONFIG_SETTINGS_JSON" 2>/dev/null)"
    if [[ "$val" == "__MISSING__" || "$val" == "null" ]]; then
        printf '%s' "$fallback"
    else
        printf '%s' "$val"
    fi
}

set_setting() {
    local key="$1"
    local value="$2"
    local backup="${CONFIG_SETTINGS_JSON}.v24-last-good"
    exec 9>"${CONFIG_SETTINGS_JSON}.lock"
    flock 9
    _config_ensure_settings

    if ! jq -e 'type == "object"' "$CONFIG_SETTINGS_JSON" >/dev/null 2>&1; then
        if jq -e 'type == "object"' "$backup" >/dev/null 2>&1; then
            cp -f -- "$backup" "$CONFIG_SETTINGS_JSON"
        else
            return 1
        fi
    fi

    local json_value
    if echo "$value" | jq -e . > /dev/null 2>&1; then
        json_value="$value"
    else
        json_value="$(jq -Rn --arg v "$value" '$v')"
    fi

    local tmp
    tmp="$(mktemp "${CONFIG_SETTINGS_JSON}.tmp.XXXXXX")"
    if jq --arg k "$key" --argjson v "$json_value" '. + {($k): $v}' "$CONFIG_SETTINGS_JSON" > "$tmp" 2>/dev/null; then
        if jq -e 'type == "object"' "$tmp" > /dev/null 2>&1; then
            chmod 600 "$tmp"
            mv -f -- "$tmp" "$CONFIG_SETTINGS_JSON"
            local backup_tmp
            backup_tmp="$(mktemp "${backup}.tmp.XXXXXX")"
            cp -f -- "$CONFIG_SETTINGS_JSON" "$backup_tmp"
            chmod 600 "$backup_tmp"
            mv -f -- "$backup_tmp" "$backup"
            return 0
        fi
    fi
    rm -f -- "$tmp"
    return 1
}

update_settings_bulk() {
    local json_obj="$1"
    local backup="${CONFIG_SETTINGS_JSON}.v24-last-good"
    exec 9>"${CONFIG_SETTINGS_JSON}.lock"
    flock 9
    _config_ensure_settings

    if ! jq -e 'type == "object"' "$CONFIG_SETTINGS_JSON" >/dev/null 2>&1; then
        if jq -e 'type == "object"' "$backup" >/dev/null 2>&1; then
            cp -f -- "$backup" "$CONFIG_SETTINGS_JSON"
        else
            return 1
        fi
    fi

    local tmp
    tmp="$(mktemp "${CONFIG_SETTINGS_JSON}.tmp.XXXXXX")"
    if jq --argjson patch "$json_obj" '. + $patch' "$CONFIG_SETTINGS_JSON" > "$tmp" 2>/dev/null; then
        if jq -e 'type == "object"' "$tmp" > /dev/null 2>&1; then
            chmod 600 "$tmp"
            mv -f -- "$tmp" "$CONFIG_SETTINGS_JSON"
            local backup_tmp
            backup_tmp="$(mktemp "${backup}.tmp.XXXXXX")"
            cp -f -- "$CONFIG_SETTINGS_JSON" "$backup_tmp"
            chmod 600 "$backup_tmp"
            mv -f -- "$backup_tmp" "$backup"
            return 0
        fi
    fi
    rm -f -- "$tmp"
    return 1
}
