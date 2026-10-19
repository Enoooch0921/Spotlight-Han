# Spotlight Han

<img src="Assets/SpotlightHan.png" alt="Spotlight Han app icon" width="112" />

**用你習慣的中文，找到 Mac 裡的 App、影片和文件。**

繁體、簡體混在一起，也能一起搜。檔名與影片搜尋使用自己的本機索引，讓你清楚知道哪些資料夾已納入搜尋。

An open-source macOS Spotlight alternative with Traditional/Simplified Chinese search and independent local filename indexing.

[![macOS checks](https://github.com/Enoooch0921/Spotlight-Han/actions/workflows/ci.yml/badge.svg)](https://github.com/Enoooch0921/Spotlight-Han/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[開發預覽與下載](https://github.com/Enoooch0921/Spotlight-Han/releases) · [開始使用](#開始使用) · [完整說明](docs/guide.zh-Hant.md) · [回報問題](https://github.com/Enoooch0921/Spotlight-Han/issues)

## 明明就在電腦裡，為什麼搜不到？

App 叫「红果短剧」，你輸入「紅果短劇」。Word 裡寫的是「教会活动」，你記得的是「教會活動」。要播影片時，知道檔名，搜尋結果卻遲遲找不到它。

遇到這些情況，我們常常得換一種字形、再試一次，甚至打開資料夾一層一層找。

**Spotlight Han 從這些日常搜尋失敗開始：讓繁簡互搜、搜尋範圍與檔案分類變得更直接。**

| 你遇到的情況 | 在 Han 裡怎麼找 |
| --- | --- |
| App 使用簡體名稱，平常習慣打繁體 | 輸入 `紅果短劇`，比對名稱為 `红果短剧` 的 App。 |
| 資料夾裡的檔名繁簡混用 | `教會活動`、`教会活动` 都能比對對應字形的檔名，原檔名保持原樣。 |
| Word 用簡體寫，記得的關鍵字是繁體 | 加入文件資料夾後，在「文件內容」搜尋 `教會活動`，比對內文中的 `教会活动`。 |
| 急著找影片，結果混著其他檔案 | 切到「影片」，在已選資料夾的本機檔名清單中搜尋。 |

以上是繁簡字形比對範例。不同用詞、同義詞與錯字容忍尚未涵蓋，例如「影片／視頻」不會自動視為同一個詞。

## 為什麼試試 Spotlight Han？

- **少猜一次字形。** App、檔名與支援的文件內容採用繁簡比對，保留原始名稱與文字。
- **找檔案有自己的索引。** 檔名與影片搜尋獨立建立本機清單；選擇搜尋範圍後，不依賴 Spotlight 的檔名索引。
- **搜尋範圍看得見。** 自己選擇資料夾、查看索引狀態，也能手動更新清單。
- **本機搜尋、開源可檢閱。** 搜尋資料在本機處理；沒有自建搜尋伺服器、分析追蹤或自動上傳查詢。

這些特色最適合繁簡資料混用，或經常在 Mac 上找影片、教材、工作文件的人。

## 同一個搜尋框，也能處理日常小事

| 想做什麼 | 試著輸入 |
| --- | --- |
| 計算 | `(1200+300)*0.9` |
| 單位換算 | `5 km to m` |
| 台幣換人民幣 | `3000tb rmb` |
| 同時看多個幣別 | `3000tb`，預設顯示 CNY、USD、JPY，可在設定更改。 |
| 新增系統提醒事項 | `提醒我明天上午9點交報告`，預覽後按 Return。 |
| 設定 Apple 時鐘鬧鐘 | `設定30分鐘後的鬧鐘`，首次需加入內附捷徑。 |

也支援經授權搜尋備忘錄、聯絡人、行事曆、提醒事項與 Mail，以及選擇啟用的剪貼板記錄。非中文查詢可在搜尋結果上方顯示本機繁體中文翻譯。

匯率使用免費每日參考資料，畫面標示時間與來源；本機翻譯需 macOS 15 以上並先準備 Apple 語言模型。私人資料來源與建立指令需個別設定及系統授權。詳見[完整功能與限制](docs/guide.zh-Hant.md#功能)。

## 開始使用

**目前為 0.5.3 開發預覽。** 已在 Apple Silicon、macOS 26.6.1 驗證；目標最低執行版本為 macOS 14，較舊版本與 Intel Mac 尚待驗證。

**[公開預覽與下載狀態請見 Releases](https://github.com/Enoooch0921/Spotlight-Han/releases)**。若尚無公開版本，可先使用下方原始碼建置方式。Apple Silicon 預覽包檔名為 `Spotlight-Han-0.5.3-macOS-arm64.zip`，採用 ad hoc 簽章，尚未完成 Developer ID 簽章與 Apple 公證，從網路下載後可能被 macOS 阻擋開啟。一般使用者可等候完成簽章與公證的版本；詳見[安裝說明](docs/install.zh-Hant.md)。

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

想改用 **⌘Space**：在 Han 設定按「開啟 Spotlight 快捷鍵開關」，自行關閉原生 Spotlight 的組合鍵，再回 Han 按「使用 ⌘Space」。

## 試用前，先了解這幾件事

- **目前仍是開發預覽。** 目標是成為 Spotlight 的開源替代品，現階段尚未達到完整功能對等。
- **檔名清單需要首次掃描。** 已選範圍在啟動及叫出面板時按間隔更新，也可手動更新；目前尚非即時檔案監看。
- **全文搜尋有指定範圍。** 加入資料夾後可直接讀取支援的 Word、文字 PDF 與純文字；未加入資料夾的文件內容搜尋仍使用 Spotlight。掃描圖片與掃描 PDF 尚不支援 OCR。
- **授權由 macOS 管理。** 已選資料夾會保存存取書籤；系統撤銷權限或開發版重新簽章後，仍可能需要再次授權。

[使用、權限與隱私說明](docs/guide.zh-Hant.md) · [開發檢查](docs/guide.zh-Hant.md#建置) · [待完成項目](docs/guide.zh-Hant.md#待完成的功能對等)

## 一起讓中文搜尋更好用

如果你也遇過「明明有檔案，換個字形卻找不到」，歡迎[分享可重現的例子](https://github.com/Enoooch0921/Spotlight-Han/issues)。你的回饋能幫助我們找出真正需要改善的搜尋情境。

回報時附上 macOS／Han 版本、輸入的關鍵字、預期結果與實際結果即可。請用自製測試檔案，避免公開私人文件、備忘錄或檔名快取。也歡迎提交 Pull Request，或給專案一顆 Star 方便追蹤進度。

MIT License · Copyright 2026 Enoooch0921.

Spotlight Han 是獨立開源專案，與 Apple 無關；Apple 與 Spotlight 的名稱及商標屬於各自權利人。
