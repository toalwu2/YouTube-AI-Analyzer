# templates/

這個資料夾目前是空的，這是刻意的設計決定，不是遺漏。

`generate_readme()`（scripts/youtube-ai-analyzer.sh）目前用
Shell 的 Here-Document 直接產生 README.md，而不是讀取這個資料夾
裡的外部樣板檔案。原因：目前樣板只有一種、格式單純（沒有條件式
段落），外部樣板 + 佔位符取代的方案，會需要額外處理「怎麼讀取
外部檔案」「佔位符命名規則」「取代邏輯」這些機制，這些成本在
現況下大於它帶來的好處（YAGNI）。

**觸發條件**：如果未來對 README 格式的調整需求變得頻繁，或需要
支援多種樣板（例如 Phase 17 規劃的 AI Summary 需要不同排版），
屆時就是這個資料夾該正式啟用的時機——把樣板邏輯搬出 Shell
程式碼，改用讀取這裡的外部檔案。

詳見 docs/MentorHandbook.md 的 Phase 8。
