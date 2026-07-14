#!/usr/bin/env zsh
#
# youtube-ai-analyzer.sh
# Phase 16：main-guard 重構 —— 讓 script 可以被 source，只載入
# function 定義而不觸發整個分析流程，方便單獨測試個別 function。

set -euo pipefail

# ---- Constants ----
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/../logs/archive.txt"
readonly YTDLP_BASE_OPTS=(--no-playlist)

readonly ILLEGAL_CHARS_SRC='/\:*?"<>|'
readonly ILLEGAL_CHARS_DST='---------'
readonly FULLWIDTH_CHARS_TO_SANITIZE=("：")

readonly BASE_DOWNLOAD_DIR="${HOME}/Documents/YoutubeAnalysis"
readonly PREFERRED_SUBTITLE_LANGS=("en" "zh-Hant" "zh-Hans" "ja")

readonly CHATGPT_URL="https://chatgpt.com"

# ---- Functions ----

log() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] ${message}" | tee -a "$LOG_FILE"
}

escape_for_applescript() {
    local input="$1"
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    echo "$input"
}

send_notification() {
    local title="$1"
    local subtitle="$2"
    local message="$3"
    local safe_title safe_subtitle safe_message

    safe_title="$(escape_for_applescript "$title")"
    safe_subtitle="$(escape_for_applescript "$subtitle")"
    safe_message="$(escape_for_applescript "$message")"

    osascript -e "display notification \"${safe_message}\" with title \"${safe_title}\" subtitle \"${safe_subtitle}\"" || true
}

open_download_folder() {
    local dir="$1"

    if ! open "$dir" 2>/dev/null; then
        log "Warning: failed to open Finder for ${dir}"
    fi
}

open_chatgpt() {
    if ! open "$CHATGPT_URL" 2>/dev/null; then
        log "Warning: failed to open ${CHATGPT_URL}"
    fi
}

log_error() {
    local message="$1"
    log "[ERROR] ${message}"
    echo "Error: ${message}" >&2
    send_notification "YouTube AI Analyzer" "Failed" "$message"
    log_section_end "failure"
    exit 1
}

log_section_start() {
    local url="$1"
    local -r divider="========================================"
    log "$divider"
    log "Analysis started for: ${url}"
}

log_section_end() {
    local result="$1"
    log "Analysis finished. Result: ${result}"
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "required command '${cmd}' not found in PATH."
    fi
}

sanitize_for_filename() {
    local input="$1"
    local sanitized="$input"
    local ch

    sanitized="$(tr "$ILLEGAL_CHARS_SRC" "$ILLEGAL_CHARS_DST" <<< "$sanitized")"

    for ch in "${FULLWIDTH_CHARS_TO_SANITIZE[@]}"; do
        sanitized="$(sed "s/${ch}/-/g" <<< "$sanitized")"
    done

    sanitized="$(sed -E 's/ +/ /g; s/^ +//; s/ +$//' <<< "$sanitized")"

    echo "$sanitized"
}

ensure_download_dir() {
    local dir="$1"

    if [[ -d "$dir" ]]; then
        log "Directory already exists, reusing: ${dir}"
        return 0
    fi

    if ! mkdir -p "$dir"; then
        log_error "failed to create directory: ${dir}"
    fi

    log "Directory created: ${dir}"
}

find_available_lang() {
    local json_object="$1"
    local lang

    for lang in "${PREFERRED_SUBTITLE_LANGS[@]}"; do
        if jq -e --arg lang "$lang" 'has($lang)' <<< "$json_object" >/dev/null 2>&1; then
            echo "$lang"
            return 0
        fi
    done

    echo ""
    return 1
}

download_subtitle() {
    local source_mode="$1"
    local lang="$2"
    local sub_flag

    case "$source_mode" in
        manual) sub_flag="--write-sub" ;;
        auto)   sub_flag="--write-auto-sub" ;;
        *)
            log_error "unknown subtitle source mode '${source_mode}'."
            ;;
    esac

    yt-dlp "${YTDLP_BASE_OPTS[@]}" \
        --skip-download \
        "$sub_flag" \
        --sub-langs "$lang" \
        --sub-format "srt/best" \
        --output "${DOWNLOAD_DIR}/subtitle.%(ext)s" \
        "$URL"
}

download_audio_fallback() {
    yt-dlp "${YTDLP_BASE_OPTS[@]}" \
        -x --audio-format mp3 \
        --output "${DOWNLOAD_DIR}/audio.%(ext)s" \
        "$URL"
}

download_thumbnail() {
    yt-dlp "${YTDLP_BASE_OPTS[@]}" \
        --skip-download \
        --write-thumbnail \
        --convert-thumbnails webp \
        --output "${DOWNLOAD_DIR}/thumbnail.%(ext)s" \
        "$URL"
}

save_info_json() {
    local info_path="${DOWNLOAD_DIR}/info.json"

    if ! jq '.' <<< "$METADATA_JSON" > "$info_path"; then
        log_error "failed to write info.json to ${info_path}"
    fi

    log "info.json saved to ${info_path}"
}

generate_readme() {
    local readme_path="${DOWNLOAD_DIR}/README.md"

    if ! cat > "$readme_path" << EOF
# ${TITLE}

- **URL**: ${URL}
- **Uploader**: ${UPLOADER}
- **Upload Date**: ${UPLOAD_DATE_FORMATTED}
- **Download Time**: ${ANALYSIS_TIMESTAMP}
- **Subtitle Language**: ${SUBTITLE_LANGUAGE_DISPLAY}
- **Folder Name**: ${FOLDER_NAME}
EOF
    then
        log_error "failed to write README.md to ${readme_path}"
    fi

    log "README.md saved to ${readme_path}"
}

validate_url_format() {
    local url="$1"

    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+ ]]; then
        log_error "input does not look like a valid URL: ${url}"
    fi
}

truncate_to_byte_limit() {
    local input="$1"
    local max_bytes="$2"

    python3 -c "
import sys
data = sys.argv[1].encode('utf-8')
max_bytes = int(sys.argv[2])
if len(data) <= max_bytes:
    print(sys.argv[1])
else:
    truncated = data[:max_bytes]
    while True:
        try:
            print(truncated.decode('utf-8'))
            break
        except UnicodeDecodeError:
            truncated = truncated[:-1]
" "$input" "$max_bytes"
}

# ---- Main ----
#
# main: 整個分析流程的主體。包成 function 而非直接寫在最外層，
# 是為了搭配下方的 main-guard —— 讓這支檔案被 source 時，只會
# 載入上面所有 function 的定義，不會自動觸發實際分析，方便
# 單獨測試個別 function（見本 Phase「驗證方式」的示範）。
main() {
    if [[ $# -eq 0 ]]; then
        echo "Error: No URL provided." >&2
        echo "Usage: $0 <youtube-url>" >&2
        exit 1
    fi

    readonly URL="$1"
    readonly ANALYSIS_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

    validate_url_format "$URL"

    log_section_start "$URL"

    require_command "yt-dlp"
    require_command "jq"
    require_command "ffmpeg"
    require_command "osascript"
    require_command "python3"

    log "Received input: ${URL}"

    log "Fetching metadata..."
    if ! METADATA_JSON="$(yt-dlp "${YTDLP_BASE_OPTS[@]}" --dump-json "${URL}")"; then
        log_error "yt-dlp failed to fetch metadata for URL: ${URL}"
    fi
    log "Metadata fetched (${#METADATA_JSON} bytes)"

    TITLE="$(jq -r '.title // "Untitled"' <<< "${METADATA_JSON}")"
    UPLOADER="$(jq -r '.uploader // "Unknown Uploader"' <<< "${METADATA_JSON}")"
    VIDEO_ID="$(jq -r '.id' <<< "${METADATA_JSON}")"

    UPLOAD_DATE_RAW="$(jq -r '.upload_date // ""' <<< "${METADATA_JSON}")"
    if [[ -n "$UPLOAD_DATE_RAW" ]]; then
        UPLOAD_DATE_FORMATTED="${UPLOAD_DATE_RAW:0:4}-${UPLOAD_DATE_RAW:4:2}-${UPLOAD_DATE_RAW:6:2}"
    else
        UPLOAD_DATE_FORMATTED="Unknown"
    fi

    readonly SAFE_TITLE="$(sanitize_for_filename "$TITLE")"
    readonly SAFE_UPLOADER="$(sanitize_for_filename "$UPLOADER")"

    # 這裡改用 local —— main() 有了真正的 function 作用域之後，
    # 這種只用一次的中繼值，終於可以正確地限定在區域範圍，不用
    # 再像 Phase 1~15 那樣，Main 直接寫在最外層、所有變數都只能
    # 是全域變數。這是 main-guard 重構額外帶來的好處，不只是
    # 為了讓 script 能被 source。
    local folder_name_raw="${SAFE_UPLOADER} - ${SAFE_TITLE} [${VIDEO_ID}]"
    readonly FOLDER_NAME="$(truncate_to_byte_limit "$folder_name_raw" 240)"
    readonly DOWNLOAD_DIR="${BASE_DOWNLOAD_DIR}/${FOLDER_NAME}"

    log "Target directory: ${DOWNLOAD_DIR}"
    ensure_download_dir "$DOWNLOAD_DIR"

    if ! download_thumbnail; then
        log_error "failed to download thumbnail."
    fi
    log "Thumbnail downloaded to ${DOWNLOAD_DIR}"

    save_info_json

    SUBTITLES_JSON="$(jq -c '.subtitles // {}' <<< "${METADATA_JSON}")"
    AUTO_CAPTIONS_JSON="$(jq -c '.automatic_captions // {}' <<< "${METADATA_JSON}")"

    SUBTITLE_LANG=""
    SUBTITLE_SOURCE=""

    if SUBTITLE_LANG="$(find_available_lang "$SUBTITLES_JSON")"; then
        SUBTITLE_SOURCE="manual"
    elif SUBTITLE_LANG="$(find_available_lang "$AUTO_CAPTIONS_JSON")"; then
        SUBTITLE_SOURCE="auto"
    fi

    if [[ -n "$SUBTITLE_LANG" ]]; then
        log "Subtitle found: language=${SUBTITLE_LANG}, source=${SUBTITLE_SOURCE}"
        if ! download_subtitle "$SUBTITLE_SOURCE" "$SUBTITLE_LANG"; then
            log_error "failed to download subtitle (lang=${SUBTITLE_LANG}, source=${SUBTITLE_SOURCE})."
        fi
        log "Subtitle downloaded to ${DOWNLOAD_DIR}"
        SUBTITLE_LANGUAGE_DISPLAY="${SUBTITLE_LANG} (${SUBTITLE_SOURCE})"
        NOTIFY_SUBTITLE_LINE="Subtitle Found"
    else
        log "No usable subtitle in preferred languages. Falling back to MP3."
        if ! download_audio_fallback; then
            log_error "failed to download audio fallback."
        fi
        log "Audio downloaded to ${DOWNLOAD_DIR}"
        SUBTITLE_LANGUAGE_DISPLAY="None (MP3 fallback used)"
        NOTIFY_SUBTITLE_LINE="No Subtitle, MP3 Downloaded"
    fi

    generate_readme

    open_download_folder "$DOWNLOAD_DIR"
    open_chatgpt

    send_notification "Download Complete" "$NOTIFY_SUBTITLE_LINE" "$TITLE"

    log_section_end "success"

    echo "Done. Check log at: ${LOG_FILE}"
}

# main-guard：只有在這支檔案「被直接執行」時才呼叫 main。
# $ZSH_EVAL_CONTEXT 是 zsh 記錄「目前執行環境堆疊」的特殊參數，
# 直接執行時它的值精確等於 "toplevel"；被 source 進另一個環境時，
# 會多一層變成 "toplevel:file"。這是 zsh 版的
# if __name__ == "__main__"（Python）。

echo "basename : $(basename -- $0)"
if [[ "$(basename -- "$0")" == "youtube-ai-analyzer.sh" ]]; then
    main "$@"
fi
