# YouTube AI Analyzer

一支 macOS 自動化工具：從 Safari 分享，或複製網址後按下快捷鍵，
自動下載 YouTube 影片的字幕（或在無字幕時 fallback 成音檔）、
縮圖、metadata，並整理成方便 Obsidian 管理的資料夾結構，同時
自動開啟 Finder 與 ChatGPT，方便立即進行 AI 分析。

## 功能

- 支援兩種觸發方式：Safari 分享表單、剪貼簿 + 鍵盤快捷鍵
- 自動擷取 metadata（標題、上傳者、上傳日期、時長等）
- 字幕優先下載策略：人工字幕 > 自動字幕 > MP3 音檔 fallback
- 自動產生縮圖（統一轉換為 webp）、info.json、README.md
- macOS 原生通知、自動開啟 Finder 與 ChatGPT
- 完整的 log 紀錄系統，每次分析皆有起訖標記

## 架構

```
Safari 分享 / 剪貼簿 + 快捷鍵
        ↓
    捷徑（Shortcuts）— 僅負責觸發與取得輸入，無業務邏輯
        ↓
scripts/youtube-ai-analyzer.sh
        ↓
    yt-dlp（下載/metadata） → jq（JSON 解析）
        ↓
    osascript（Notification） / open（Finder、瀏覽器）
```

## 環境需求

- macOS
- [Homebrew](https://brew.sh)
- yt-dlp、jq、ffmpeg、python3（透過 Homebrew 安裝）

## 安裝

```bash
git clone https://github.com/toalwu2/YouTube-AI-Analyzer.git
cd YouTube-AI-Analyzer
brew install yt-dlp jq ffmpeg
chmod +x scripts/youtube-ai-analyzer.sh
./scripts/check-env.sh   # 確認所有依賴都已安裝
```

匯入 `shortcuts/` 資料夾內的 `.shortcut` 檔案到「捷徑」App，
依照 `docs/Shortcuts-Setup.md` 的說明，手動設定鍵盤快捷鍵與
分享表單開關（這些個人化設定不會隨匯出檔案完整保留）。

## 使用方式

- **分享**：在 Safari 開啟 YouTube 影片 → 分享 → YT Analyzer (Share)
- **剪貼簿**：複製 YouTube 網址 → 按下設定好的鍵盤快捷鍵

分析結果會存放在 `~/Documents/YoutubeAnalysis/` 底下，
以 `Uploader - Title [VideoID]` 命名。

## Known Limitations

若某支影片曾用其中一種觸發方式（Share 或 Clipboard）分析過，
之後改用另一種方式對同一支影片重新分析，可能遇到 macOS 層級
的 `Operation not permitted` 錯誤（原因是 macOS 的檔案級存取
權限機制 `com.apple.macl`，非本專案程式邏輯問題，詳見
`docs/MentorHandbook.md`）。解法：手動刪除該影片的舊資料夾
後再重新分析。

## 專案文件

這份專案不只是一套工具，更完整記錄了每一個設計決策背後的
「為什麼」，包含底層原理、方案比較、以及開發過程中真實踩過
的每一個 bug（macOS 剪貼簿型別轉換、Shell `set -e` 例外規則、
TCC 權限機制、UTF-8 位元組邊界處理等）——詳見
[`docs/MentorHandbook.md`](docs/MentorHandbook.md)。

## License

MIT License，詳見 [`LICENSE`](LICENSE)。
