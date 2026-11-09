# C 槽還原後的恢復與驗收

適用情境：教室電腦重開機後 C 槽還原，D 槽與 `D:\Night_Trains\@George\VSCode` 保留。2026-11-09 使用者已確認 D 槽不會還原，這項儲存政策已確認。若未來換電腦或還原政策改變，需重新確認持久儲存位置；私人資料仍建議另備份至不同儲存裝置。

## 目前已修好與保存的位置

| 項目 | 已確認狀態 | C 槽還原後如何延續 |
| --- | --- | --- |
| VS Code 本體 | 安裝目錄仍名為 Portable-VSCode-1.142.0，實際版本 1.144.1 | 程式在 D 槽；使用 D 槽啟動器，不能靠 C 槽捷徑存在 |
| Git、uv、Python | 2.56.0.windows.4、0.13.7、3.14.10 | 執行檔在 D 槽 portable-tools，啟動器每次設定 PATH，不依賴 C 槽全域 PATH |
| HOME、USERPROFILE、CODEX_HOME | 指向安裝根的 data/home、data/home/.codex | 啟動器每次套用；直接開 Code.exe 或接續舊程序未必載入這些設定 |
| Codex 對話 | 既有 C 槽舊對話已合併至 D 槽；D 槽新對話保留 | C 槽還原後沿用 D 槽資料，不要重新用空資料覆蓋；確認舊對話能開啟、新對話重開後仍存在 |
| PowerShell 中文 | Console 輸入／輸出與 native pipeline 都是 UTF-8 | 初始化腳本在 D 槽；每個終端機重新套用，不依賴 C 槽 PowerShell profile |
| CMD 中文 | chcp 65001、Python UTF-8 環境變數 | 使用 D 槽專用入口；開始功能表的一般 CMD 不保證套用 |
| 腳本執行限制 | CMD 以 -NoProfile -ExecutionPolicy Bypass 啟動 PowerShell | 每次只作用於該程序，不依賴 C 槽永久執行原則或 .ps1 檔案關聯；學校強制政策仍可能阻擋 |
| 更新交易 | PowerShell 5.1 File.Replace 使用 NullString，保留備份、鎖與日誌 | 維護模板納入 repro；重新部署不必靠先前對 C 槽做過的設定 |
| 背景 Code.exe | 本體更新支援輸入 UPDATE 確認後關閉同安裝路徑的程序 | 先儲存工作；未確認不會停止程序；重跑已安裝版本會直接提示 |
| Git 姓名／Email | 可攜式設定在 data/home/.gitconfig | D 槽檔案保留；GitHub 登入憑證另行處理 |
| Node/npm/npx | 2026-11-09 已安裝 Node 24.22.2、npm/npx 11.19.1，下載摘要比對通過 | 啟動器已納入 Node PATH；下次從 D 槽啟動器重新開啟 VS Code 後繼承設定 |

日常使用的實際修復檔位於外層 `scripts` 與安裝根 `portable-tools`／`scripts`。repro 的 `config/maintenance` 保存可部署維護模板，`Install-ClassroomMaintenance.ps1` 負責重建維護入口；`Install-PortableTools.ps1` 負責重建工具、內層啟動器與 UTF-8 初始化。這些程式碼可進 Git；實際 `data`、對話、記憶及登入資料不進 Git。

## 還原後先做什麼

1. 從檔案總管開啟 D 槽的 `VSCode-Classroom-Repro`，雙擊 `Check-AfterReset.cmd`。此入口以全新、無 profile 的 PowerShell 檢查，不下載、不安裝、不關閉 VS Code，也不讀取聊天內容。
2. 若 D 槽安裝仍在，使用外層 `Launch-Portable-VSCode.cmd`。不要因 C 槽還原就再次執行對話匯入或覆蓋 data。
3. 開啟新的 PowerShell／CMD 終端機，確認中文正常；舊終端機不會自動取得新設定。
4. 開啟一段舊 Codex 對話，再建立一段新對話，關閉後重新啟動，確認兩者都能接續。
5. 視需要重新登入 GitHub、VS Code 同步、Codex 或 MCP 服務。C 槽的 Windows Credential Manager、DPAPI 狀態及 C 槽 profile 可能被還原；僅有 D 槽程式與 auth 檔不保證登入仍有效。

可明確指定位置，將不含對話內容的檢查結果留在本機 output：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ClassroomPersistence.ps1 `
  -InstallRoot 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0' `
  -ReportPath '.\output\persistence-check.json'
```

檢查分為 PASS、WARN、FAIL、MANUAL。FAIL 會回傳非零退出碼；WARN 與 MANUAL 表示待補功能或仍需操作驗收。這不是實際還原 C 槽的模擬；D 槽保留政策依使用者確認記錄，並非由檢查腳本推定。

## 修復檔遺失時

如果 D 槽工具與 data 都保留，只是外層更新／終端機入口遺失，先預覽維護部署；不是整套重新安裝：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-ClassroomMaintenance.ps1 `
  -InstallRoot 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0'
```

確認預覽後加 `-Apply`。現有檔案不同時預設停止；明確要套用修正時再加 `-ReplaceExisting`，腳本會先備份。這個步驟不下載 runtime、不替換 Code.exe、不複製對話，也不匯入登入憑證。

如果整套 D 槽環境遺失，依 README 的 Bootstrap 流程在空目標重建，再從私人備份恢復資料。只有 GitHub 上的 repro 無法找回私人對話；請在所有 Codex／VS Code 程序退出後備份整個 `data/home/.codex` 到另一個持久儲存。複製 SQLite 活躍資料庫可能遺漏 WAL，雙端都有資料時不可直接覆蓋。

## 下載來源與持久快取

VS Code 官方固定版來源：`https://update.code.visualstudio.com/1.144.1/win32-x64-archive/stable`。本次下載原在 `C:\Users\N22\Downloads\VSCode-win32-x64-1.144.1.zip`，已另存於：

`D:\Night_Trains\@George\VSCode\installers\classroom-repro\vscode\VSCode-1.144.1-win32-x64.zip`

已比對 manifest 的 363999477 bytes 與 SHA-256 `d701cf4dd78875f90fe6f14ad8e11ebb8052b36978dc9926aef1b3a4d46485fe`。Bootstrap 可重用此快取；檔案不進 Git。其他工具與 VSIX 的快取是否完整仍需分別確認，不能因 VS Code ZIP 已保存就宣稱可全離線重建。

下次要從 C 槽保留同一固定版 ZIP，可先預覽，再加 `-Apply`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Save-ClassroomDownload.ps1 `
  -SourceArchive 'C:\Users\N22\Downloads\VSCode-win32-x64-1.144.1.zip' `
  -CacheRoot 'D:\Night_Trains\@George\VSCode\installers\classroom-repro' -Apply
```

## 本次驗證的界線

2026-11-09：使用者確認已重開，Codex 對話保存且可接續。這是對話重開留存的實際驗收；是否由教室還原機制真正還原 C 槽仍未獨立確認。檢查腳本可加 `-ConversationRestartConfirmed` 記錄此使用者驗收，其他人工還原檢查仍保留。

同日 Node 已補齊，現有持久性檢查更新為 0 FAIL、0 WARN。隔離空白重建最終通過本體、工具及全部 37 個清單版本的擴充功能驗證；過程修正 CLI 呼叫，並使用保存的 VSIX 解決已無法由 Marketplace 取得的 Roo Code 舊版。37 個固定版本的 VSIX 已保存於 D 槽快取，但尚未因此宣稱完全離線可重建，詳見 [驗收報告](../output/Rebuild-Acceptance-2026-11-09.md)。

2026-11-04 的現有環境檢查：0 個 FAIL、1 個 WARN（尚缺 Node）；UTF-8 的 Console 輸入／輸出／pipeline 都是 65001。實際安裝的版本、D 槽設定與對話目錄、Git 設定檔及 VS Code ZIP 快取均確認存在。此結果沒有實際還原 C 槽，也未執行空白環境的完整安裝。

首次匯入腳本 `Enable-PortableCodex.ps1` 目前仍未自動修正 SQLite 的 rollout_path；雙邊對話合併也未自動化。這些限制不表示目前 D 槽的既有合併失敗，而是 repro 的自動重建能力尚未涵蓋所有私人資料恢復情況。
