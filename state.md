# 重建狀態

## 目前狀態

- 狀態：初版 repro 專案已建立；尚未在空白目標目錄實際下載或安裝。
- 快照日期：2026-11-04。
- 來源環境：`D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0`。
- VS Code：1.144.1，commit `261c84cb1eddf11235f9e2c921425e9663fbe556`，Windows x64 stable。
- Portable Git：`2.56.0.windows.4`。
- uv：`0.13.7`。
- Node.js：`24.22.2` LTS，納入 repro 以提供同步 MCP 設定所需的 `node`/`npm`/`npx`；原安裝沒有 Node/npm/npx。Windows x64 ZIP SHA-256 固定於 `manifests/versions.json`，來源為官方 release checksum 清單。
- Python：`3.14.10`。
- 擴充功能：37 個，逐項固定 ID、版本和可用平台，詳見 `manifests/extensions.json`。
- Agent 自訂內容：目前觀察到兩組 VS Code 帳號同步的 Copilot CLI 自訂內容；它們不是本機獨立安裝包，需登入並重新同步。MCP 設定參考已另存於 `config/agent-plugins/`。

## 重建策略

1. 將腳本、版本清單、擴充功能清單及通用設定放在本專案版本控制；不提交已安裝 runtime 或快取。
2. 用 Microsoft 官方固定版本端點下載 VS Code，驗證 `Code.exe` 簽章及產品版本。
3. 透過固定 release tag 取得 Git 和 uv，驗證資產大小、GitHub digest（若提供）及程式版本；用固定 SHA-256 驗證 Node 官方 ZIP；由 uv 安裝固定的 Python patch 版本。
4. 透過 VS Code CLI 還原 Marketplace 指定版本，並支援本機 VSIX 快取做離線安裝。
5. 使用可攜式 `data` 目錄和 wrapper；`CODEX_HOME` 指向 `data/home/.codex`。帳號登入、Codex 記憶及 agent sync 資料保留為使用者狀態，不混入 source repo。
6. Fusion 360 保持獨立安裝流程；只有明確指定時才由 bootstrap 呼叫 Autodesk installer。

## 還未被證明的前提與限制

- C 槽重製後能否快速恢復，取決於 D 槽和 `D:\Night_Trains\@George\VSCode` 是否仍保留。尚未確認教室的 D 槽重製政策。
- Marketplace 可能下架舊版擴充功能；如無法下載，需預先保存同版本 VSIX 到可持續保留的快取。
- 擴充功能版本已鎖定，但部分擴充功能啟動時可能另行下載語言伺服器、runtime 或 CLI；這些延伸依賴尚未個別鎖版。
- VS Code ZIP 固定大小與 SHA-256 已寫入 manifest，下載時比對；解壓後仍驗證 Code.exe Microsoft 簽章及產品版本。
- GitHub release API 若沒有提供 asset digest，初次下載採 HTTPS、檔案大小與解壓版本驗證，並建立本機 SHA-256 sidecar。若要跨機器保證完全相同的 artifact，應將正式核准的摘要寫入版本清單。
- Agent plugin 自訂內容的 nonce 資料夾由 VS Code 帳號同步生成，無法由固定路徑直接複製重建。
- `microsoft/playwright-mcp` 的目前同步設定指定 `@latest`，其 MCP 套件版本尚未鎖定；需捕捉明確版本後才能完全重現此伺服器。
- 個人雲端 project ID、MCP/API 憑證、登入狀態、Codex 記憶和工作階段都刻意排除；這些需在目標環境重新登入或個別設定。
- Fusion Installer 會取得 Autodesk 當時提供的 Downloader；它重建安裝流程，不鎖定 Fusion 的固定 build。

## 現場觀察

- 2026-11-04（已完成）：檢視本機啟動器發現缺少 `CODEX_HOME`，已修正啟動器；專案遷移腳本僅支援初次匯入，不處理雙邊合併。
- 新增 `scripts/Enable-PortableCodex.ps1`：支援預覽、單獨修正舊啟動器與關閉程序後的初次資料遷移；來源保留、拒絕目標已有對話資料、逐檔摘要驗證。不將個人資料寫入 repro。
- 已在本機啟動器加入與 bootstrap 範本相同的 `CODEX_HOME`；未將任何對話或個人資料匯入本專案。
- 驗證：本次所有 PowerShell AST、JSON 及 manifest/profile assertions 通過；未執行 bootstrap 下載或安裝。
- 下一步：雙邊對話需按 README 所述人工安全合併與隔離驗證；首次遷移亦需另行修正並驗證 SQLite `rollout_path`；完整空白環境 bootstrap 尚未實跑。

- 原始可攜式安裝約 9.69 GiB；主要容量在擴充功能和 `CachedExtensionVSIXs`。本專案不複製這些安裝快取。
- `portable-tools/.download-stage` 曾有一筆約 6.4 MiB 的 PortableGit `.partial` 及另一個歷史下載檔；當時沒有發現 `.update-backups` 或 `versions.json`。這些留在原始安裝目錄，與本 repro 專案分開。
- Fusion installer repo 在檢查時為乾淨狀態；ZIP SHA-256 與 `output/SHA256SUMS.txt` 相符，PowerShell parser 檢查通過。未執行 Autodesk 安裝器。


## 2026-11-04 更新

- 同步已驗證版本：VS Code 1.144.1（commit 261c84cb1eddf11235f9e2c921425e9663fbe556）、Portable Git 2.56.0.windows.4、uv 0.13.7、Python 3.14.10；保留 Node.js 24.22.2 與其官方 checksum。安裝目錄仍沿用 Portable-VSCode-1.142.0 名稱。
- 固定 VS Code ZIP 大小 363999477 bytes 與 SHA-256 d701cf4dd78875f90fe6f14ad8e11ebb8052b36978dc9926aef1b3a4d46485fe。
- 增加可攜式 PowerShell UTF-8 終端機 profile，設定只作用於該 VS Code。
- 文件說明下載快取持久化選項及 Codex 雙端對話需安全合併；目前遷移腳本只做初次匯入。
- 未下載或執行安裝。

## C 槽還原情境補強

- 這次不再只連到外層維護檔：將實際已修好的維護實作整理為 repro 模板，附明確預覽／套用的維護部署入口。保留私人 data 與對話於 D 槽，不存進 Git。
- 新增 `docs/C-Drive-Restore.md`：逐項記錄本體更新、PowerShell 5.1、UTF-8、CODEX_HOME、工具 PATH、Git 設定、程序關閉和備份交易修正如何延續，以及哪些仍依賴重新登入或人工驗收。
- 新增 `Check-AfterReset.cmd` 與 `Test-ClassroomPersistence.ps1`；以無 profile、單次 Bypass 的 PowerShell 檢查 D 槽安裝與中文編碼，不依賴 C 槽永久設定。
- C 槽 VS Code 下載 ZIP 已使用 `Save-ClassroomDownload.ps1` 複製至 D 槽 `installers/classroom-repro/vscode`，固定大小與 SHA-256 檢查通過。未重新下載或安裝。
- 實際現有環境檢查：0 FAIL、1 WARN（目前安裝缺少 Node）；UTF-8 輸入／輸出／pipeline 都是 65001。私人對話只檢查目錄與檔案數，不讀取或匯入內容；本機報告不進 Git。
- 下一步：教室真的還原 C 槽後重跑檢查，再確認舊／新對話可開啟並完成必要登入。D 槽保留政策仍待教室管理者確認；完整空白安裝、全離線快取和 SQLite 私人資料恢復仍未全部驗證。
- 重建下載統一使用 PowerShell `-UseBasicParsing`，GitHub release 查詢有逾時限制，避免依賴 C 槽還原前的瀏覽器初始化狀態。
- 補正工具重建腳本對唯讀 `$HOME` 的同名變數寫入，改用 `$portableHome`，避免語法檢查通過但首次執行在建立啟動器時失敗。
- 維護模板合成測試通過：預覽不寫入、10 檔部署、重複套用、衝突拒絕、替換前備份驗證及不安全資料夾名稱拒絕；工具更新重建的啟動器保留 Node/uv PATH 和 VSCODE_PORTABLE_ROOT。

## Project agent instructions

- Rewrote `AGENTS.md` in English and integrated applicable workspace rules for persistent storage, reproducible repairs, safe updates, private conversation recovery, verification, and handoff.
- Kept versions, installation paths, and detailed recovery steps in their existing manifests and documentation; the instructions reference those sources rather than duplicate current values.
- Preserved the original safeguards for official downloads, pinned extensions, user data, explicit Fusion installation, and checks without running installers. No installation or private data was changed.
