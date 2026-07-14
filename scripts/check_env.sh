#!/usr/bin/env zsh
#
# check-env.sh
# 用途：檢查 YouTube AI Analyzer 所需的外部工具是否已安裝於本機
# 用法：./check-env.sh

# 集中管理需要的工具清單。
# 之後若新增依賴（例如 whisper），只需要改這一行，
# 不用在程式裡到處新增判斷式 —— 這是在實踐 DRY。
readonly REQUIRED_TOOLS=("yt-dlp" "jq" "ffmpeg" "osascript")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "[OK]      $tool -> $(command -v "$tool")"
    else
        echo "[MISSING] $tool"
    fi
done
