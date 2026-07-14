# Shortcuts 設定說明

本專案透過 macOS「捷徑」App 建立兩個觸發入口，皆呼叫同一支
`scripts/youtube-ai-analyzer.sh`，不包含任何業務邏輯。

## YT Analyzer (Clipboard)
觸發方式：鍵盤快捷鍵（自訂，例如 ⌃⌥⌘Y）

流程：
1. 取得剪貼簿內容
2. 取得輸入的文字（強制轉換成純文字，避免 Rich Text/HTML
   型別導致的內容異常，詳見 docs/MentorHandbook.md Phase 2 附錄）
3. 執行 Shell 腳本：
   - Shell: /bin/zsh
   - Pass Input: as arguments
   - 內容: `~/Projects/YouTube-AI-Analyzer/scripts/youtube-ai-analyzer.sh "$1"`

## YT Analyzer (Share)
觸發方式：Safari「分享」選單

流程：
1. 取得輸入的網址（Get URLs from Input）
2. 執行 Shell 腳本（設定與上方完全相同）

## 匯入方式
若要在別台 Mac 上重建，直接雙擊 shortcuts/ 資料夾內對應的
.shortcut 檔案即可匯入「捷徑」App，匯入後仍需依上方流程手動
確認鍵盤快捷鍵綁定、分享表單開關等個人化設定（這些設定不一定
會隨匯出檔案完整保留）。
