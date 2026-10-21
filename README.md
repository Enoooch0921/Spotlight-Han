# Spotlight Han

繁體中文 · [English](README.en.md)

<img src="Assets/SpotlightHan.png" alt="Spotlight Han app icon" width="112" />

**用你習慣的中文，找到 Mac 裡的 App、影片和文件。**

繁體、簡體混在一起，也能一起搜。檔名與影片搜尋使用自己的本機索引，讓你清楚知道哪些資料夾已納入搜尋。

An open-source macOS Spotlight alternative with Traditional/Simplified Chinese search and independent local filename indexing.

[![macOS checks](https://github.com/Enoooch0921/Spotlight-Han/actions/workflows/ci.yml/badge.svg)](https://github.com/Enoooch0921/Spotlight-Han/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[下載 Apple Silicon DMG](https://github.com/Enoooch0921/Spotlight-Han/releases/download/v1.0.0/Spotlight-Han-1.0.0-macOS-arm64.dmg) · [版本與下載](https://github.com/Enoooch0921/Spotlight-Han/releases) · [開始使用](#開始使用) · [完整說明](docs/guide.zh-Hant.md) · [回報問題](https://github.com/Enoooch0921/Spotlight-Han/issues)

## 明明就在電腦裡，為什麼搜不到？

檔案叫「会议记录.docx」，你輸入「會議記錄」。Word 裡寫的是「台北出差」，你想直接找到提到它的那一段。要播影片時，知道檔名，搜尋結果卻遲遲找不到它。

遇到這些情況，我們常常得換一種字形、再試一次，甚至打開資料夾一層一層找。

**Spotlight Han 從這些日常搜尋失敗開始：讓繁簡互搜、搜尋範圍與檔案分類變得更直接。**

| 你遇到的情況 | 在 Han 裡怎麼找 |
| --- | --- |
| 檔案使用簡體名稱，平常習慣打繁體 | 輸入 `會議記錄`，比對名稱為 `会议记录.docx` 的文件。 |
| 資料夾裡的檔名繁簡混用 | `教會活動`、`教会活动` 都能比對對應字形的檔名，原檔名保持原樣。 |
| Word 用簡體寫，記得的關鍵字是繁體 | 在「全部」搜尋 `教會活動`，比對已索引文件內文中的 `教会活动`；也可加入資料夾補強直接擷取。 |
| 急著找影片，結果混著其他檔案 | 切到「影片」，在已選資料夾的本機檔名清單中搜尋。 |

以上是繁簡字形比對範例。不同用詞、同義詞與錯字容忍尚未涵蓋，例如「影片／視頻」不會自動視為同一個詞。

## 為什麼試試 Spotlight Han？

- **少猜一次字形。** App、檔名與支援的文件內容採用繁簡比對，保留原始名稱與文字。
- **找檔案有自己的索引。** 檔名與影片搜尋獨立建立本機清單；選擇搜尋範圍後，不依賴 Spotlight 的檔名索引。
- **命中的字看得見。** 標題及內容摘要凸顯繁簡命中的字，長文摘要會定位到關鍵字附近。
- **搜尋範圍看得見。** 自己選擇資料夾、查看索引狀態，也能手動更新清單。
- **本機搜尋、開源可檢閱。** 搜尋資料在本機處理；沒有自建搜尋伺服器、分析追蹤或自動上傳查詢。

這些特色最適合繁簡資料混用，或經常在 Mac 上找影片、教材、工作文件的人。

## 同一個搜尋框，也能處理日常小事

| 想做什麼 | 試著輸入 |
| --- | --- |
| 計算 | `(1200+300)*0.9` |
| 單位換算 | `5 km to m` |
| 開啟系統設定子頁 | `隱私安全性`、`wifi`、`蓝牙` 或 `Bluetooth`。 |
| 直接用國名換算 | `3000NT=馬來西亞`、`3000nt 马来`、`3000NT=Malaysia`。 |
| 台幣換人民幣 | `3000tb rmb` |
| 同時看多個幣別 | `3000tb`，預設顯示 CNY、USD、JPY，可在設定更改。 |
| 新增系統行事曆 | `cal`＋Tab → `明天下午3點到4點開會` → Return 預覽 → 確認建立。 |
| 新增系統提醒事項 | `提醒`＋Tab → `30分鐘後喝水` → Return 預覽 → 確認建立。 |
| 設定 Apple 時鐘鬧鐘 | `設定30分鐘後的鬧鐘`，首次需加入內附捷徑。 |

行程預覽可調整標題、日期、開始／結束時間、全天與提前通知。在 Han 設定選擇預設行事曆（例如「大拇指」），每次確認預覽仍能改到其他可寫入的行事曆（例如「大腳趾」），只影響當次新增。

自然語言日期使用內附 [Chrono](https://github.com/wanasit/chrono) 加上 Han 的中文補強，透過 JavaScriptCore 在本機處理；使用 App 不需 Node.js、API Key 或下載模型。公開1.0.0支援單次事項；本機1.0.1-dev另加入每天／每週／每月重複、民國日期、台灣單位換算與Apple Vision圖片／掃描PDF的背景OCR，尚未發布，詳見[本機測試版說明](docs/guide.zh-Hant.md#本機測試版-101-dev尚未發布)。未支援或無法完整辨識的規則會提示調整。

行事曆搜尋預設依時間排序：進行中／即將到來的行程在前，過去行程由近到遠，也能切換日期新到舊或舊到新。已授權來源會背景更新：行事曆／提醒事項每 5 分鐘及系統變更後重讀，其他來源與文件索引每 15 分鐘更新。來源狀態會標示上次完整更新、失敗、部分資料與舊副本；權限失效時暫停並提示，不在背景要求授權。

也支援經授權搜尋備忘錄、聯絡人、行事曆、提醒事項與 Mail，以及選擇啟用的剪貼板記錄。可在搜尋結果下方顯示 Apple 本機翻譯，來源及目標語言可自訂。

匯率使用免費每日參考資料，畫面標示時間與來源；本機翻譯需 macOS 15 以上並先準備 Apple 語言模型。私人資料來源與建立指令需個別設定及系統授權。詳見[完整功能與限制](docs/guide.zh-Hant.md#功能)。

### 不想打字時，也能直接找 App

按 **⌘1** 或右側 App 圖示，直接看圖示／列表。預設列出全部、按名稱排列；左側直接選分類，也能新增自己的分類，把 App 拖過去整理。所有分類可以拖動排序，自訂分類可換圖示、重新命名或刪除；右鍵也能釘選或改分類。也提供 Waves、iZotope、影音製作與 Office 等建議分類。Han 會在本機記住安排，不會搬動系統裡的 App。

有新版時，Han 會在面板與選單列提示；可直接下載 DMG。設定中可關閉每日檢查或選擇是否接收測試版。

中文名稱可用完整拼音與注音；App 另支援首字母：拼音首字母 `jsj`／注音首符號 `ㄐㄙㄐ` 找計算機，`zdj` 找終端機；檔名和個人資料標題不自動套用首字母，結果右鍵仍可自訂搜尋縮寫。

搜尋 `logicpro` 也能找到 **Logic Pro**，`fcp`／`fcpx` 可找到 **Final Cut Pro**；另內建 `ps`、`ai`、`ae`、`pr`、`vscode`、`ppt` 等常見縮寫。新增本機搜尋習慣：重複開啟的同詞結果優先，App、備忘錄與檔案共同排序；設定可關閉或清除，原始搜尋文字與內容不保存、不上傳。

「全部」直接搜尋 Han 自建的 **Word／PDF／PowerPoint／Excel 全文索引**。先選擇文件資料夾，索引保存在本機、重啟可沿用，背景只重新擷取有變動的文件。可顯示命中摘要與逐檔失敗原因。Spotlight 全機文件結果改為可選補充，預設關閉。

檔案搜尋結果會顯示檔案系統的建立日期與時間；無法讀取時明確標示。日期在背景按需讀取；可切換相關度、建立日期新到舊／舊到新，並記住排序偏好。

## 開始使用

首次開啟提供可略過、可重新查看的 App 內引導。v1.0.0 提供六步引導，並可切換 App 拼音與注音範例，涵蓋操作範例、快捷鍵與接續、檔案及全文範圍、個人資料來源、日常工具及真實設定摘要。

**目前為 v1.0.0 正式版。** 已在 Apple Silicon、macOS 26.6.1 驗證；目標最低執行版本為 macOS 14，較舊版本與 Intel Mac 尚待驗證。

**[正式版本與下載請見 Releases](https://github.com/Enoooch0921/Spotlight-Han/releases)**。Apple Silicon 提供 `Spotlight-Han-1.0.0-macOS-arm64.dmg` 拖曳安裝與 ZIP 壓縮包，採用 ad hoc 簽章，尚未完成 Developer ID 簽章與 Apple 公證，從網路下載後可能被 macOS 阻擋開啟。一般使用者可等候完成簽章與公證的版本；詳見[安裝說明](docs/install.zh-Hant.md)。

若要自行從原始碼建置，需要包含 macOS 26 SDK 的 Xcode／Command Line Tools，以及 Swift 5.9 以上：

```sh
git clone https://github.com/Enoooch0921/Spotlight-Han.git
cd Spotlight-Han
./script/build_and_run.sh
```

1. 腳本會建置並開啟 `outputs/Spotlight Han.app`。
2. 用 `Control + Option + Space` 叫出／收起 Han；在設定可錄製自己的快捷鍵。
3. 按「選擇搜尋資料夾…」，加入下載、影片、文件等實際想搜尋的位置，等待首次掃描完成。
4. 輸入關鍵字；用 `↑ / ↓` 選擇、`Return` 開啟、`Escape` 收起。

介面語言可選跟隨系統、繁體中文、简体中文或 English；翻譯另外設定來源及目標語言。一般設定提供登入時自動啟動；搜尋／索引會顯示目前處理狀態。

想改用 **⌘Space**：在 Han 設定按「開啟 Spotlight 快捷鍵開關」，自行關閉原生 Spotlight 的組合鍵，再回 Han 按「使用 ⌘Space」。Han 會檢查系統快捷鍵衝突；無法註冊時保留原本的組合。其他 App 的衝突仍以系統是否允許註冊為準。

## 使用前，先了解這幾件事

- **目前功能仍有範圍。** 這是獨立的開源啟動器，現階段尚未達到 Spotlight 完整功能對等。
- **檔名清單需要首次掃描。** 已選範圍在啟動及叫出面板時按間隔更新，也可手動更新；目前尚非即時檔案監看。
- **全文搜尋有指定範圍。** 加入資料夾後可直接讀取支援的 Word、文字 PDF、PPTX、XLSX 與純文字；未加入資料夾的文件不在 Han 索引範圍；可另外開啟 Spotlight 補充。公開1.0.0尚不支援掃描圖片／PDF的OCR；本機1.0.1-dev已加入Apple Vision背景OCR、命中片段與頁碼，預設接電時逐頁辨識，使用中降速、閒置加快，低耗電或升溫先等待，尚未發布。
- **授權由 macOS 管理。** 已選資料夾會保存存取書籤；系統撤銷權限或開發版重新簽章後，仍可能需要再次授權。

[使用、權限與隱私說明](docs/guide.zh-Hant.md) · [開發檢查](docs/guide.zh-Hant.md#建置) · [待完成項目](docs/guide.zh-Hant.md#待完成的功能對等)

## 一起讓中文搜尋更好用

如果你也遇過「明明有檔案，換個字形卻找不到」，歡迎[分享可重現的例子](https://github.com/Enoooch0921/Spotlight-Han/issues)。你的回饋能幫助我們找出真正需要改善的搜尋情境。

回報時附上 macOS／Han 版本、輸入的關鍵字、預期結果與實際結果即可。請用自製測試檔案，避免公開私人文件、備忘錄或檔名快取。也歡迎提交 Pull Request，或給專案一顆 Star 方便追蹤進度。

[第三方授權與日期解析建置](THIRD_PARTY_NOTICES.md) · [解析器重建方式](tools/date-parser/README.md)

MIT License · Copyright 2026 Enoooch0921.

Spotlight Han 是獨立開源專案，與 Apple 無關；Apple 與 Spotlight 的名稱及商標屬於各自權利人。
