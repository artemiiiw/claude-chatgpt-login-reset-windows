#!/usr/bin/env bash
set -u

MODE="Safe"
PRODUCT="All"
LANG_UI="Auto"
CONFIRM_RESET=0
DRY_RUN=0
SKIP_KEYCHAIN=0
ENABLE_BASIC_NETWORK_RESET=0
NETWORK_RESET_ONLY=0
INTERACTIVE_MENU=1
LOG_PATH="${TMPDIR:-/tmp}/claude-chatgpt-reset-macos-$(date +%Y%m%d-%H%M%S).log"
SUPPORT_CONTACT="@telegrim"

DELETED=0
SKIPPED=0
ERRORS=0
STEP=0

color() {
  case "$1" in
    red) echo "\033[31m" ;;
    green) echo "\033[32m" ;;
    yellow) echo "\033[33m" ;;
    cyan) echo "\033[36m" ;;
    gray) echo "\033[90m" ;;
    reset) echo "\033[0m" ;;
    *) echo "" ;;
  esac
}

if [[ "$LANG_UI" == "Auto" ]]; then
  if [[ "${LANG:-}" == ru* ]]; then LANG_UI="ru"; else LANG_UI="en"; fi
fi

t() {
  local ru="$1"
  local en="$2"
  if [[ "$LANG_UI" == "ru" ]]; then echo "$ru"; else echo "$en"; fi
}

write_step() {
  STEP=$((STEP + 1))
  local txt="$1"
  echo
  printf "%s[%d] %s%s\n" "$(color cyan)" "$STEP" "$txt" "$(color reset)"
  echo "[$STEP] $txt" >> "$LOG_PATH"
}

write_explain() {
  local txt="$1"
  printf "    -> %s\n" "$txt"
  echo "    -> $txt" >> "$LOG_PATH"
}

write_item() {
  local status="$1"
  local msg="$2"
  local c="${3:-gray}"
  printf "  %s[%s]%s %s\n" "$(color "$c")" "$status" "$(color reset)" "$msg"
  echo "  [$status] $msg" >> "$LOG_PATH"
}

remove_path_safe() {
  local p="$1"
  if [[ ! -e "$p" ]]; then
    SKIPPED=$((SKIPPED + 1))
    write_item "NO CHANGES NEEDED" "$p" "gray"
    return
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    write_item "DRY RUN (WOULD REMOVE)" "$p" "yellow"
    return
  fi
  rm -rf "$p" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    DELETED=$((DELETED + 1))
    write_item "REMOVED" "$p" "green"
  else
    ERRORS=$((ERRORS + 1))
    write_item "ERROR" "$p" "red"
  fi
}

remove_matching_in_dir() {
  local base="$1"
  shift
  local patterns=("$@")
  if [[ ! -d "$base" ]]; then
    SKIPPED=$((SKIPPED + 1))
    write_item "NO CHANGES NEEDED" "$base" "gray"
    return
  fi
  local found=0
  for pat in "${patterns[@]}"; do
    while IFS= read -r -d '' f; do
      found=1
      remove_path_safe "$f"
    done < <(find "$base" -maxdepth 1 -iname "$pat" -print0 2>/dev/null)
  done
  if [[ "$found" -eq 0 ]]; then
    SKIPPED=$((SKIPPED + 1))
    write_item "NO CHANGES NEEDED" "$base (pattern not found)" "gray"
  fi
}

stop_processes() {
  local names=("$@")
  for n in "${names[@]}"; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
      write_item "DRY RUN (WOULD RUN)" "pkill -f $n" "yellow"
    else
      pkill -f "$n" >/dev/null 2>&1 || true
    fi
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --product) PRODUCT="$2"; shift 2 ;;
      --lang|--language) LANG_UI="$2"; shift 2 ;;
      --confirm) CONFIRM_RESET=1; INTERACTIVE_MENU=0; shift ;;
      --dry-run) DRY_RUN=1; INTERACTIVE_MENU=0; shift ;;
      --skip-keychain) SKIP_KEYCHAIN=1; shift ;;
      --network-reset) ENABLE_BASIC_NETWORK_RESET=1; shift ;;
      --network-reset-only) ENABLE_BASIC_NETWORK_RESET=1; NETWORK_RESET_ONLY=1; INTERACTIVE_MENU=0; shift ;;
      --help|-h)
        cat <<EOF
Usage:
  $0 [--mode Safe|Soft|Hard] [--product All|Claude|ChatGPT] [--lang Auto|ru|en] [--confirm|--dry-run]
EOF
        exit 0
        ;;
      *) echo "Unknown arg: $1"; exit 1 ;;
    esac
  done

  case "$MODE" in Safe|Soft|Hard) ;; *) echo "Invalid --mode"; exit 1;; esac
  case "$PRODUCT" in All|Claude|ChatGPT) ;; *) echo "Invalid --product"; exit 1;; esac
  case "$LANG_UI" in Auto|ru|en) ;; *) echo "Invalid --lang"; exit 1;; esac

  if [[ "$LANG_UI" == "Auto" ]]; then
    if [[ "${LANG:-}" == ru* ]]; then LANG_UI="ru"; else LANG_UI="en"; fi
  fi
}

interactive_menu() {
  echo
  echo "$(t 'Выберите режим запуска:' 'Choose run mode:')"
  printf "  %s1)%s SAFE dry-run\n" "$(color green)" "$(color reset)"
  printf "  %s2)%s SOFT dry-run\n" "$(color green)" "$(color reset)"
  printf "  %s3)%s HARD dry-run\n" "$(color green)" "$(color reset)"
  printf "  %s4)%s SAFE real run\n" "$(color green)" "$(color reset)"
  printf "  %s5)%s SOFT real run\n" "$(color yellow)" "$(color reset)"
  printf "  %s6)%s HARD real run\n" "$(color red)" "$(color reset)"
  printf "  %s7)%s Network reset dry-run\n" "$(color green)" "$(color reset)"
  printf "  %s8)%s Network reset real run\n" "$(color green)" "$(color reset)"
  echo "  9) $(t 'Выход' 'Exit')"
  read -r -p "$(t 'Введите 1-9: ' 'Enter 1-9: ')" choice
  case "$choice" in
    1) MODE="Safe"; DRY_RUN=1 ;;
    2) MODE="Soft"; DRY_RUN=1 ;;
    3) MODE="Hard"; DRY_RUN=1 ;;
    4) MODE="Safe"; CONFIRM_RESET=1 ;;
    5) MODE="Soft"; CONFIRM_RESET=1 ;;
    6) MODE="Hard"; CONFIRM_RESET=1 ;;
    7) MODE="Safe"; DRY_RUN=1; ENABLE_BASIC_NETWORK_RESET=1; NETWORK_RESET_ONLY=1; SKIP_KEYCHAIN=1 ;;
    8) MODE="Safe"; CONFIRM_RESET=1; ENABLE_BASIC_NETWORK_RESET=1; NETWORK_RESET_ONLY=1; SKIP_KEYCHAIN=1 ;;
    *) exit 0 ;;
  esac

  if [[ "$NETWORK_RESET_ONLY" -eq 0 ]]; then
    echo
    echo "$(t 'Выберите продукт для очистки:' 'Choose product scope:')"
    echo "  1) All (Claude + ChatGPT/OpenAI)"
    echo "  2) Claude"
    echo "  3) ChatGPT/OpenAI"
    read -r -p "$(t 'Введите 1-3: ' 'Enter 1-3: ')" scope
    case "$scope" in
      2) PRODUCT="Claude" ;;
      3) PRODUCT="ChatGPT" ;;
      *) PRODUCT="All" ;;
    esac
  fi
}

run_cleanup() {
  local home_dir="$HOME"
  local lib_dir="$HOME/Library"
  local app_support="$lib_dir/Application Support"

  if [[ "$NETWORK_RESET_ONLY" -eq 0 ]]; then
    write_step "$(t 'Остановка процессов Claude/браузеров' 'Stopping Claude/browser processes')"
    stop_processes "Claude" "Google Chrome" "Microsoft Edge" "Brave Browser" "Safari" "firefox"

    write_step "$(t 'Удаление локальных данных приложений' 'Removing local app state')"
    local targets=()
    if [[ "$PRODUCT" == "All" || "$PRODUCT" == "Claude" ]]; then
      targets+=("$home_dir/.claude" "$home_dir/.config/claude" "$home_dir/.cache/claude" "$app_support/Claude" "$app_support/Anthropic")
    fi
    if [[ "$PRODUCT" == "All" || "$PRODUCT" == "ChatGPT" ]]; then
      targets+=("$app_support/OpenAI" "$app_support/ChatGPT")
    fi
    for tpath in "${targets[@]}"; do remove_path_safe "$tpath"; done

    local domain_patterns=()
    [[ "$PRODUCT" == "All" || "$PRODUCT" == "Claude" ]] && domain_patterns+=("*claude*" "*anthropic*")
    [[ "$PRODUCT" == "All" || "$PRODUCT" == "ChatGPT" ]] && domain_patterns+=("*openai*" "*chatgpt*")

    if [[ "$MODE" == "Safe" || "$MODE" == "Soft" ]]; then
      write_step "$(t 'Точечная очистка веб-данных в профилях браузеров' 'Targeted web data cleanup in browser profiles')"
      local bases=(
        "$app_support/Google/Chrome"
        "$app_support/Microsoft Edge"
        "$app_support/BraveSoftware/Brave-Browser"
      )
      for base in "${bases[@]}"; do
        [[ -d "$base" ]] || { SKIPPED=$((SKIPPED + 1)); write_item "NO CHANGES NEEDED" "$base" "gray"; continue; }
        for profile in "$base"/Default "$base"/Profile*; do
          [[ -d "$profile" ]] || continue
          if [[ "$PRODUCT" == "All" ]]; then
            remove_path_safe "$profile/Cookies"
            remove_path_safe "$profile/Network/Cookies"
            remove_path_safe "$profile/Login Data"
          fi
          remove_matching_in_dir "$profile/Local Storage/leveldb" "${domain_patterns[@]}"
          remove_matching_in_dir "$profile/IndexedDB" "${domain_patterns[@]}"
          remove_matching_in_dir "$profile/Service Worker" "${domain_patterns[@]}"
        done
      done
      remove_matching_in_dir "$lib_dir/Safari/LocalStorage" "${domain_patterns[@]}"
      remove_matching_in_dir "$lib_dir/WebKit/WebsiteData" "${domain_patterns[@]}"
    else
      write_step "$(t 'HARD: удаление полных профилей браузеров' 'HARD: deleting full browser profiles')"
      local hard_targets=(
        "$app_support/Google/Chrome"
        "$app_support/Microsoft Edge"
        "$app_support/BraveSoftware/Brave-Browser"
        "$app_support/Firefox/Profiles"
        "$lib_dir/Safari"
        "$lib_dir/WebKit/Safari"
        "$lib_dir/Cookies"
      )
      for h in "${hard_targets[@]}"; do remove_path_safe "$h"; done
    fi

    if [[ "$MODE" != "Safe" && "$SKIP_KEYCHAIN" -eq 0 ]]; then
      write_step "$(t 'Очистка записей Keychain' 'Cleaning Keychain items')"
      local keys=()
      [[ "$PRODUCT" == "All" || "$PRODUCT" == "Claude" ]] && keys+=("claude" "anthropic")
      [[ "$PRODUCT" == "All" || "$PRODUCT" == "ChatGPT" ]] && keys+=("openai" "chatgpt")
      for k in "${keys[@]}"; do
        if [[ "$DRY_RUN" -eq 1 ]]; then
          write_item "DRY RUN (WOULD RUN)" "security delete-generic-password -s $k login.keychain-db" "yellow"
          write_item "DRY RUN (WOULD RUN)" "security delete-internet-password -s $k login.keychain-db" "yellow"
        else
          security delete-generic-password -s "$k" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true
          security delete-internet-password -s "$k" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true
          write_item "OK" "Keychain pattern cleanup attempted: $k" "green"
        fi
      done
    fi
  fi

  if [[ "$ENABLE_BASIC_NETWORK_RESET" -eq 1 ]]; then
    write_step "$(t 'Базовый сброс сети' 'Basic network reset')"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      write_item "DRY RUN (WOULD RUN)" "dscacheutil -flushcache" "yellow"
      write_item "DRY RUN (WOULD RUN)" "killall -HUP mDNSResponder" "yellow"
    else
      dscacheutil -flushcache >/dev/null 2>&1 || true
      killall -HUP mDNSResponder >/dev/null 2>&1 || true
      write_item "OK" "DNS cache flushed" "green"
    fi
  fi
}

main() {
  parse_args "$@"

  if [[ "$INTERACTIVE_MENU" -eq 1 && "$#" -eq 0 ]]; then
    interactive_menu
  fi

  if [[ "$CONFIRM_RESET" -ne 1 && "$DRY_RUN" -ne 1 ]]; then
    echo "$(t 'ОТКАЗ: используйте --confirm для реального запуска или --dry-run для предпросмотра.' 'REFUSED: use --confirm for real run or --dry-run for preview.')"
    exit 1
  fi

  {
    echo "Claude+ChatGPT Reset Script Log"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Mode: $MODE"
    echo "Product: $PRODUCT"
    echo "Lang: $LANG_UI"
    echo "DryRun: $DRY_RUN"
  } > "$LOG_PATH"

  echo "========================================"
  echo " Claude + ChatGPT Login Reset (macOS)  "
  echo "========================================"
  echo "Mode: $MODE"
  echo "Product: $PRODUCT"
  echo "Language: $LANG_UI"
  echo "DryRun: $([[ "$DRY_RUN" -eq 1 ]] && echo True || echo False)"
  echo "Log: $LOG_PATH"

  run_cleanup

  echo
  echo "============== SUMMARY =============="
  echo "Deleted: $DELETED"
  echo "No changes needed: $SKIPPED"
  echo "Errors: $ERRORS"
  echo "====================================="
  echo "Support (Telegram): $SUPPORT_CONTACT"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "$(t 'Dry-run завершен. Изменений не внесено.' 'Dry-run completed. No changes made.')"
  else
    echo "$(t 'Готово. Рекомендуется перезапуск macOS перед входом.' 'Done. Reboot macOS before login for best effect.')"
  fi
}

main "$@"
