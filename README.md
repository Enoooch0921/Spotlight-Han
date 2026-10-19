# Spotlight Han · 繁簡互搜的 macOS Spotlight alternative

<img src="Assets/SpotlightHan.png" alt="Spotlight Han app icon" width="128" />

An open-source macOS Spotlight alternative with Traditional/Simplified Chinese search, independent local filename search, calculator, and Apple Notes integration.

用自己習慣的中文搜尋 App、影片、檔名和文件。目標是成為 Spotlight 的開源替代品，先把「緊急時找得到檔案」做好。

**目前版本：0.5.0，開發預覽。尚未達到 Spotlight 的完整功能對等。**

## 為什麼做 Spotlight Han？

我們能看懂繁簡中文，電腦卻常常把它們當成完全不同的搜尋詞。

- **App 明明裝了，繁體卻找不到簡體名稱。** 例如 App 叫「红果短剧」，習慣輸入「紅果短劇」卻漏掉結果。
- **Word 用簡體寫，繁體關鍵字搜不到內容。** 人記得內容，不一定記得當時用了哪種字形。
- **緊急要播的影片，知道檔名卻找不到。** 在現場播放、教學或活動中，等索引、重建搜尋都不實際。
- **搜尋慢，結果還混進很多不相關內容。** 找影片時需要影片；算數時需要答案。
- **換個搜尋外觀，未必換掉原本的索引問題。** Spotlight Han 的檔名／影片搜尋自己建立清單，文件內容則有明確分開的搜尋方式。

磁碟空間不足確實可能使整台 Mac 變慢，但不能用來解釋所有漏搜。這個專案把「繁簡匹配」「檔案是否被索引」「結果篩選」分開處理，並顯示目前實際搜尋的範圍。

## 功能

| 功能 | 目前範圍 |
| --- | --- |
| 繁簡互搜 | 查詢與文字統一字形；保留原始檔案與顯示文字。不是同義詞搜尋。 |
| App | 本機應用程式名稱，包含繁簡比對。 |
| 快速檔名／影片 | 首次選擇搜尋範圍，再自行掃描使用者授權的資料夾；不依賴 Spotlight。影片只按副檔名篩選，不讀取影音內容。 |
| Word／PDF 內容 | 可指定資料夾讀取 DOC、DOCX、RTF、ODT、UTF-8 文字與有文字層的 PDF。未指定時，僅此模式使用 Spotlight。 |
| 計算器 | 四則、括號、次方、百分比、平方根、常用函數；三角函數使用弧度。專用解析器，不執行任意程式碼。 |
| 單位換算 | 長度、重量、時間、資料容量、溫度，如 `32°F in Celsius`。貨幣換算由獨立的公開匯率表提供。 |
| 貨幣換算 | `3000台幣=rmb`、`nt3000 = rmb`、`3000nt = rmb`，以及 TWD／CNY／USD 等常見幣別。免費每日參考匯率，顯示資料時間與來源，非即時行情。 |
| 本機翻譯 | 非中文查詢上方顯示繁體中文翻譯，下方仍搜尋原查詢。使用 Apple Translation（macOS 15+），首次需準備語言；不把查詢傳給第三方翻譯服務。 |
| 自訂快捷鍵 | 按下按鍵組合錄製、保存、恢復預設；按同一快捷鍵開啟／收起面板。提供直接開啟系統 Spotlight 快捷鍵開關的入口及 ⌘Space 設定。 |
| 網址與網頁 | 開啟 HTTP/HTTPS 網址；無本機結果時提供 Google 搜尋動作，按下 Return 後才連網。 |
| 辭典 | 輸入 `define apple` 或 `查 單字` 使用 Mac 安裝的辭典。 |
| 備忘錄 | 選擇連接後讀取系統 Notes 標題、純文字；最多 2,000 則，不讀取密碼保護筆記。 |
| 聯絡人 | 經授權讀取姓名、電話與電郵，顯示與複製詳細資料。 |
| 行事曆 | 經授權搜尋前後各一年行程，最多 10,000 筆，顯示與複製詳細資料。 |
| 提醒事項 | 經授權搜尋未完成事項；可用中文指令新增到系統預設清單。 |
| 系統鬧鐘 | 一次加入內附捷徑後，由 Apple「時鐘」建立及管理。精度為分鐘，向上取整；只支援下一次指定時分。 |
| 中文建立指令 | 行程、提醒、鬧鐘先預覽，再按 Return 建立。例：`明天下午3點開會30分鐘`。 |
| 郵件 | 系統 Mail 收件匣前 200 封，每封內文前 16,000 字；按結果開啟郵件。不是全信箱索引。 |
| 捷徑 | 手動連接本機捷徑清單；執行前再次確認。 |
| 剪貼板 | 預設關閉，選擇啟用後只在記憶體保留本次執行期間最近 50 筆文字。 |

備忘錄、郵件、聯絡人、行事曆、提醒事項、捷徑需要在設定中連接；受系統授權、帳號配置及 App 腳本介面影響。這些私人資料來源的真實內容不屬於自動化測試範圍。未連接、連接失敗、讀取範圍會顯示於設定。

## 介面與快捷鍵

以 [Apple 的 macOS 27 Spotlight 官方參考](https://support.apple.com/zh-tw/guide/mac-help/mchl4d69efd3/27/mac/27)為設計依據：浮動搜尋膠囊、四個圓形分類入口、輸入後展開的結果面板。macOS 26 以上使用原生 Liquid Glass；較舊系統使用原生模糊材質。透明的 AppKit 容器與四周留白讓系統陰影自然延伸，避免矩形底板及截斷邊緣。詳情在原面板中展開，不使用會在透明視窗四周留下矩形遮罩的彈出頁；語言準備使用獨立的標準視窗。

- 預設 `Control + Option + Space`：開啟／收起搜尋。可在設定錄製自訂組合，需搭配 Command、Control 或 Option；衝突時保留原本快捷鍵。
- `Command + 1 / 2 / 3 / 4`：App／檔案／動作／剪貼板。
- `↑ / ↓` 選擇；`Return` 開啟或複製；`Command + R` 在 Finder 顯示。
- `Escape` 收起。選單列可開啟設定與結束 App。

這是獨立產品，不是 Apple Spotlight 的外掛。App 不修改系統 Spotlight；可按「開啟 Spotlight 快捷鍵開關」直接定位到系統勾選框，由使用者關閉原生 `Command + Space` 後，回 App 按「使用 ⌘Space」。也可以隨時改回其他組合、在系統重新啟用 Spotlight。目前以 macOS 26.6.1 驗證；尚未完成 macOS 27 真機逐像素驗收。Logo 是另行製作的放大鏡圖案，未使用 Apple 的 Spotlight 圖檔。Apple 的名稱及商標歸 Apple 所有，專案與 Apple 無關。

## 首次集中選擇檔案範圍

啟動時不會自動探查未選的下載／文件資料夾。按「選擇搜尋資料夾…」，可按住 Command 多選；選擇自己的使用者資料夾時，只把下載、影片、文件加入索引。選擇其他資料夾則索引該資料夾。App 保存並恢復 security-scoped bookmarks，維持已選範圍的存取；資料夾移動／重新命名時會嘗試恢復位置。未選範圍不讀取，也不載入舊快取中的結果。

「移除」停止索引指定範圍；「忘記資料夾」會停止存取、移除保存的書籤及檔名快取。macOS 撤銷權限、磁碟變更、簽章改變或書籤失效時仍可能需要重新選擇，不保證永久免授權。首次檔案選擇、Notes／Calendar 等系統隱私權也仍由使用者確認，並非同一個總開關。

## 一次集中設定，之後自動連接

在設定中按 **「一次設定所有資料來源」**，會依序連接備忘錄、聯絡人、行事曆、提醒事項、郵件、捷徑與系統時鐘。成功啟用的來源會記住，之後啟動會自動讀取，不需要每次逐個連接。

macOS 的 Contacts、Calendars、Automation 是不同權限；系統仍可能分別請你確認。完整磁碟存取也不能取代這些權限，App 沒有一個可略過它們的總開關。[Apple 權限說明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)

目前本機建置預設是 ad hoc 簽章，重新編譯後程式的代碼身份可能改變，系統可能重新詢問權限。正式版本應使用穩定的 Apple Development／Developer ID 簽章；可透過 `CODE_SIGN_IDENTITY` 指定已有的簽章身份。腳本不會建立憑證、改寫系統授權資料庫或關閉系統保護。

## 翻譯與每日參考匯率

非中文查詢會先搜尋 App／檔案，翻譯另外非同步顯示在最上方；原查詢及搜尋結果保持原樣，不會自動改用譯文搜尋。翻譯不搶走已選 App／檔案的 Return 動作。使用 Apple 的本機 Translation，缺少語言時顯示「準備本機繁體中文翻譯」，由使用者選取後按 Return 或連按兩下，開啟獨立語言視窗，再按「開啟語言下載設定」準備來源語言及繁體中文；回到 App 會自動檢查；已準備的語言可跨 App 共用。語言下載、支援範圍與完成狀態由 macOS 決定。一般搜尋不會自動跳出下載對話框；macOS 26 以上使用只接受已安裝語言的 session，macOS 26.4 以上偏好適合短查詢的 low-latency 模型。設定中可關閉自動翻譯。

貨幣辨識支援前置／後置 NT、NT$、台幣、TWD，以及 RMB、人民幣、CNY 等寫法；例如 `3000台幣=rmb`、`nt3000 = rmb`、`3000nt = rmb`、`100 USD to TWD`。它採用 [ExchangeRate-API 免費公開端點](https://www.exchangerate-api.com/docs/free)，**每日更新，非即時／盤中行情**。畫面附上來源連結、匯率資料時間與「每日更新」，也會標示離線時使用的過期快取（最多七天）。這是參考中間價，並非銀行買入／賣出或實際成交價。

只請求固定的公開 USD 匯率表，在本機換算；不傳送輸入金額、完整查詢、檔名、文件或私人資料。共用匯率快取並合併同時請求，失敗後會退避，避免每輸入一個字就連網。開源程式碼不包含即時匯率的付費帳號或 API Key。

## 系統時鐘：只需加入一次

1. 在 App 的設定按 **「連接系統時鐘」**。
2. 在 Apple 捷徑視窗檢視並按 **「加入捷徑」**。不用編輯動作或填寫時間參數。
3. 回到 App 會自動檢查連接；也可手動按「檢查連接」。之後直接輸入 `設定30分鐘後的鬧鐘`，預覽後按 Return。

內附的 `Spotlight-Han-System-Clock` 只把本機 JSON 中的時間與標籤交給 Apple 時鐘的「加入鬧鐘」動作，最後回傳完成標記。App 使用 [Apple 支援的 shortcuts 命令列介面](https://support.apple.com/en-gb/guide/shortcuts-mac/apd455c82f02/mac)，不需要使用者手動製作捷徑。捷徑可檢閱原始碼於 [SystemClock.plist](Assets/Shortcuts/SystemClock.plist)；發行檔已簽署。App 會建立並清除本機暫存 JSON，不使用剪貼板，不上傳鬧鐘資料。首次加入的系統操作無法由 App 靜默代替；系統仍可能顯示自己的執行確認。

鬧鐘由 Apple 時鐘響鈴及管理，Spotlight Han 不維護另一份鬧鐘清單。超出下一次指定時分的未來日期會拒絕建立，請改用提醒事項，避免系統鬧鐘提早響鈴。秒數向上取整到分鐘，實際時間在預覽顯示；相對時間在按 Return 時起算。此版本尚未接入系統「計時器」，不把倒數指令悄悄改成鬧鐘。

已在 macOS 26.6.1 實測由橋接捷徑建立有名稱的系統鬧鐘、核對時間與名稱，並清除測試鬧鐘。若捷徑執行失敗或未收到完成回覆，App 會要求先開啟時鐘核對，避免盲目重試。行事曆／提醒事項的寫入使用 EventKit，需你授權；私人帳號的實際寫入未納入自動化測試。

## 建置

需要 macOS、Swift 5.9 以上，以及含 macOS 26 SDK 的 Xcode／Command Line Tools。執行最低 macOS 14；目前本機驗證為 Apple Silicon。

```sh
git clone https://github.com/Enoooch0921/Spotlight-Han.git
cd Spotlight-Han
./script/build_and_run.sh
```

腳本建立 `outputs/Spotlight Han.app` 並以本機簽章啟動。`--build-only` 只建置，不啟動。沒有第三方套件依賴；發行給其他 Mac 的 Developer ID 簽章與公證尚未設定。

```sh
swift run HanSearchChecks
swift run HanSearchChecks --benchmark
python3 script/verify_clock_shortcut.py
mkdir -p work
swiftc -parse-as-library Sources/HanSearch/Services/FileAccessBookmarks.swift script/check_folder_bookmarks.swift -o work/BookmarkChecks
work/BookmarkChecks
```

使用獨立檢查程式，能在沒有 XCTest 的 Command Line Tools 環境執行。涵蓋真實 DOCX 擷取、檔名索引、繁簡比對、算式安全、單位換算與查詢跳脫。`--benchmark` 使用本機現有檔名快取，僅印數量與比對時間，不印私人路徑或檔名。

## 搜尋範圍與更新

已選範圍的檔名清單在啟動時掃描，叫出面板時如距上次更新超過 30 秒會重新掃描；新檔案可手動按更新。**不是即時檔案監看器**。隱藏檔、套件內部，以及 `node_modules`、`Pods`、`DerivedData`、`venv`、`__pycache__` 的內部預設不掃描；最多 500,000 筆。無權讀取與超限會顯示狀態。

指定資料夾的文件內文只留在記憶體，結束後需重新加入；修改文件後按重新讀取。單檔 20 MB、文字總量 32 MB、最多 10,000 檔案。掃描 PDF、照片沒有 OCR；非 UTF-8 純文字可能無法讀取。

## 隱私與儲存

- 沒有自建伺服器、分析追蹤或查詢自動上傳。貨幣換算會按需下載公開匯率表；首次翻譯會由 Apple 下載語言模型。
- 檔名及其所在路徑快取於使用者的 `Library/Caches/local.hansearch.mac/Filenames-v1.json`。它包含私人檔名，不應分享。
- 已選資料夾的存取書籤、索引範圍、快捷鍵與啟用的資料來源記錄於本機偏好設定，不納入 Git。
- 文件內文與已連接的私人資料搜尋副本只留在記憶體；不存進檔名快取。只有按 Return 確認的新增指令會寫入系統行事曆、提醒事項或時鐘。
- 剪貼板預設關閉。會略過隱藏／暫存標記及常見密碼管理器，但其他 App 沒標示的敏感文字仍可能被記錄。關閉即清除記錄。
- 備忘錄不會解鎖受密碼保護的筆記。來源移除會清掉記憶體副本；撤銷系統授權請到系統設定。
- `work/`、`outputs/`、建置產物和本機索引不納入 Git。

## 待完成的功能對等

- [ ] macOS 27 真機外觀、無障礙與鍵盤驗收
- [x] 可設定的全域快捷鍵與 `Command + Space` 開關頁入口
- [ ] 檔案變更事件的增量索引、外接磁碟／NAS 明確狀態
- [ ] 備忘錄與全信箱的增量更新、更多資料範圍選項
- [ ] 原生行程／聯絡人深層連結與完整預覽
- [ ] 系統計時器、更多日期語法、行程／提醒寫入的完整互動驗收
- [ ] 可選盤中匯率來源、天氣，以及更多系統動作
- [ ] OCR、更多文件格式與可持久化的內容索引
- [ ] Developer ID 簽章、公證、可安裝發行包

Siri／Apple Intelligence 的系統私有能力不包含在目前的替代範圍中。

## 貢獻與授權

歡迎提出可重現的問題、效能數據與 Pull Request。回報請使用自製測試文件，不要附上私人備忘錄、信件、通訊錄或檔名快取。

MIT License · Copyright 2026 Enoooch0921.
