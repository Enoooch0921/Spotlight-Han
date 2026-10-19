# Spotlight Han · 繁簡互搜的 macOS Spotlight alternative

<img src="Assets/SpotlightHan.png" alt="Spotlight Han app icon" width="128" />

An open-source macOS Spotlight alternative with Traditional/Simplified Chinese search, independent local filename search, calculator, and Apple Notes integration.

用自己習慣的中文搜尋 App、影片、檔名和文件。目標是成為 Spotlight 的開源替代品，先把「緊急時找得到檔案」做好。

**目前版本：0.3.0，開發預覽。尚未達到 Spotlight 的完整功能對等。**

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
| 快速檔名／影片 | 自行掃描下載、影片、文件，以及使用者加入的資料夾；不依賴 Spotlight。影片只按副檔名篩選，不讀取影音內容。 |
| Word／PDF 內容 | 可指定資料夾讀取 DOC、DOCX、RTF、ODT、UTF-8 文字與有文字層的 PDF。未指定時，僅此模式使用 Spotlight。 |
| 計算器 | 四則、括號、次方、百分比、平方根、常用函數；三角函數使用弧度。專用解析器，不執行任意程式碼。 |
| 單位換算 | 長度、重量、時間、資料容量、溫度，如 `32°F in Celsius`。不提供即時匯率。 |
| 網址與網頁 | 開啟 HTTP/HTTPS 網址；無本機結果時提供 Google 搜尋動作，按下 Return 後才連網。 |
| 辭典 | 輸入 `define apple` 或 `查 單字` 使用 Mac 安裝的辭典。 |
| 備忘錄 | 選擇連接後讀取系統 Notes 標題、純文字；最多 2,000 則，不讀取密碼保護筆記。 |
| 聯絡人 | 經授權讀取姓名、電話與電郵，顯示與複製詳細資料。 |
| 行事曆 | 經授權搜尋前後各一年行程，最多 10,000 筆，顯示與複製詳細資料。 |
| 郵件 | 系統 Mail 收件匣前 200 封，每封內文前 16,000 字；按結果開啟郵件。不是全信箱索引。 |
| 捷徑 | 手動連接本機捷徑清單；執行前再次確認。 |
| 剪貼板 | 預設關閉，選擇啟用後只在記憶體保留本次執行期間最近 50 筆文字。 |

備忘錄、郵件、聯絡人、行事曆、捷徑需要在設定中連接；受系統授權、帳號配置及 App 腳本介面影響。這些私人資料來源的真實內容不屬於自動化測試範圍。未連接、連接失敗、讀取範圍會顯示於設定。

## 介面與快捷鍵

以 [Apple 的 macOS 27 Spotlight 官方參考](https://support.apple.com/zh-tw/guide/mac-help/mchl4d69efd3/27/mac/27)為設計依據：浮動搜尋膠囊、四個圓形分類入口、輸入後展開的結果面板。macOS 26 以上使用原生 Liquid Glass；較舊系統使用原生模糊材質。

- `Control + Option + Space`：喚出搜尋。
- `Command + 1 / 2 / 3 / 4`：App／檔案／動作／剪貼板。
- `↑ / ↓` 選擇；`Return` 開啟或複製；`Command + R` 在 Finder 顯示。
- `Escape` 收起。選單列可開啟設定與結束 App。

這是獨立產品，不是 Apple Spotlight 的外掛。未修改系統 Spotlight，也未接管 `Command + Space`。目前以 macOS 26.6.1 驗證；尚未完成 macOS 27 真機逐像素驗收。Logo 是另行製作的放大鏡圖案，未使用 Apple 的 Spotlight 圖檔。Apple 的名稱及商標歸 Apple 所有，專案與 Apple 無關。

## 一次集中設定，之後自動連接

在設定中按 **「一次設定所有資料來源」**，會依序連接備忘錄、聯絡人、行事曆、郵件與捷徑。成功啟用的來源會記住，之後啟動會自動讀取，不需要每次逐個連接。

macOS 的 Contacts、Calendars、Automation 是不同權限；系統仍可能分別請你確認。完整磁碟存取也不能取代這些權限，App 沒有一個可略過它們的總開關。[Apple 權限說明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)

目前本機建置預設是 ad hoc 簽章，重新編譯後程式的代碼身份可能改變，系統可能重新詢問權限。正式版本應使用穩定的 Apple Development／Developer ID 簽章；可透過 `CODE_SIGN_IDENTITY` 指定已有的簽章身份。腳本不會建立憑證、改寫系統授權資料庫或關閉系統保護。

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
```

使用獨立檢查程式，能在沒有 XCTest 的 Command Line Tools 環境執行。涵蓋真實 DOCX 擷取、檔名索引、繁簡比對、算式安全、單位換算與查詢跳脫。`--benchmark` 使用本機現有檔名快取，僅印數量與比對時間，不印私人路徑或檔名。

## 搜尋範圍與更新

檔名清單在啟動時掃描，叫出面板時如距上次更新超過 30 秒會重新掃描；新檔案可手動按更新。**不是即時檔案監看器**。隱藏檔、套件內部，以及 `node_modules`、`Pods`、`DerivedData`、`venv`、`__pycache__` 的內部預設不掃描；最多 500,000 筆。無權讀取與超限會顯示狀態。

指定資料夾的文件內文只留在記憶體，結束後需重新加入；修改文件後按重新讀取。單檔 20 MB、文字總量 32 MB、最多 10,000 檔案。掃描 PDF、照片沒有 OCR；非 UTF-8 純文字可能無法讀取。

## 隱私與儲存

- 沒有伺服器、分析追蹤或自動上傳。
- 檔名及其所在路徑快取於使用者的 `Library/Caches/local.hansearch.mac/Filenames-v1.json`。它包含私人檔名，不應分享。
- 文件內文與已連接的私人資料只留在記憶體；不存進檔名快取。
- 剪貼板預設關閉。會略過隱藏／暫存標記及常見密碼管理器，但其他 App 沒標示的敏感文字仍可能被記錄。關閉即清除記錄。
- 備忘錄不會解鎖受密碼保護的筆記。來源移除會清掉記憶體副本；撤銷系統授權請到系統設定。
- `work/`、`outputs/`、建置產物和本機索引不納入 Git。

## 待完成的功能對等

- [ ] macOS 27 真機外觀、無障礙與鍵盤驗收
- [ ] 可設定的全域快捷鍵與 `Command + Space` 接管指引
- [ ] 檔案變更事件的增量索引、外接磁碟／NAS 明確狀態
- [ ] 備忘錄與全信箱的增量更新、更多資料範圍選項
- [ ] 原生行程／聯絡人深層連結與完整預覽
- [ ] 即時匯率、天氣，以及更多系統動作
- [ ] OCR、更多文件格式與可持久化的內容索引
- [ ] Developer ID 簽章、公證、可安裝發行包

Siri／Apple Intelligence 的系統私有能力不包含在目前的替代範圍中。

## 貢獻與授權

歡迎提出可重現的問題、效能數據與 Pull Request。回報請使用自製測試文件，不要附上私人備忘錄、信件、通訊錄或檔名快取。

MIT License · Copyright 2026 Enoooch0921.
