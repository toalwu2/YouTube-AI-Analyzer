# YouTube AI Analyzer — Mentor Handbook

這份文件記錄了 YouTube AI Analyzer 這個專案，從零開始建置的完整
過程：每一個設計決策背後的「為什麼」、底層原理、方案比較，以及
開發過程中真實踩過的每一個 bug（不是事後編出來的教材，是實際
發生、實際除錯過的紀錄）。

如果你是想理解這支工具怎麼運作的人，建議照順序讀下去；如果你
只是想找某個特定問題的答案（例如「為什麼 tr 處理中文字會出錯」），
可以直接用下面的目錄跳過去。

## 目錄

- [Phase 0 — 環境準備 + 專案骨架](#phase-0)
- [Phase 1 — 第一支最小 Script：打通管線](#phase-1)
- [Phase 2 — 把 Script 接進 Shortcut（Clipboard 觸發）](#phase-2)
  - [附錄：Clipboard 型別轉換陷阱](#phase-2-addendum)
- [Phase 3 — yt-dlp 基礎：--dump-json 抓 Metadata，用 jq 解析](#phase-3)
- [Phase 4 — 檔名 Sanitize + 資料夾命名規則](#phase-4)
  - [附錄：tr 的多位元組陷阱](#phase-4-addendum)
- [Phase 5 — 建立資料夾結構](#phase-5)
- [Phase 6 — 下載邏輯：字幕優先，無字幕 Fallback 到 MP3](#phase-6)
  - [附錄：燒錄字幕 vs 系統字幕軌](#phase-6-addendum)
- [Phase 7 — 下載 Thumbnail 與 info.json](#phase-7)
- [Phase 8 — README.md 樣板產生](#phase-8)
- [Phase 9 — Logging 系統收斂](#phase-9)
  - [附錄：yt-dlp 裸呼叫繞過 log_error](#phase-9-addendum)
- [Phase 10 — macOS Notification](#phase-10)
  - [附錄一：TCC 授權依觸發當下最上層 App 而不同](#phase-10-addendum-1)
  - [附錄二：com.apple.macl 檔案級存取控制](#phase-10-addendum-2)
- [Phase 11 — 自動打開 Finder](#phase-11)
- [Phase 12 — 自動開啟 ChatGPT](#phase-12)
- [Phase 13 — Safari Share Sheet 整合](#phase-13)
- [Phase 14 — Clipboard + 快捷鍵版整合收斂](#phase-14)
- [Phase 15 — Defensive Programming 總複查](#phase-15)
- [Phase 16 — Refactor](#phase-16)
  - [附錄：main-guard 修正紀錄](#phase-16-addendum)
- [Phase 17 — 未來擴充預留點](#phase-17)
- [Phase 18 — GitHub 上架](#phase-18)
- [已知限制總覽](#known-limitations)

---

<a id="phase-0"></a>
## Phase 0 — 環境準備 + 專案骨架

### Summary
建立 ~/Projects/YouTube-AI-Analyzer 骨架（scripts/docs/templates/logs），
git init，並寫出第一支 script check-env.sh 檢查 yt-dlp / jq / ffmpeg / osascript 是否安裝。

### Code
`scripts/check-env.sh`：用 readonly 陣列集中管理依賴清單，
用 command -v 搭配 exit code 判斷工具是否存在。

### Concept
- Shebang (`#!/usr/bin/env zsh`)：告訴系統用哪個直譯器執行
- PATH：系統尋找可執行檔的路徑清單
- command -v vs which：script 裡用 command -v，更可移植、行為明確
- exit code：Shell 判斷「成功/失敗」的依據，而非文字內容
- chmod +x：Unix 執行權限位元
- Homebrew 是 macOS 的套件管理器，管的是「這台機器的命令列工具」，
  跟 NuGet 管「專案相依套件」的層級不同
- Shell 的 hash table（指令快取表）：互動式 Shell 會快取指令路徑，
  可能與現況脫節（`hash -r` / `rehash` 清空快取）；但獨立執行的
  script（透過 Shebang 啟動全新 process）天生不受快取影響

### Best Practice
- 用陣列集中管理依賴清單（DRY）
- 資料夾依「職責」而非「技術/格式」分類（SRP 套用在檔案系統）
- 先建立可重複執行的骨架指令（mkdir -p 具備冪等性）

---

<a id="phase-1"></a>
## Phase 1 — 第一支最小 Script：打通管線

### Summary
建立 scripts/youtube-ai-analyzer.sh，用 $1 接收字串，驗證參數數量，
用 log() function 寫入 logs/archive.txt，建立 set -euo pipefail 的
防禦性骨架，之後所有 Phase 都延用這個地基。

### Code
核心結構：set -euo pipefail 開頭 → `$(cd "$(dirname "$0")" && pwd)`
動態解析自身所在絕對路徑 → log() function 統一輸出 → 參數驗證
（$# -eq 0 則 exit 1）→ 正常路徑 exit 0。

### Concept
- Positional parameters: $0 $1 $# $@ $*，"$@" vs "$*" 的引號差異
- set -e / -u / -o pipefail 三者分別的作用，對應「fail fast」
  - set -e：任何指令失敗，立即中止 script
  - set -u：引用未定義變數視為錯誤
  - set -o pipefail：管線中任何一段失敗，整條管線視為失敗
  - 例外規則：if/while 條件式、! 取反、&&/|| 非最後一個，都不
    觸發 set -e；但「單獨一行、沒有搭配這些結構的裸敘述」會觸發
- `$(cd "$(dirname "$0")" && pwd)`：自身路徑解析的標準 idiom，
  無論從哪個目錄、用相對或絕對路徑呼叫，都能解析出唯一絕對路徑
- function 與 local：Shell 的作用域規則，變數預設是全域的，
  需要明確用 local 限定在函式內部
- stderr（>&2）與 stdout 的分流
- `${#}` 是特殊參數 `#` 的展開，等同 `$#`；`${#VAR}` 是變數長度
  運算子——同一個符號 `#` 依位置不同扮演不同角色

### Best Practice
- 路徑解析方案比較：方案 A（寫死絕對路徑，Hard Code）
  vs 方案 B（裸 dirname "$0"，相對路徑不可靠）
  vs 方案 C（cd+pwd，採用）→ 因為已知未來會被 Shortcut（非終端機
  環境）呼叫
- log() 提前抽成 function：因為重複呼叫是「確定會發生」而非
  「猜測」，符合 Rule of Three 的例外情境；但介面保持極簡，
  避免過度設計
- exit code 明確區分（0 成功 / 1 參數錯誤），為未來呼叫端判斷做準備

---

<a id="phase-2"></a>
## Phase 2 — 把 Script 接進 Shortcut（Clipboard 觸發）

### Summary
建立 macOS Shortcut「YT Analyzer (Clipboard)」，用「取得剪貼簿」+
「執行 Shell 腳本」(zsh, Pass Input: as arguments) 呼叫
youtube-ai-analyzer.sh "$1"，並綁定鍵盤快捷鍵觸發。驗證 log 格式
跟 Terminal 手動執行完全一致，證明 script 對呼叫端保持無知
（caller-agnostic）。

### Code
本階段無新程式碼，是 Shortcuts App 的 GUI 設定：
Get Clipboard → Run Shell Script (/bin/zsh, as arguments) →
呼叫 `~/Projects/YouTube-AI-Analyzer/scripts/youtube-ai-analyzer.sh "$1"`
→ Show Result（除錯用，Phase 10 會被 Notification 取代）。

### Concept
- Run Shell Script 的 Pass Input：as arguments（→ $1）vs as stdin
  （→ 需用 read/cat 接），本專案選 as arguments
- Login shell / Interactive shell / Non-interactive shell 的差異：
  Shortcuts 啟動的是 non-login non-interactive shell，不會讀
  ~/.zprofile，PATH 可能比 Terminal 精簡
- 鍵盤快捷鍵是系統層級的全域事件監聽（global hotkey）

### Best Practice
- Thin Orchestration Layer, Thick Logic Layer：Shortcut 只負責
  「觸發方式 + 取得輸入 + 呼叫 script」，所有邏輯留在 shell script，
  可版本控制、可在 Terminal 獨立測試、可用 set -x/echo $? 除錯
- SRP 套用在系統邊界層級：「觸發媒介」跟「業務邏輯」是兩個不同的
  改變理由，理應分層 —— 檢驗標準：「A 需求改變，需不需要動到 B？」

<a id="phase-2-addendum"></a>
### 附錄 — Clipboard 型別轉換陷阱（真實踩坑紀錄）

**現象**：從網址列複製 YouTube 網址時，Shortcut 運作正常；但從
某個 HTML 渲染的網頁（例如聊天介面）選字複製時，Shortcut 傳進
script 的 $1 變成一串暫存檔路徑，例如
`/Users/xxx/Library/Group Containers/.../Clipboard ....html`，
而不是預期的純文字內容。

**Root Cause**：macOS Pasteboard 可以同時存放同一份內容的多種
表示法（public.utf8-plain-text / public.html / public.rtf...）。
「取得剪貼簿」動作在偵測到 HTML 表示法時，會優先當作 Rich Text
處理；當這個 Rich Text 被強制轉換成 Shell 腳本需要的純文字字串
時（as arguments），Shortcuts 底層引擎 WorkflowKit 對於複雜的
HTML 內容，會 fallback 成「把內容寫成暫存 HTML 檔案，回傳檔案
路徑」，而不是純文字。

**Fix**：在「取得剪貼簿」與「執行 Shell 腳本」之間，插入「取得
輸入的文字」(Get Text from Input) 動作，強制把任何型別的輸入
攤平成純文字，再送進 Run Shell Script。

**Concept 對應**：
- macOS Pasteboard 是多重表示法（multi-representation）設計，
  類似 Windows IDataObject 或 HTTP Content Negotiation
- Shortcuts 變數型別是動態、隱含自動轉換（coercion），類似
  duck typing，跟 C# 的強型別、顯式轉型思維不同
- 加一個明確的型別轉換步驟，等同 C# 裡寫 .ToString() 或顯式轉型：
  把「隱含行為」變成「管線裡看得見、可控的步驟」

**Best Practice**：不要相信輸入來源永遠乾淨。管線裡任何「型別
不確定」的節點，都該有一道明確的正規化（normalize）關卡，而不
是依賴巧合。


---

<a id="phase-3"></a>
## Phase 3 — yt-dlp 基礎：--dump-json 抓 Metadata，用 jq 解析

### Summary
新增 require_command() 做外部依賴的 fail-fast 檢查；用
yt-dlp --no-playlist --dump-json 一次性抓回完整 metadata JSON，
存進變數重複利用；用 jq -r 解析出 title / uploader / id 三個欄位。

### Code
require_command()：command -v 判斷 + exit 1，跟 check-env.sh 邏輯
相同但用途不同（fail-fast vs 診斷報告）。
YTDLP_BASE_OPTS=(--no-playlist)：陣列集中管理未來會重複用到的旗標。
METADATA_JSON="$(yt-dlp "${YTDLP_BASE_OPTS[@]}" --dump-json "$URL")"：
單次網路請求，之後所有欄位解析都是本地端操作。
jq -r '.field' <<< "$METADATA_JSON"：here-string 餵資料，-r 去除
JSON 字串的雙引號。

### Concept
- yt-dlp --dump-json：只解析不下載，回傳完整 JSON
- JSON 基本結構對照 C#：{} 物件、[] 陣列、null
- jq 是「JSON 版的 grep」，.field 語法取值，-r 拿掉雙引號
- 餵資料進指令的四種方式比較：< 檔案重導、| 管線、<<< here-string、
  <<EOF here-document，各自適合的情境
- ${#VAR}：字串長度（跟 Phase 1 的 $# 位置參數個數是不同語法）
- yt-dlp 對「網址帶 list= 參數」的預設行為：優先當作整個播放清單
  處理，需明確加 --no-playlist 才會只處理 v= 指定的單一影片；
  Video ID（v=）、Playlist ID（list=）、Index（index=）是三個
  獨立概念，各自代表不同層級的識別

### Best Practice
- 方案比較：A（每欄位各自呼叫 yt-dlp，多次網路請求）
  vs B（dump-json 一次 + jq 解析多次，採用）
  vs C（jq 一次抽多欄位用 @tsv，效能更好但可讀性犧牲，暫不採用）
  → 優先可讀性、教學循序漸進，效能差異在此規模下可忽略
- False DRY 的具體案例：require_command() 跟 check-env.sh 用同樣的
  command -v 技巧，但服務不同的失敗處理策略（fail-fast vs
  收集完整報告），不應該被迫合併成同一支程式碼
- --no-playlist 屬於「確定會重複用到」的已知情境，提前用陣列常數
  集中管理（跟 log() function 提前抽出是同一種判斷）
- 責任歸屬：把「不要下載整個播放清單」這個保證放進 script，而非
  依賴使用者複製網址前自己處理——自動化的意義就是把容易被忽略的
  步驟變成系統自動保證的行為

---

<a id="phase-4"></a>
## Phase 4 — 檔名 Sanitize + 資料夾命名規則

### Summary
新增 sanitize_for_filename()，用 tr 取代危險字元、sed 收斂空白，
把 TITLE/UPLOADER 轉成安全字串；用 jq 的 // 運算子攔截 JSON null，
組出 FOLDER_NAME = "Uploader - Title [VideoID]"。

### Code
sanitize_for_filename()：
  Step 1: tr "$SRC" "$DST" <<< "$input"  → 危險字元換成 '-'
  Step 2: sed -E 's/ +/ /g; s/^ +//; s/ +$//'  → 收斂/去除空白
jq -r '.title // "Untitled"'：JSON null fallback

### Concept
- macOS 禁止 ':' '/' 的歷史原因：HFS 舊系統用 ':' 當路徑分隔符，
  Finder 至今仍相容轉換這個規則
- tr：逐字元一對一映射替換，不理解正規表示式，速度快但功能陽春
- sed -E：Extended Regex，s/pattern/replacement/flags，
  分號可串接多條規則依序執行
- jq 的 // (alternative operator)：左邊是 null/false 時取右邊預設值
- jq -r 對 null 的行為：印出字面 "null" 四個字，不是空字串

### Best Practice
- Sanitize 策略方案比較：
  A（只擋 macOS 要求的字元）→ 資料若被同步到其他系統會延遲爆炸
  B（擋跨平台常見黑名單字元，採用）→ 低成本換取長期穩定
  C（白名單只留英數字）→ 會摧毀中日韓文/emoji 標題的語意，拒絕採用
  → 教訓：更嚴格不等於更好，要衡量「防禦收穫」vs「對核心需求的傷害」
- Trust Boundary：VIDEO_ID（平台格式受限）不需要 sanitize，
  TITLE/UPLOADER（自由格式使用者輸入）需要 —— 不是所有外部
  資料風險程度都一樣
- Rule of Three 的典型應用：sanitize 邏輯從一開始就確定會被
  呼叫兩次，直接抽 function，沒有爭議

<a id="phase-4-addendum"></a>
### 附錄 — tr 的多位元組陷阱（真實踩坑紀錄）

**現象**：標題含全形冒號「：」的影片，sanitize 後冒號沒被替換掉；
原本想直接把「：」加進 tr 的 ILLEGAL_CHARS_SRC 解決。

**Root Cause（實測驗證）**：tr 是以「位元組」為單位建立轉換表，
不理解多位元組字元的邊界。全形冒號在 UTF-8 是 3 bytes（EF BC 9A）。
若塞進 tr 的 SRC，會被拆成 3 個獨立位元組各自替換，只要標題中
其他中文字的 UTF-8 編碼剛好共用其中任一個位元組值（實測：
「式」「碼」「演」都共用了 0xBC），就會被意外打斷，產生無法
解碼的損毀資料，且不會有任何錯誤訊息提示。

底層原因：UTF-8 設計保證 ASCII 位元組（0x00-0x7F）絕不會出現
在任何多位元組字元編碼裡，所以半形符號用 tr 天生安全；但全形
字元的位元組落在 ≥0x80，跟中文字的位元組範圍重疊，風險才浮現。

**Fix**：新增 FULLWIDTH_CHARS_TO_SANITIZE 陣列，用 sed 逐一字面
取代，不擴充 tr 的字元集。sed 的 pattern 比對是完整連續位元組
序列，不會有 tr 那種「拆成單一位元組建表」的問題。

**Concept 對應**：
- tr：位元組層級的一對一轉換表，只對 ASCII 安全
- sed：字面字串（連續位元組序列）比對，天生對多位元組字元安全
- UTF-8 設計原則：ASCII 位元組與多位元組延續位元組的範圍互斥，
  這是 tr 對 ASCII 安全、對非 ASCII 危險的根本原因

**Best Practice**：處理可能含多語言/多位元組內容的文字時，優先
用 sed 的字面比對而非 tr 的字元集展開；陣列集中管理「已知會
陸續補充」的清單（跟 Phase 0 的 REQUIRED_TOOLS 同一種模式）。


---

<a id="phase-5"></a>
## Phase 5 — 建立資料夾結構

### Summary
新增 BASE_DOWNLOAD_DIR (~/Documents/YoutubeAnalysis，用 $HOME
而非 ~ 定義) 與 ensure_download_dir() function：用 -d 明確檢查
資料夾是否已存在，區分「新建」vs「重用」並分別記錄 log，而不是
直接無腦呼叫 mkdir -p 蓋過去。

### Code
ensure_download_dir()：
  [[ -d "$dir" ]] → 已存在，log 後 return
  否則 mkdir -p "$dir"（用 if ! ... 包住，失敗時自訂清楚的錯誤
  訊息並 exit 1，而不是放給 set -e 用預設方式中止）

### Concept
- ~ 展開規則：只在「未加引號、位於字首」時展開；包進雙引號會
  被當字面字元 → 一律改用 $HOME，不受位置規則限制
- Shell 檔案測試運算子：-e(存在) / -d(是資料夾) / -f(是檔案)
  / -r -w -x(讀寫執行權限)，要問對問題才用對運算子
- mkdir -p 的兩個獨立功能：(1) 已存在不算錯誤 (2) 自動建立
  路徑上所有缺少的父層資料夾

### Best Practice
- 重複分析同一支影片的三種處理方案比較：
  A（無腦覆蓋）→ 資訊不透明，之後想做斷點續傳缺乏切入點
  B（偵測 + 記錄 + 放行，採用）→ 不阻擋合理的重複使用情境，
    同時保留可追溯的 log 軌跡
  C（偵測 + 拒絕）→ 適合高一致性要求系統(如交易紀錄)，
    對個人知識管理工具而言過度嚴格，傷害好用性
- 實際運用 Phase 1 學到的「if 條件式不觸發 set -e」規則，
  主動用這個特性取得對失敗處理的自訂控制權

已知但未處理的 edge case：macOS APFS 限制單一檔名 255 bytes
（不是 255 字元），中日文標題可能字數不多但 byte 數超標——
留到 Phase 15 處理安全截斷。

---

<a id="phase-6"></a>
## Phase 6 — 下載邏輯：字幕優先，無字幕 Fallback 到 MP3

### Summary
新增 PREFERRED_SUBTITLE_LANGS 語言優先清單、find_available_lang()
判斷邏輯（人工字幕優先於自動字幕）、download_subtitle() /
download_audio_fallback() 實際呼叫 yt-dlp 下載。決策依據來自
Phase 3 已抓的 METADATA_JSON，不需要額外的網路請求。

### Code
find_available_lang()：依序比對 PREFERRED_SUBTITLE_LANGS,用
jq -e --arg lang "$lang" 'has($lang)' 檢查是否存在
download_subtitle()：用 case/esac 依 source_mode 切換
--write-sub / --write-auto-sub，其餘參數完全共用
SUBTITLES_JSON="$(jq -c '.subtitles // {}' ...)"：防禦 null

### Concept
- YouTube automatic_captions 機制：先 ASR 出一份「原始語言」
  逐字稿（key 帶 -orig 尾綴），再機器翻譯成近150種語言全部塞入
  這個物件——所以「有 en 這個 key」不代表影片是英文原生內容
- jq -e：依「輸出是否為 truthy」決定 exit code，可直接接 if
- jq --arg：把 shell 變數當「資料」交給 jq，而非拼接進程式碼
  字串——概念對應 C#/SQL 的參數化查詢，防止程式碼注入風險
- case/esac：Shell 的多重分支語法，對應 C# switch，
  *) 萬用分支處理「不該發生但要防範」的例外值
- 三個工具、同一種「偏好 + fallback」設計理念的不同語法外殼：
  Shell 的 ||、jq 的 //、yt-dlp 格式選擇器的 /
- Shell function 的兩個獨立通道：exit code（成敗）與 stdout
  （輸出內容），兩者互不干涉，必須都主動管理，不能只顧其中一個
  （find_available_lang 若省略明確 return，最後一行 echo "" 
  成功執行會讓函式回傳「成功」，即使邏輯上代表「沒找到」）

### Best Practice
- 決策邏輯不能委託給 yt-dlp：「人工優先於自動、指定語言順序、
  fallback MP3」是我們專案特有的商業邏輯，必須自己在 script
  層決定，yt-dlp 只負責照決定執行 —— Thin Orchestration,
  Thick Logic 原則的再次套用
- 特意不處理 automatic_captions 的 -orig 語言保真度問題：
  技術上「更精確」不代表「更貼近真正需求」——下游消費者是
  中英文閱讀的使用者跟 AI 摘要工具,可讀性優先於保真度
- download_subtitle() 抽出 function：manual/auto 兩條 yt-dlp
  指令僅一個旗標不同,屬於 Rule of Three 的明顯訊號
- set -e 的一個真實陷阱：`VAR="$(func)"` 是裸賦值敘述，若 func
  失敗會直接觸發 set -e 中止整支 script，即使下一行是 if 判斷
  也救不回來——正確寫法是把賦值本身放進 if 條件式：
  `if VAR="$(func)"; then ... fi`，這樣才真正落在 set -e 的
  例外規則範圍內

<a id="phase-6-addendum"></a>
### 附錄 — 燒錄字幕 vs 系統字幕軌（真實案例）

**現象**：影片標題寫著「中文字幕」，但工具判定 source=auto、
language=en，且 `.subtitles | keys` 回傳空陣列。

**說明**：「畫面上看得到字幕」跟「YouTube 系統登記了一條可抽取
的字幕軌」是兩件完全不同的事。上傳者可能把字幕直接燒錄進影片
畫面（變成影片本身的像素），這種情況下 yt-dlp 完全無法把它當
文字抽出來，不管是 .subtitles 還是 .automatic_captions 都問
不到。

**結論**：系統判斷沒有錯，是誠實反映 YouTube API 的真實狀態。
這種影片只能靠 MP3 fallback（或未來 Whisper 語音辨識）取得
文字內容，沒有辦法透過抽取字幕軌拿到。


---

<a id="phase-7"></a>
## Phase 7 — 下載 Thumbnail 與 info.json

### Summary
新增 download_thumbnail()（yt-dlp --write-thumbnail
--convert-thumbnails webp）與 save_info_json()（把 Phase 3
已抓好的 METADATA_JSON 直接用 jq '.' 格式化寫檔，不打新的
網路請求）。新增 require_command "ffmpeg"。

### Code
download_thumbnail()：yt-dlp --skip-download --write-thumbnail
  --convert-thumbnails webp --output ".../thumbnail.%(ext)s"
save_info_json()：jq '.' <<< "$METADATA_JSON" > info.json
  （> 覆寫，不用 >>，因為 info.json 代表最新快照而非歷史累積）

### Concept
- yt-dlp 的 post-processor 概念：--convert-thumbnails 這類
  「下載完再轉檔」的功能，實際上是外包給 ffmpeg 執行，
  yt-dlp 扮演協調者角色（跟整個專案 Shortcut→Shell→yt-dlp
  的協調式架構，是同一個模式在不同層級的重複出現）
- jq '.' 從「探索工具」延伸成「格式化輸出工具」，同一語法
  服務不同目的
- > 與 >> 要依「這個檔案的語意」分別決定，不是無腦套用同一
  規則：log 用 >> 累積歷史，info.json 用 > 保持最新快照
- file 指令：讀檔案開頭的 magic number 驗證真實格式，
  不要只信任副檔名

### Best Practice
- 釐清「避免重複網路請求」原則的正確適用範圍：適用於避免
  重複查詢同一批文字欄位（Phase 3 情境），不適用於「下載
  媒體檔案」這個動作本身——字幕/音訊/縮圖各自需要 yt-dlp
  走不同管線，無法靠一次 metadata 查詢就生出實體檔案
- Rule of Three 訊號出現（三個 function 都是 yt-dlp+output+URL
  骨架）但結論是不合併：三者的「重複」只停留在實作細節
  （都呼叫同一個外部工具），業務邏輯本質不同，合併只會製造
  一個難讀的萬用函式 —— False DRY 概念的再次實戰應用
- 函式命名要誠實反映實際行為：save_info_json 而非
  download_info_json，因為它不涉及任何新的網路動作

---

<a id="phase-8"></a>
## Phase 8 — README.md 樣板產生

### Summary
新增 generate_readme()，用 Here-Document（未加引號的 << EOF）
產生 README.md，涵蓋 URL/Title/Uploader/Upload Date/Download
Time/Subtitle Language/Folder Name。新增 UPLOAD_DATE_FORMATTED
（參數展開子字串擷取 ${VAR:offset:length}）與
SUBTITLE_LANGUAGE_DISPLAY（依字幕決策最終結果組字串）。

### Code
generate_readme()：cat > "$path" << EOF ... EOF，函式只負責
排版輸出，不做任何判斷邏輯（判斷邏輯在 Main 區塊已完成）
UPLOAD_DATE_FORMATTED="${RAW:0:4}-${RAW:4:2}-${RAW:6:2}"

### Concept
- Here-Document 起源與運作機制：<< DELIMITER 把多行文字轉成
  stdin 餵給前面的指令，cat > file << EOF 是「stdin 重導向」+
  「stdout 重導向」的組合，不是字串型別，跟 C# raw string
  literal 概念相近但機制不同
- << EOF（未加引號）vs << 'EOF'（加引號）：決定 heredoc 內容
  是否展開變數/指令替換，直接對應雙引號 vs 單引號字串的規則，
  只是套用範圍從一行字串擴大到整段文字區塊
- 參數展開子字串擷取 ${VAR:offset:length}：跟 ${#VAR}（長度）
  同屬參數展開家族，索引從 0 開始，概念對應 C# 的 Substring()
- Heredoc 結尾標記必須「單獨一行、完全一致」：前面多縮排、
  後面多一個看不見的空格，都會讓 Shell 找不到終止點，導致把
  後續所有程式碼（包含 exit 0、後面的邏輯）都吞成 heredoc 內容，
  且不會讓 script 崩潰、不會被 set -e 抓到，是難以察覺的靜默錯誤
- `;` 和「換行」是同一件事的兩種寫法：if cmd; then（同一行需要
  分號）vs if cmd \n then（換行本身已扮演分隔符角色，不需分號）
  —— 這不是 heredoc 特有規則，是通用 Shell 文法

### Best Practice
- README 樣板方案比較：A（echo >> 疊加，繁瑣易錯）
  vs B（Heredoc 內嵌，採用）vs C（外部樣板檔案 + 佔位符取代，
  內容與邏輯分離但目前是 YAGNI）
  → 方案 C 不是永遠不做，是記錄成一個「有明確觸發條件」的
  未來重構點
- Thin Orchestration, Thick Logic 原則的新維度延伸：不只是
  「觸發媒介 vs 業務邏輯」要分開，「決策邏輯 vs 呈現邏輯」
  也該分開 —— generate_readme() 不重新判斷任何狀態，只負責
  把已經算好的結果排版輸出


---

<a id="phase-9"></a>
## Phase 9 — Logging 系統收斂

### Summary
新增 log_error()（統一「錯誤訊息+exit 1」複合動作）、
log_section_start() / log_section_end()（每次分析的起訖標記），
把散落在四五處的 log+exit 1 收斂成單一知識來源。

### Code
log_error()：log "[ERROR] ..." + echo stderr + log_section_end
  "failure" + exit 1
log_section_start(url) / log_section_end(result)：分隔線 +
  起訖標記，讓 archive.txt 可分段辨識

### Concept
- local -r：local（作用域限定）+ readonly（唯讀）的組合，
  適用於「只在這個 function 執行期間有意義的唯讀值」
- Observability（可觀測性）：log 檔案的價值不在「當下看得到」，
  而在「事後能快速定位」——分段標記是最低成本、效果扎實的
  可觀測性投資
- 診斷技巧：grep -c "Analysis started" vs "Analysis finished"
  數量是否相等，快速健檢有沒有分析中途被意外中止

### Best Practice
- 三次「該不該合併重複程式碼」的判斷回顧（sanitize_for_filename
  合併 / 三個 download_* 不合併 / log_error 合併）：判斷準則
  永遠是「代表的知識是否相同」，不是機械套用 Rule of Three
- 新抽象不代表無腦套用到每個角落：Main 開頭的參數檢查刻意
  不用 log_error()，因為那個時間點 log_section_start 還沒被
  呼叫，語意上不該記錄一個「未曾開始卻失敗結束」的分析

<a id="phase-9-addendum"></a>
### 附錄 — yt-dlp 裸呼叫繞過 log_error（真實踩坑紀錄）

**現象**：yt-dlp --dump-json 遇到無效網址失敗時，log 只停在
"Fetching metadata..."，沒有 [ERROR] 也沒有 "Analysis finished.
Result: failure"，grep -c 比對 started/finished 數量不相等。

**Root Cause**：`METADATA_JSON="$(yt-dlp ...)"` 是裸賦值敘述，
yt-dlp 失敗時這句賦值的 exit code 直接繼承失敗狀態，set -e
立即中止 script，完全繞過 log_error()。跟 Phase 6 
find_available_lang 的 bug 是同一個機制，這次發生在呼叫外部
工具（而非自己寫的 function）身上。

**Fix**：系統性稽核所有裸呼叫 yt-dlp 的地方（metadata fetch、
download_thumbnail、download_subtitle、download_audio_fallback），
統一改成 `if ! cmd; then log_error "..."; fi`。

**額外驗證的技巧細節**：函式呼叫包進 if 條件式時，set -e 的
豁免會傳遞進函式「內部」，但函式的 exit code 規則不變：依然是
「函式內最後一個指令的 exit code」——所以用來當 if 條件的函式，
最後一個指令必須就是你真正關心成敗的那個動作，不能後面還接一個
會洗掉失敗訊號的指令。

**Best Practice**：引入新的不變性保證（「每個致命錯誤都要走
log_error」）時，必須回頭稽核既有程式碼的每一條路徑，不能只
確保新寫的部分符合它。


---

<a id="phase-10"></a>
## Phase 10 — macOS Notification

### Summary
新增 send_notification()（呼叫 osascript display notification）
與 escape_for_applescript()（防止標題內雙引號打斷 AppleScript
語法，跟 jq --arg 同一個道理）。log_error() 新增一行呼叫，讓
所有錯誤路徑自動具備失敗通知能力。Main 結尾成功時發送
"Download Complete" + Subtitle Found/No Subtitle 副標題。

### Code
escape_for_applescript()：`${input//\\/\\\\}` 先跳脫反斜線本身，
再 `${input//\"/\\\"}` 跳脫雙引號 —— 順序不可顛倒
send_notification()：osascript -e "display notification ...
with title ... subtitle ..." || true（通知失敗不拖累整支 script）

### Concept
- osascript：Shell 呼叫 AppleScript 的橋樑，Notification Center
  沒有開放給 Shell 的直接介面，只能透過 AppleScript
- ${var//pattern/replacement}：Shell 內建全域字串取代，效果同
  sed s///g 但不需呼叫外部指令
- 跳脫特殊字元的通用原則：永遠先跳脫「跳脫符號本身」，再跳脫
  其他特殊字元，否則新增的保護符號會被自己的規則誤傷

### Best Practice
- 不是所有失敗都該走 log_error：通知失敗用 || true 直接放行，
  因為它不影響「下載/寫檔」這個核心任務是否達成，讓它拖累整體
  結果判定成 failure 反而更誤導人
- Phase 9 集中化錯誤處理的具體回報：新增失敗通知只需要在
  log_error() 加一行，而不是回頭修改十個分散的錯誤處理點——
  評估「值不值得重構」要看這個投資未來會被兌現幾次，不只看
  當下省了多少
- 同一份決策結果，給不同呈現場合（README vs 系統通知）用不同
  變數（SUBTITLE_LANGUAGE_DISPLAY vs NOTIFY_SUBTITLE_LINE），
  是「決策邏輯 vs 呈現邏輯」原則的再延伸

<a id="phase-10-addendum-1"></a>
### 附錄一 — TCC 授權會依「觸發當下最上層 App」而不同

**現象**：Safari 複製網址 → 直接按快速鍵 → 失敗（Operation not
permitted，下載縮圖失敗）。Safari 複製網址 → 先貼到 Terminal →
再按快速鍵 → 成功。網址本身、metadata 擷取、資料夾偵測都正常，
只有「第一次真正寫入檔案」這個動作失敗。

**已確認機制**：macOS 從 Mojave 起用 TCC（Transparency, Consent,
and Control）機制保護 ~/Documents 等資料夾，授權是「以呼叫的
App 為單位」分別記錄的，不會因為 Terminal.app 已被授權就自動
沿用。透過快速鍵觸發捷徑時，實際執行 script 的是背景程式
com.apple.WorkflowKit.BackgroundShortcutRunner（Phase 2 附錄
剪貼簿暫存檔路徑裡就出現過這個名字），它是一個獨立的呼叫者，
需要自己獨立的授權。

**Fix（部分有效）**：系統設定 → 隱私權與安全性 → 檔案與檔案夾
（或完整磁碟取用權）→ 找到「捷徑」App → 開啟「文件」資料夾
存取權 → 建議重開機讓已在背景執行的程序套用新權限。

**Concept 對應**：跟 Phase 2「Terminal 是 login shell、Shortcuts
是 non-login shell，PATH 環境不同」是同一個模式的另一種呈現：
不同呼叫環境（這次是不同的呼叫 App 身分），擁有的能力/權限不
必然相同，不能假設「在 Terminal 能動，別的地方就一定能動」。

<a id="phase-10-addendum-2"></a>
### 附錄二 — com.apple.macl：檔案級的存取控制（真實踩坑，未完全解開但已可安全結案）

**精確重現條件（實測確認）**：
1. 刪除舊資料夾 → 用 Terminal 直接執行 script 建立資料夾與檔案
2. 之後改用「捷徑」（Safari 複製網址 + 快捷鍵）觸發同一支影片
   → 覆寫 thumbnail.webp 時失敗：Operation not permitted
3. 反過來：刪除舊資料夾 → 第一次就用「捷徑」建立
   → 之後不管再用「捷徑」或改用 Terminal 重跑，都成功
4. 更細緻的一版：先用 Clipboard 版捷徑建立，再用 Share 版捷徑
   對同一支影片重新分析，同樣失敗；連 script 自己執行的 rm 都
   無法刪除這些檔案（「無權限刪檔」實測確認）

**確認的機制**：macOS 會在 ~/Documents 等受保護資料夾內的每個
檔案上，個別附加 com.apple.macl 這個隱藏標記，記錄「哪個身分
被允許存取這個檔案」，獨立於資料夾層級的 TCC 授權之外，即使
後者已完整授權（完整磁碟取用權），這層檔案級標記依然可能擋下
存取。連我們自己 script 執行的 rm，都一樣無法刪除被其他身分
標記過的檔案——這代表這個限制在 Shell script 層級沒有解法。

**未解開的部分（誠實記錄，已達公開資料查證極限）**：「Terminal
建立的檔案，換捷徑覆寫會失敗；捷徑建立的檔案，換誰覆寫都成功」
「連同一個捷徑 App 底下，不同的個別捷徑之間也會被視為不同身分」
——這些不對稱性的確切原因，超出目前查得到的公開資料範圍，連
專門研究此機制的資安研究者都表示官方文件付之闕如。

**務實結論**：本專案正式設計的觸發方式只有 Safari 分享與剪貼簿
快捷鍵，兩者都經過「捷徑」——真實使用情境下，任何影片的資料夾
必然是由「捷徑」最先建立。此問題只在「跨觸發方式重新分析同一支
已分析過的影片」時出現。判斷結案的標準：不是「徹底消除所有理論
上的邊界情況」，是「確認這個邊界不會在正確的使用方式下出現」，
並將其記錄為使用須知（見 README.md 的 Known Limitations）。

**曾嘗試但確認無效的方案**：新增 clear_stale_output_files()
主動用 rm -f 清除舊檔案，實測後確認同樣「無權限刪檔」，已從
程式碼中移除——防禦性程式碼跟其他程式碼一樣，驗證後發現沒用
就該誠實刪除，不是加上去就不再檢視。


---

<a id="phase-11"></a>
## Phase 11 — 自動打開 Finder

### Summary
新增 open_download_folder()，用 open（Launch Services）而非
osascript 控制 Finder 來開啟下載資料夾。補上 Phase 10 遺漏的
require_command "osascript"。

### Code
open_download_folder()：`if ! open "$dir" 2>/dev/null; then
  log "Warning: ..."; fi` —— 非致命失敗，只記警告

### Concept
- open 命令走 Launch Services（請系統用預設程式開啟路徑），
  跟 osascript 的 tell application "Finder" 走 Apple Events
  完全是不同機制
- TCC 的 Automation（自動化）授權類別，專門管「控制其他 App」，
  跟 Phase 10 的「檔案與檔案夾」是獨立分類；且一旦被拒絕，
  不會自動重新詢問，需手動到系統設定或用 tccutil 重置

### Best Practice
- 相同目標、不同機制、不同權限成本：能用更輕量、風險更低的
  方式達成一樣效果時，不需要拘泥於最初架構圖畫的路徑
  （AppleScript 只在 Notification 這裡是必要的，Finder 這裡
  open 就夠了）—— 回頭檢視最初藍圖，是否每條線都仍然必要
- 系統性稽核的又一次應用：新工具依賴要記得補進 require_command
  清單，不能只顧著讓新功能能動

---

<a id="phase-12"></a>
## Phase 12 — 自動開啟 ChatGPT

### Summary
新增 open_chatgpt()，用 open 開啟 https://chatgpt.com（跟
open_download_folder 是同一個工具，這次餵給它 URL 而非本機
路徑）。刻意不做「自動把字幕內容塞進網頁」這個看似更貼心的
功能，並說明理由。

### Code
open_chatgpt()：`if ! open "$CHATGPT_URL" 2>/dev/null; then
  log "Warning: ..."; fi` —— 跟 open_download_folder 同一套
  「非致命失敗」哲學

### Concept
- open 不只能開檔案/資料夾路徑，也能開 URL，Launch Services
  會自動判斷交給系統預設瀏覽器處理——同一工具、不同輸入類型，
  自然延伸出新能力，不需要學新語法

### Best Practice
- 自動化的目標是消除「重複性、無決策價值」的操作步驟（找分頁、
  打網址），不是連「需要人腦判斷」的環節也一併取代——分辨這條
  界線比技術實作本身更重要
- 方案比較：自動塞剪貼簿（pbcopy）→ .srt 格式含時間碼雜訊，
  需要額外的資料前處理，超出本 Phase 範圍；自動操控瀏覽器貼入
  網頁 → 需要 Automation 授權且極度脆弱，綁定第三方網站介面
  細節；兩者都拒絕，只做「把工具準備好、開在使用者眼前」
- 知道「可以做」和「應該做」是兩件事，並能清楚說出「不應該做」
  的具體理由

---

<a id="phase-13"></a>
## Phase 13 — Safari Share Sheet 整合

### Summary
建立全新獨立捷徑「YT Analyzer (Share)」，開啟「在分享表單中
顯示」，用「取得輸入的網址」取得分享內容，呼叫跟 Phase 2 完全
相同的 youtube-ai-analyzer.sh，不修改任何 .sh 程式碼。

### Code
本階段無程式碼異動，純 Shortcuts App 設定：
Share Sheet Input → Get URLs from Input → Run Shell Script
(/bin/zsh, as arguments) → 同一支 script

### Concept
- Share Extension：App/捷徑向系統「登記」能處理的內容類型，
  系統彙整所有登記者列成分享選單
- 分享內容也有多重表示法（跟 Phase 2 剪貼簿的教訓同一個模式）：
  網址、標題、截圖可能同時存在，需明確指定要哪一種類型

### Best Practice
- 兩個獨立捷徑（Share/Clipboard）優於一個捷徑+條件判斷：
  避免把「分辨觸發來源」這個問題，從 .sh 層搬到 Shortcuts 層
  重新處理一次 —— Thin Orchestration 原則延伸到多入口情境
- 兩捷徑間唯一重複的「呼叫 script」那一行，屬於 False DRY：
  不代表需要維護的邏輯知識，真正的知識只有一份，在 .sh 檔案裡
- 本 Phase 是 Phase 2 架構決定的直接回報驗證：新增一整個觸發
  模式，完全未觸碰核心邏輯，零回歸測試風險

---

<a id="phase-14"></a>
## Phase 14 — Clipboard + 快捷鍵版整合收斂

### Summary
系統性核對兩個捷徑（Clipboard/Share）的設定一致性，匯出
.shortcut 檔案至新增的 shortcuts/ 資料夾，撰寫文字化的設定
說明放進 docs/Shortcuts-Setup.md，並把已知限制正式寫進
README.md 的 Known Limitations 章節。

### Concept
- .shortcut 匯出檔案是二進位 plist，無法被 git 有意義地 diff；
  文字說明負責「可讀、可版控、可講給別人聽」，兩者互補而非
  互相取代（呼應 Phase 8 heredoc vs 外部樣板的判斷邏輯）
- 匯出方式：選單列 File → Export（不是編輯畫面右上角那個分享
  圖示，那個是「分享執行結果」用的，跟「匯出捷徑本身」是兩件事）
- plutil -p：可將 plist 轉成人類可讀的樹狀結構，選讀

### Best Practice
- 系統性稽核不只用於程式碼（Phase 9），GUI/設定層面同樣需要
  逐項檢查清單，不能因為「看不到原始碼」就跳過
- 新增 shortcuts/ 資料夾是回頭修正原始藍圖的合理案例：因為
  「GitHub 作品集可讀性」這個明確目標，服務了這個新增項的
  正當性，不是範圍蔓延


---

<a id="phase-15"></a>
## Phase 15 — Defensive Programming 總複查

### Summary
新增 validate_url_format()（寬鬆的 URL 語法前置檢查，不取代
yt-dlp 的權威判斷）與 truncate_to_byte_limit()（用 python3
安全地在 UTF-8 byte 邊界截斷字串，處理 APFS 255 bytes 檔名
限制）。

### Code
validate_url_format()：`[[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+ ]]`
  =~ 是 [[ ]] 專屬的正規表示式比對運算子，pattern 端不能加引號
  （加了會變成純字面比對，失去正規表示式解析能力）
truncate_to_byte_limit()：python3 -c 搭配 sys.argv 傳資料（不要
  把 Shell 變數直接拼進 Python 程式碼字串，避免注入風險，跟
  jq --arg 同一個安全原則），encode/decode 搭配 try/except 逐
  byte 回退，找到安全的 UTF-8 邊界

### Concept
- APFS 檔名限制是 255 UTF-8 bytes，不是 255 字元；中日文字元
  多半佔 3 bytes，純中文標題實際容量遠低於直覺預期
- ${#VAR} 量字元數，wc -c 量 byte 數，兩者是不同的量測工具，
  對應不同的限制情境
- ${VAR:0:N} 切字元位置，不保證 byte 邊界安全；需要 byte 邊界
  安全截斷時，改用 python3 的 encode/decode
- sys.argv：Python 版的位置參數，概念對應 Shell 的 $1 $2
- str.encode('utf-8') 把字元序列轉成位元組序列，len() 在兩種
  型別上量出的意義完全不同——同一個工具，套用在不同型別上，
  結果語意完全不同

### Best Practice
- Edge case 處理時機：不是專案一開始就預先寫好所有理論邊界，
  是累積足夠真實案例後，有依據地判斷「這個情境值不值得處理」
  —— YAGNI 的延伸應用
- 分層防禦：便宜、寬鬆的檢查放前面（URL 語法），昂貴、精確的
  判斷交給更權威的下游（yt-dlp 對 YouTube 網址格式的理解）—
  不重複造輪子，也不會因為自訂規則過時而誤判
- 漸進式引入新工具：不因為複雜就整個重寫成 Python，只在
  Shell 能力邊界處，精準補一小塊新工具擅長的部分
- 遇到「有沒有正確處理某個複雜規則」的問題時，優先想「有沒有
  現成、已經被驗證過的工具可以幫我判斷」，而不是自己重新推導
  一遍規則（借用 Python 內建 UTF-8 解碼器判斷邊界是否合法）

---

<a id="phase-16"></a>
## Phase 16 — Refactor

### Summary
新增 main() function 包住整個分析流程，搭配 main-guard，讓
script 被 source 時只載入 function 定義。系統性稽核現有
function 與 Main 的長度，結論是均不需要拆分；保留
download_* 函式對 $URL/$DOWNLOAD_DIR 的隱含全域依賴。

### Code
main-guard 最終版本（見附錄，中間經過修正）：
```
if [[ "$(basename -- "$0")" == "youtube-ai-analyzer.sh" ]]; then
    main "$@"
fi
```

### Concept
- main-guard 概念對應 Python 的 if __name__ == "__main__"：
  同一份程式碼，「被直接執行」跟「被當作函式庫載入」要有不同行為
- main-guard 的附帶好處：Main 邏輯有了真正的 function 作用域，
  終於能對只用一次的中繼值使用 local，減少不必要的全域變數

### Best Practice
- 稽核不代表一定要找到問題：逐一檢視現有 function 後，誠實
  結論是「目前沒有需要拆分的」，這跟找出真正該拆的問題一樣，
  都是稽核該有的正當產出
- SRP 檢驗的是「改變理由的數量」，不是「行數多寡」：Main 雖長，
  但只有單一改變理由（這支影片分析流程的步驟與順序），且步驟
  間無重複，拆成一次性階段函式不會減少重複，只會增加追蹤成本
- 隱含全域變數 vs 明確傳參數：$URL/$DOWNLOAD_DIR 是 readonly
  （排除意外被改的風險）且本質上是「這次執行唯一、不變」的值，
  保留隱含依賴是誠實反映事實，不是偷懶——但若未來被抽成可重用
  函式庫，這個判斷會反轉
- 三個判斷共用同一套檢驗邏輯：「這個改動有沒有解決真實問題、
  帶來可具體指出的好處」——Refactor 的核心不是讓程式碼更有
  層次感，是有明確理由才動手，且能為「不動手」的地方也說出理由

<a id="phase-16-addendum"></a>
### 附錄 — main-guard 修正紀錄：$ZSH_EVAL_CONTEXT 不可靠，改用 $0

**現象**：第一版 main-guard 用 `$ZSH_EVAL_CONTEXT == "toplevel"`
判斷，實測發現：(1) source 時報 unbound variable；(2) 加上
`${ZSH_EVAL_CONTEXT:-}` 防護後，連「直接執行」也被誤判成不該
呼叫 main（值同樣是 UNSET）。

**原因**：$ZSH_EVAL_CONTEXT 在「透過 shebang 執行的 script 檔案」
這種情境下，不保證會被賦值，行為不如部分文件描述的穩定，不適合
用來判斷「這是不是被直接執行」。

**修正**：改用更基本、驗證更充分的機制：$0
- 直接執行時：$0 是這支 script 自己的路徑/檔名
- 被 source 時：$0 維持呼叫端（互動式 Shell）自己的 $0
  （通常是 -zsh 或 zsh），不會變成這支 script 的名字

**已知限制**：檔名寫死在判斷式裡，若重新命名這支 script，
判斷式會失效，需要同步更新。

**教訓**：zsh 較新、較少被使用的特殊變數，即使查到文件描述其
行為，也不能保證在所有實際情境下都如文件所寫一致運作；$0 這種
歷史悠久、幾乎所有 Shell 都遵守的基本機制，通常更值得信賴。
真正可靠的知識，來自實測，不是查證本身。

---

<a id="phase-17"></a>
## Phase 17 — 未來擴充預留點

### Summary
盤點 Whisper、AI Summary/Keyword Extraction、Obsidian 深度
整合三大類未來功能，逐項確認現有架構是否已有天然掛勾點，
不做任何提前實作。

### Whisper（語音轉字幕）
掛勾點：download_audio_fallback() 產生的 MP3，本身就是 Whisper
的輸入。實作時可在 Main 呼叫 download_audio_fallback 之後，
新增 transcribe_with_whisper() function。無需預先準備。

### AI Summary / Keyword Extraction（OpenAI/Claude/Gemini API）
設計原則：比照 Phase 12「不自動貼字幕進 ChatGPT」的判斷邏輯——
自動摘要等同替使用者決定「這支影片該怎麼被理解」，需要謹慎
考慮是否自動化到什麼程度。若要做，結果應獨立寫成 summary.md，
不與 README.md 混合，維持「工具記錄的事實」與「AI 推論」的
分界（呼應 Phase 8 決策邏輯/呈現邏輯分離原則）。

### Obsidian 深度整合
現有 README.md 已滿足基本需求（Obsidian 本質是讀 Markdown
資料夾）。深度整合（wikilink、索引頁）可用獨立 function 疊加，
不影響現有邏輯。

### Best Practice
- 判斷原則：掛勾點已存在（如 Whisper）→ 不用預留，現在不做
  準備完全不會增加未來成本；涉及需要謹慎的產品設計決策（如
  AI Summary）→ 更不該現在倉促預留程式碼，那只會困住未來
  真正要做決定時的空間

---

<a id="phase-18"></a>
## Phase 18 — GitHub 上架

### Summary
建立 .gitignore（排除 logs/archive.txt 個人使用紀錄與 .DS_Store）、
LICENSE（MIT）、專案根目錄 README.md（區別於每支影片資料夾裡的
分析結果 README），並完成第一次正式 git commit。

### Concept
- .gitignore 是「請 git 別去注意」，不是刪除；只對「尚未被
  追蹤」的檔案生效
- git 只追蹤檔案，不追蹤空資料夾；.gitkeep 是社群慣例（非 git
  官方功能），用一個空白佔位檔案，間接讓空資料夾也被版本控制
  保留下來——這是為了讓全新 clone 下來的人，logs/ 資料夾依然
  存在，script 的 tee -a 才不會因為資料夾不存在而失敗
- .gitignore 要放在專案根目錄（跟 .git/ 同一層），不是 .git/
  資料夾裡面——.git/ 是 git 自己的內部資料庫，不是給使用者手動
  放置檔案的地方

### Best Practice
- LICENSE 選擇：MIT（極簡、寬鬆）vs Apache 2.0（多專利條款，
  適合大型/企業專案）vs GPL（copyleft，強制衍生作品開源）——
  個人作品集/展示專案，MIT 最貼合目的
- Commit 歷史的誠實性：不要事後偽造一份「看起來循序漸進」的
  假歷史來美化作品集——commit 歷史、log 檔案、Obsidian 附錄，
  三者背後是同一個工程倫理：任何紀錄的價值，建立在「它是真實
  發生過的」這個前提上，一旦開始為了好看而竄改，紀錄就從「有
  價值的歷史」變成「不可信的裝飾」
- 文件架構的 DRY：Shortcuts 設定的「操作步驟」只活在
  docs/Shortcuts-Setup.md 一份文件裡；MentorHandbook.md 只保留
  「為什麼這樣設計」的討論，不重複具體操作步驟——同一份知識
  不該同時存在於兩份文件、各自維護

---

<a id="known-limitations"></a>
## 已知限制總覽

**跨觸發方式重新分析同一支影片**：若某支影片曾用其中一種觸發
方式（Clipboard 或 Share）分析過，之後改用另一種方式對同一支
影片重新分析，會遇到 macOS 層級的 `Operation not permitted`
錯誤（詳見 Phase 10 附錄二：com.apple.macl 檔案級存取控制）。
這是 macOS 作業系統層級的限制，不是本專案程式邏輯的缺陷，經
實測確認連程式自己執行的檔案刪除都無法突破。

**解法**：手動刪除該影片在 `~/Documents/YoutubeAnalysis/`
底下的資料夾，再重新觸發分析。

**不受影響的情境**：
- 同一支影片，重複用「同一種」觸發方式重新分析：正常
- 分析一支全新、從未處理過的影片，不管用哪種觸發方式：正常
- 只有「換成另一種觸發方式，分析『已經被分析過』的影片」才會
  遇到此限制
