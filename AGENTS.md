# 專案指引

- 本專案保存可重建 VS Code 課堂環境所需的腳本、清單與文件，不納入已安裝的 VS Code、擴充功能執行檔、使用者快取或登入資料。
- 下載來源必須使用清單指定的官方端點或 GitHub 專案 release API；驗證版本、檔案大小、可取得的 SHA-256 摘要及 Microsoft Authenticode 簽章。
- 安裝腳本預設只建立缺少的元件。若目標已有不同版本，停止並說明，不可靜默覆蓋或刪除使用者資料。
- 擴充功能版本以 `manifests/extensions.json` 為準；離線 VSIX 快取放在可設定的下載快取，不提交到 Git。
- 不將登入憑證、個人記憶、VS Code 工作階段、機器識別碼或個人雲端專案 ID 寫入此專案。
- 只有使用者明確指定時，才從 bootstrap 呼叫 Fusion 安裝器；不得自行執行安裝器。
- 修改 bootstrap 或版本清單後，先做 PowerShell 語法和 JSON 格式檢查，不執行下載或安裝來代替使用者操作。
