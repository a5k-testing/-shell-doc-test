#!/sbin/sh
# @file common-functions.sh
# @brief A library with common functions used during flashable ZIP installation.
# SPDX-FileCopyrightText: (c) 2016 ale5000
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileType: SOURCE

# shellcheck disable=SC3043
# SC3043: In POSIX sh, local is undefined

if test -z "${RECOVERY_PIPE:-}" || test -z "${OUTFD:-}" || test -z "${ZIPFILE:-}" || test -z "${TMP_PATH:-}" || test -z "${DEBUG_LOG:-}"; then
  echo 'Some variables are NOT set.'
  exit 90
fi

mkdir -p "${TMP_PATH:?}/func-tmp" || ui_error 'Failed to create the functions temp folder'


# @section Message related functions

_show_text_on_recovery()
{
  if test "${BOOTMODE:?}" = 'true'; then
    printf '%s\n' "${1?}"
    return
  elif test -e "${RECOVERY_PIPE:?}"; then
    printf 'ui_print %s\nui_print\n' "${1?}" >> "${RECOVERY_PIPE:?}"
  else
    printf 'ui_print %s\nui_print\n' "${1?}" 1>&"${OUTFD:?}"
  fi

  if test "${DEBUG_LOG:?}" -ne 0; then printf '%s\n' "${1?}"; fi
}

ui_error()
{
  ERROR_CODE=91
  if test -n "${2:-}"; then ERROR_CODE="${2:?}"; fi
  _show_text_on_recovery "ERROR: ${1:?}"
  1>&2 printf '\033[1;31m%s\033[0m\n' "ERROR ${ERROR_CODE:?}: ${1:?}"
  abort '' 2>/dev/null || exit "${ERROR_CODE:?}"
}

ui_warning()
{
  _show_text_on_recovery "WARNING: ${1:?}"
  1>&2 printf '\033[0;33m%s\033[0m\n' "WARNING: ${1:?}"
}

ui_msg_empty_line()
{
  _show_text_on_recovery ' '
}

ui_msg()
{
  _show_text_on_recovery "${1:?}"
}

ui_msg_sameline_start()
{
  if test -e "${RECOVERY_PIPE}"; then
    printf 'ui_print %s' "${1:?}" >> "${RECOVERY_PIPE:?}"
  else
    printf 'ui_print %s' "${1:?}" 1>&"${OUTFD:?}"
  fi
  if test "${DEBUG_LOG}" -ne 0; then printf '%s\n' "${1:?}"; fi
}

ui_msg_sameline_end()
{
  if test -e "${RECOVERY_PIPE}"; then
    printf '%s\nui_print\n' "${1:?}" >> "${RECOVERY_PIPE:?}"
  else
    printf '%s\nui_print\n' "${1:?}" 1>&"${OUTFD:?}"
  fi
  if test "${DEBUG_LOG}" -ne 0; then printf '%s\n' "${1:?}"; fi
}

ui_debug()
{
  printf '%s\n' "${1?}"
}


# @section Error checking functions

validate_return_code()
{
  if test "${1}" -ne 0; then ui_error "${2}"; fi
}

validate_return_code_warning()
{
  if test "${1}" -ne 0; then ui_warning "${2}"; fi
}


# @section Mounting related functions

mount_partition()
{
  local partition
  partition="$(readlink -f "${1:?}")" || { partition="${1:?}"; ui_warning "Failed to canonicalize '${1}'"; }

  mount "${partition:?}" || ui_warning "Failed to mount '${partition}'"
  return 0  # Never fail
}

mount_partition_silent()
{
  local partition
  partition="$(readlink -f "${1:?}")" || { partition="${1:?}"; }

  mount "${partition:?}" 2>/dev/null || true
  return 0  # Never fail
}

unmount()
{
  local partition
  partition="$(readlink -f "${1:?}")" || { partition="${1:?}"; ui_warning "Failed to canonicalize '${1}'"; }

  umount "${partition:?}" || ui_warning "Failed to unmount '${partition}'"
  return 0  # Never fail
}

is_mounted()
{
  local _partition _mount_result _silent
  _silent="${2:-false}"
  _partition="$(readlink -f "${1:?}")" || { _partition="${1:?}"; if test "${_silent:?}" = false; then ui_warning "Failed to canonicalize '${1}'"; fi; }

  { test "${TEST_INSTALL:-false}" = 'false' && test -e '/proc/mounts' && _mount_result="$(cat /proc/mounts)"; } || _mount_result="$(mount 2>/dev/null)" || { test -n "${DEVICE_MOUNT:-}" && _mount_result="$("${DEVICE_MOUNT:?}")"; } || ui_error 'is_mounted has failed'

  case "${_mount_result:?}" in
    *[[:blank:]]"${_partition:?}"[[:blank:]]*) return 0;;  # Mounted
    *)                                                     # NOT mounted
  esac
  return 1  # NOT mounted
}

_mount_if_needed_silent()
{
  if is_mounted "${1:?}" true; then return 1; fi

  mount_partition_silent "${1:?}"
  is_mounted "${1:?}" true
  return "${?}"
}

UNMOUNT_SYS_EXT=0
UNMOUNT_PRODUCT=0
UNMOUNT_VENDOR=0
mount_extra_partitions_silent()
{
  ! _mount_if_needed_silent '/system_ext'
  UNMOUNT_SYS_EXT="${?}"
  ! _mount_if_needed_silent '/product'
  UNMOUNT_PRODUCT="${?}"
  ! _mount_if_needed_silent '/vendor'
  UNMOUNT_VENDOR="${?}"

  return 0  # Never fail
}

unmount_extra_partitions()
{
  if test "${UNMOUNT_SYS_EXT:?}" = '1'; then
    unmount '/system_ext'
  fi
  if test "${UNMOUNT_PRODUCT:?}" = '1'; then
    unmount '/product'
  fi
  if test "${UNMOUNT_VENDOR:?}" = '1'; then
    unmount '/vendor'
  fi

  return 0  # Never fail
}

ensure_system_is_mounted()
{
  if ! is_mounted '/system'; then
    mount '/system'
    if ! is_mounted '/system'; then ui_error '/system cannot be mounted'; fi
  fi
  return 0;  # OK
}

is_mounted_read_write()
{
  mount | grep " $1 " | head -n1 | grep -qi -e "[(\s,]rw[\s,)]"
}

get_mount_status()
{
  local mount_line
  mount_line="$(mount | grep " $1 " | head -n1)"
  if test -z "${mount_line}"; then return 1; fi  # NOT mounted
  if echo "${mount_line}" | grep -qi -e "[(\s,]rw[\s,)]"; then return 0; fi  # Mounted read-write (RW)
  return 2  # Mounted read-only (RO)
}

remount_read_write()
{
  mount -o remount,rw "$1" "$1"
}

remount_read_only()
{
  mount -o remount,ro "$1" "$1"
}


# @section Getprop related functions

getprop()
{
  (test -e '/sbin/getprop' && /sbin/getprop "ro.$1") || (grep "^ro\.$1=" '/default.prop' | head -n1 | cut -d '=' -f 2)
}

build_getprop()
{
  grep "^ro\.$1=" "${TMP_PATH}/build.prop" | head -n1 | cut -d '=' -f 2
}

simple_get_prop()
{
  grep -F "${1}=" "${2}" | head -n1 | cut -d '=' -f 2
}


# @section String related functions

is_substring()
{
  case "$2" in
    *"$1"*) return 0;;  # Found
    *)                  # NOT found
  esac
  return 1  # NOT found
}

replace_string()
{
  # shellcheck disable=SC3060
  echo "${1//$2/$3}"
}

replace_slash_with_at()
{
  local result
  result="$(echo "$@" | sed -e 's/\//@/g')"
  echo "${result}"
}

replace_line_in_file()  # $1 => File to process  $2 => Line to replace  $3 => Replacement text
{
  rm -f -- "${TMP_PATH:?}/func-tmp/replacement-string.dat"
  echo "${3:?}" > "${TMP_PATH:?}/func-tmp/replacement-string.dat" || ui_error "Failed to replace (1) a line in the file => '${1}'" 92
  sed -i -e "/${2:?}/r ${TMP_PATH:?}/func-tmp/replacement-string.dat" -- "${1:?}" || ui_error "Failed to replace (2) a line in the file => '${1}'" 92
  sed -i -e "/${2:?}/d" -- "${1:?}" || ui_error "Failed to replace (3) a line in the file => '${1}'" 92
  rm -f -- "${TMP_PATH:?}/func-tmp/replacement-string.dat"
}

replace_line_in_file_with_file()  # $1 => File to process  $2 => Line to replace  $3 => File to read for replacement text
{
  sed -i -e "/${2:?}/r ${3:?}" -- "${1:?}" || ui_error "Failed to replace (1) a line in the file => '$1'" 92
  sed -i -e "/${2:?}/d" -- "${1:?}" || ui_error "Failed to replace (2) a line in the file => '$1'" 92
}

search_string_in_file()
{
  grep -qF "$1" "$2" && return 0  # Found
  return 1  # NOT found
}

search_ascii_string_in_file()
{
  LC_ALL=C grep -qF "$1" "$2" && return 0  # Found
  return 1  # NOT found
}

search_ascii_string_as_utf16_in_file()
{
  local SEARCH_STRING
  SEARCH_STRING="$(printf '%s' "${1}" | od -A n -t x1 | LC_ALL=C tr -d '\n' | LC_ALL=C sed -e 's/^ //g;s/ /00/g')"
  od -A n -t x1 "$2" | LC_ALL=C tr -d ' \n' | LC_ALL=C grep -qF "${SEARCH_STRING}" && return 0  # Found
  return 1  # NOT found
}


# @section Permission related functions

set_perm()
{
  local uid="$1"; local gid="$2"; local mod="$3"
  shift 3
  # Quote: Previous versions of the chown utility used the dot (.) character to distinguish the group name; this has been changed to be a colon (:) character, so that user and group names may contain the dot character
  chown "${uid}:${gid}" "$@" || chown "${uid}.${gid}" "$@" || ui_error "chown failed on: $*" 81
  chmod "${mod}" "$@" || ui_error "chmod failed on: $*" 81
}

set_std_perm_recursive()  # Use it only if you know your version of 'find' handle spaces correctly
{
  find "$1" -type d -exec chmod 0755 '{}' + -o -type f -exec chmod 0644 '{}' +
  validate_return_code "$?" 'Failed to set permissions recursively'
}


# @section Extraction related functions

package_extract_file()
{
  local dir
  dir="$(dirname "${2:?}")"
  mkdir -p "${dir:?}" || ui_error "Failed to create the dir '${dir}' for extraction" 94
  set_perm 0 0 0755 "${dir:?}"
  unzip -opq "${ZIPFILE:?}" "${1:?}" 1> "${2:?}" || ui_error "Failed to extract the file '${1}' from this archive" 94
}

custom_package_extract_dir()
{
  mkdir -p "${2:?}" || ui_error "Failed to create the dir '${2}' for extraction" 95
  set_perm 0 0 0755 "${2:?}"
  unzip -oq "${ZIPFILE:?}" "${1:?}/*" -d "${2:?}" || ui_error "Failed to extract the dir '${1}' from this archive" 95
}

zip_extract_file()
{
  mkdir -p "$3" || ui_error "Failed to create the dir '$3' for extraction" 96
  set_perm 0 0 0755 "$3"
  unzip -oq "$1" "$2" -d "$3" || ui_error "Failed to extract the file '$2' from the archive '$1'" 96
}

zip_extract_dir()
{
  mkdir -p "$3" || ui_error "Failed to create the dir '$3' for extraction" 96
  set_perm 0 0 0755 "$3"
  unzip -oq "$1" "$2/*" -d "$3" || ui_error "Failed to extract the dir '$2' from the archive '$1'" 96
}


# @section Data reset functions

reset_gms_data_of_all_apps()
{
  if test -e '/data/data/'; then
    ui_debug 'Resetting GMS data of all apps...'
    find /data/data/*/shared_prefs -name 'com.google.android.gms.*.xml' -delete
    validate_return_code_warning "$?" 'Failed to reset GMS data of all apps'
  fi
}


# @section Hash related functions

verify_sha1()
{
  if ! test -e "$1"; then ui_debug "The file to verify is missing => '$1'"; return 1; fi  # Failed
  ui_debug "$1"

  local file_name="$1"
  local hash="$2"
  local file_hash

  file_hash="$(sha1sum "${file_name}" | cut -d ' ' -f 1)"
  if test -z "${file_hash}" || test "${hash}" != "${file_hash}"; then return 1; fi  # Failed
  return 0  # Success
}


# @section File / folder related functions

create_dir() # Ensure dir exists
{
  test -d "$1" && return
  mkdir -p "$1" || ui_error "Failed to create the dir '$1'" 97
  set_perm 0 0 0755 "$1"
}

copy_dir_content()
{
  create_dir "$2"
  cp -rpf "$1"/* "$2"/ || ui_error "Failed to copy dir content from '$1' to '$2'" 98
}

copy_file()
{
  cp -pf "$1" "$2"/ || ui_error "Failed to copy the file '$1' to '$2'" 99
}

move_file()
{
  mv -f "$1" "$2"/ || ui_error "Failed to move the file '$1' to '$2'" 100
}

move_rename_file()
{
  mv -f "$1" "$2" || ui_error "Failed to move/rename the file from '$1' to '$2'" 101
}

move_rename_dir()
{
  mv -f "$1"/ "$2" || ui_error "Failed to move/rename the folder from '$1' to '$2'" 101
}

move_dir_content()
{
  test -d "$1" || ui_error "You can only move the content of a folder" 102
  create_dir "$2"
  mv -f "$1"/* "$2"/ || ui_error "Failed to move dir content from '$1' to '$2'" 102
}

delete()
{
  ui_debug "Deleting '$*'..."
  rm -f -- "$@" || ui_error "Failed to delete files" 103
}

delete_recursive()
{
  if test -e "$1"; then
    ui_debug "Deleting '$1'..."
    rm -rf -- "$1" || ui_error "Failed to delete files/folders" 104
  fi
}

delete_recursive_wildcard()
{
  for filename in "$@"; do
    if test -e "${filename}"; then
      ui_debug "Deleting '${filename}'...."
      rm -rf -- "${filename:?}" || ui_error "Failed to delete files/folders" 105
    fi
  done
}

delete_dir_if_empty()
{
  if test -d "$1"; then
    ui_debug "Deleting '$1' folder (if empty)..."
    rmdir --ignore-fail-on-non-empty -- "$1" || ui_error "Failed to delete the '$1' folder" 103
  fi
}

file_get_first_line_that_start_with()
{
  grep -m 1 -e "^${1:?}" -- "${2:?}" || return "${?}"
}

string_split()
{
  printf '%s' "${1:?}" | cut -d '|' -sf "${2:?}" || return "${?}"
}

# @description Setup an app for later installation.
# (it automatically installs it depending on the SDK)
#
# @arg $1 boolean Default installation setting
# @arg $2 string Name of the app
# @arg $3 string Filename of the app
# @arg $4 string Folder of the app
#
# @exitcode 0 If successful.
setup_app()  # $1 => Default setting  $2 => Name  $3 => Filename  $4 => Folder
{
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
