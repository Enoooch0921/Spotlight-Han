# Spotlight Han · 開發預覽版安裝說明

目前打包版本為 **0.5.3 開發預覽**，供願意協助回報問題的使用者試用。公開狀態以 Releases 列表為準；它尚未達到 Spotlight 的完整功能對等。

## 下載哪個檔案？

到 [GitHub Releases](https://github.com/Enoooch0921/Spotlight-Han/releases)，在公開的 v0.5.3 版本下載 `Spotlight-Han-0.5.3-macOS-arm64.zip`。若列表還沒有這個版本，代表尚未公開。

- `arm64` 適用於 Apple Silicon（M 系列）Mac。目前未提供 Intel 版或 Universal 版安裝包。
- 目前已驗證 Apple Silicon、macOS 26.6.1。程式宣告最低 macOS 14，macOS 14／15 尚待真機驗證。
- GitHub 自動提供的 `Source code` 是原始碼，不是可直接開啟的 App。
- `SHA256SUMS.txt` 可供核對下載檔案完整性；它不是 Apple 簽章或公證。

## 重要：目前的簽章狀態

這個開發預覽包採用 **ad hoc 簽章**，尚無 Developer ID 簽章及 Apple 公證。從網路下載後，macOS Gatekeeper 可能阻擋開啟；本機開發環境能執行不代表其他 Mac 能直接安裝。

若被系統阻擋，請保留系統安全保護，等候後續完成 Developer ID 簽章與公證的版本。此預覽不適合作為所有一般使用者都能順利安裝的正式發行版。

具備開發環境的使用者也可依[專案首頁](https://github.com/Enoooch0921/Spotlight-Han#開始使用)自行從原始碼建置。這個選項仍需 Xcode／Command Line Tools，不能取代正式簽章發行流程。

## 首次使用

1. 解壓縮 ZIP，將 `Spotlight Han.app` 放到「應用程式」。
2. 系統允許開啟後，以 `Control + Option + Space` 叫出或收起搜尋。
3. 按「選擇搜尋資料夾…」，加入實際想搜尋的位置，等待首次掃描完成。
4. 輸入繁體或簡體關鍵字。`↑ / ↓` 選擇，`Return` 開啟，`Escape` 收起。
5. 若想改用 `⌘Space`，到 Han 設定開啟系統 Spotlight 快捷鍵頁，自行關閉原生組合鍵，再回 Han 選擇「使用 ⌘Space」。

備忘錄、聯絡人、行事曆、提醒事項、Mail 與捷徑需在設定連接並依系統提示授權。資料夾會保存存取書籤；系統撤銷權限或開發版簽章變動後，可能需要重新授權。

所有來源會排隊連接，避免同時出現多個授權請求。備忘錄會顯示讀取數量，可先搜尋已載入內容；若等待太久，可按「停止連接」。系統授權視窗仍需由你自行選擇或關閉。啟動時不會主動重新要求已失效的權限。

Apple 時鐘鬧鐘需要一次加入內附的 `Spotlight-Han-System-Clock` 捷徑。翻譯需 macOS 15 以上並準備 Apple 語言模型。匯率為免費每日參考資料，並非即時行情。

## 更新與回報

更新時先從 Han 選單結束 App，再以新版本取代舊 App。預覽版目前沒有自動更新機制。

歡迎到 [Issues](https://github.com/Enoooch0921/Spotlight-Han/issues)回報 macOS／Han 版本、搜尋關鍵字、預期與實際結果。請以自製測試資料重現，避免公開私人檔案、備忘錄或檔名快取。

[完整使用與隱私說明](https://github.com/Enoooch0921/Spotlight-Han/blob/main/docs/guide.zh-Hant.md) · [MIT License](https://github.com/Enoooch0921/Spotlight-Han/blob/main/LICENSE)
