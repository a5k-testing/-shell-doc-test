#!/sbin/sh
# @file common-functions.sh
# @brief A library with common functions used during flashable ZIP installation.
# SPDX-FileCopyrightText: (c) 2016 ale5000
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileType: SOURCE

# shellcheck disable=SC3043
# SC3043: In POSIX sh, local is undefined

# @section Example functions

# @description Setup an app for later installation.
#
# @arg $1 boolean Default installation setting
# @arg $2 string Name of the app
# @arg $3 string Filename of the app
# @arg $4 string Folder of the app
#
# @exitcode 0 If successful.
setup_app() {
  local _install _app_conf _min_sdk _max_sdk
  _install="${1:-0}"
  _app_conf="$(file_get_first_line_that_start_with "${4:?}/${3:?}|" "${TMP_PATH}/files/system-apps/file-list.dat")" || ui_error "Failed to get app config for '${2}'"
  _min_sdk="$(string_split "${_app_conf:?}" 2)" || ui_error "Failed to get min SDK for '${2}'"
  _max_sdk="$(string_split "${_app_conf:?}" 3)" || ui_error "Failed to get max SDK for '${2}'"
  _output_name="$(string_split "${_app_conf:?}" 4)" || ui_error "Failed to get output name for '${2}'"

  if test "${API:?}" -ge "${_min_sdk:?}" && test "${API:?}" -le "${_max_sdk:-99}"; then
    if test "${live_setup_enabled:?}" = 'true'; then
      choose "Do you want to install ${2:?}?" '+) Yes' '-) No'
      if test "${?}" -eq 3; then _install='1'; else _install='0'; fi
    fi

    if test "${_install:?}" -ne 0; then
      echo move_rename_file "${TMP_PATH}/files/system-apps/${4:?}/${3:?}.apk" "${TMP_PATH}/files/${4:?}/${_output_name:?}.apk"
    fi
  else
    ui_debug "Skipped: ${2:?}"
  fi
}
