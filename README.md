# VS Code 課堂環境 repro

本專案提供可版本控制的重建入口，用來在教室電腦重製後恢復 VS Code 課堂環境。已確認更新流程使用 Microsoft 官方更新端點 `https://update.code.visualstudio.com/{version}/win32-x64-archive/stable`；版本與 ZIP SHA-256/大小鎖定在 `manifests/versions.json`。本機曾用的 `C:\Users\N22\Downloads\VSCode-win32-x64-1.144.1.zip` 僅是下載位置範例，不是持久快取。正式快取應放 D 槽 `D:\Night_Trains\@George\VSCode\installers\classroom-repro`；需要跨重製保存時，將專案與快取放到 USB 或網路磁碟。安裝資料夾沿用 `Portable-VSCode-1.142.0` 名稱，但其內容版本為 1.144.1。

## 快速重建

若教室只還原 C 槽、D 槽環境仍保留，請先讀 [C 槽還原後的恢復與驗收](docs/C-Drive-Restore.md)，執行根目錄 `Check-AfterReset.cmd`，再使用 D 槽啟動器。這份文件記錄實際已修好的項目、維護模板的重套方式、持久下載快取，以及登入／私人對話的恢復限制。

2026-11-09 已完成實際隔離空白重建及 37 個擴充版本驗證，詳見 [驗收報告](output/Rebuild-Acceptance-2026-11-09.md)。完整離線仍有限制，請使用 [離線快取盤點](docs/Offline-Cache.md) 分別確認檔案完整性、來源信任與網路需求。

### 新電腦第一次重建

先把整個 `VSCode-Classroom-Repro` 專案資料夾複製或 clone 到重製後仍會保留的位置，例如 D 槽或 USB。若學校的 D 槽也會清除，請把專案與下載快取放到 USB 或網路磁碟。確認新電腦可連線到 Microsoft、GitHub 和 VS Code Marketplace，並預留下載與安裝空間。

在 Windows PowerShell 中進入 `VSCode-Classroom-Repro` 資料夾，執行以下命令：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Bootstrap-Classroom.ps1 `
  -InstallRoot 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0' `
  -CacheRoot 'D:\Night_Trains\@George\VSCode\installers\classroom-repro'
```

如果新電腦使用不同磁碟或資料夾，請把兩個參數改成新位置。若不指定參數，腳本會依本專案所在位置推算 VS Code 安裝與下載快取路徑：

```powershell
.\scripts\Bootstrap-Classroom.ps1
```

完成後啟動 VS Code：

```powershell
& 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0\Launch-VSCode.cmd'
```

首次啟動時登入 VS Code 帳號以同步 agent 自訂內容，並依提示重新授權 MCP 服務。登入憑證和 Codex 記憶不會由本專案還原。

Bootstrap 會依序：

1. 從 Microsoft 官方更新端點下載清單指定版本的 VS Code ZIP；解壓後驗證 `Code.exe` 的 Microsoft Authenticode 簽章與 `product.json` 版本。
2. 從清單指定的 GitHub release 取得 PortableGit 與 uv；檢查 release 資產大小、可用的 SHA-256 摘要及工具版本。接著從 Node.js 官方站下載固定版本，並比對版本清單中取自官方 `SHASUMS256.txt` 的固定摘要，再安裝清單指定的 Python 版本。
3. 建立可攜式啟動器、Git/Python wrapper，並將 Git、Python、uv/uvx、Node/npm/npx 加入啟動環境的 PATH；`HOME`、`USERPROFILE` 及 `CODEX_HOME` 指向可攜式資料夾。
4. 依 `manifests/extensions.json` 還原固定版本的擴充功能，最後執行本機狀態檢查。

若目標已安裝不同版本，腳本會停止並提示，不會靜默覆蓋。請先確認版本差異，再決定是否使用新的目標資料夾。Bootstrap 不會預設安裝 Fusion；如果需要在 C 槽重製後重裝 Fusion，且 `Workspace\Fusion360-Installer` 專案也在場，可明確指定 `-InstallFusion`。

## 版本與下載

- `manifests/versions.json` 鎖定 VS Code、Git、uv、Node.js、Python 及官方下載端點。
- `manifests/extensions.json` 是從目前安裝的 VS Code 擴充功能登錄擷取的 ID、版本與平台快照。
- 這份清單鎖定 VS Code 擴充功能本身；部分擴充功能在首次啟用時仍可能下載額外語言伺服器、runtime 或工具，這些依賴目前尚未逐項快照。
- `installers/classroom-repro/extensions/<publisher>.<extension>-<version>.vsix` 是選用的離線 VSIX 快取位置。沒有快取時，還原腳本會使用 VS Code Marketplace 安裝精確版本。
- GitHub 若提供 release asset digest，腳本會比對；若沒有，會使用 HTTPS、資產大小及解壓後版本驗證，並為下載快取建立 SHA-256 sidecar，供後續重用時核對。
- Node.js 固定為 `manifests/versions.json` 中的 LTS 版本和 SHA-256。
- VS Code 1.144.1 ZIP 的固定 SHA-256 與大小已寫入版本清單；Bootstrap 會比對，並驗證程式簽章、產品版本和既有快取 sidecar。

下載快取預設位於外層 VSCode 根目錄下的 `installers/classroom-repro`，與已安裝的程式目錄分開；重製 C 槽時可保留並重用。若 D 槽也會被重製，請將專案和 `-CacheRoot` 指向不會被清除的 USB、網路磁碟或其他持久化位置。

## 既有環境更新

本 repro 的 Bootstrap 用於依清單重建，遇到既有不同版本會停止；現有環境的原地更新由外層 `D:\Night_Trains\@George\VSCode` 管理。外層 [README](../../README.md) 與 [STATE](../../STATE.md) 記錄目前操作方式與狀態，腳本位於外層 `scripts`。維護實作現已另存於本專案 `config/maintenance`，可用 `scripts/Install-ClassroomMaintenance.ps1` 預覽、加 `-Apply` 部署；不同既有檔預設拒絕，明確以 `-ReplaceExisting` 套用前會備份。只複製本 repro 到別台電腦時，也能重建這些維護入口；完整環境仍使用 Bootstrap。

| 外層入口 | 用途與限制 |
| --- | --- |
| `Update-Portable.cmd` | 更新 Git、uv、Python；不更新 VS Code 本體。此維護流程取得最新版，與 repro 的固定版本重建不同。 |
| `Update-VSCode.cmd` | 套用已準備的 VS Code 1.144.1 ZIP；已安裝時直接提示，不會自動下載未來版本。 |
| `Launch-Portable-VSCode.cmd` | 沿用原路徑啟動，載入 D 槽設定、工具與 CODEX_HOME。 |

更新前先儲存所有工作，關閉 VS Code，再從檔案總管執行對應 `.cmd`。若本體更新仍偵測到同安裝路徑的背景程序，會要求輸入 `UPDATE`；確認後先嘗試正常關閉，再停止殘留程序。此動作可能丟失未儲存內容，請先存檔。不要直接雙擊 `.ps1`，本機預設可能用記事本開啟。

本體更新以官方 ZIP 暫存並驗證 Microsoft 簽章與版本，備份程式檔後才替換；保留 `data`、`portable-tools` 和啟動器。安裝目錄名稱沿用 `Portable-VSCode-1.142.0`，實際版本已為 1.144.1。外層 `maintenance/vscode-backups`、`maintenance/vscode-logs`、`maintenance/vscode-stage` 分別保留本體備份、日誌與暫存；工具更新的版本與摘要在 `portable-tools/versions.json`，日誌與備份在 `portable-tools/update-logs` 和 `portable-tools/.update-backups`。交易標示 `in-progress` 或 `needs-recovery` 時先處理回復，勿直接刪除備份重跑。

## 擴充功能與 agent 自訂內容

`scripts/Restore-Extensions.ps1` 會讀取固定版本清單。離線時可預先把對應 VSIX 放進快取；檔名格式為 `<publisher>.<extension>-<version>.vsix`。如果 Marketplace 不再提供某個舊版本，需使用保存的 VSIX，否則該項會明確失敗，避免悄悄改裝最新版。

目前 `data/agent-plugins` 中的兩組 Copilot CLI 自訂內容來自 VS Code 帳號同步。`manifests/agent-plugins.json` 記錄其來源與還原方式，`config/agent-plugins/copilotcli-standalone.mcp.json` 保存 MCP 設定參考。重建時請登入 VS Code，讓帳號同步重新產生資料夾；不要複製 VS Code 產生的 nonce/快取目錄。MCP 認證不包含在本專案內，需由使用者重新完成登入或授權。Playwright MCP 的同步設定目前使用 `@latest`，因此該 MCP 套件仍未鎖版；若要完全固定，需先取得明確套件版本再更新設定。

`config/settings.template.json` 只保留通用編輯器設定。原安裝中的雲端專案 ID、個人信任/自動核准規則、機器 ID、工作階段、Codex 記憶與登入狀態不會匯入或提交；請在重建後按個人需求自行恢復。

## Fusion 360

Fusion 安裝器仍由獨立的 `Workspace\Fusion360-Installer` 專案管理。它會從 Autodesk 官方來源下載當時的 Client Downloader、驗證簽章後安裝目前使用者版本。C 槽重製後可重新執行 `Fusion360-Installer\scripts\Install-Fusion.cmd`；這重現安裝流程，不代表固定重現同一個 Fusion build。

## 驗證與限制

## Codex 對話留存與首次遷移

Codex 對話是使用者資料，不會存進本 repro 專案。可攜式啟動器應將 `CODEX_HOME` 指向安裝目錄的 `data\home\.codex`。請透過 `Launch-VSCode.cmd` 啟動；直接開 `Code.exe` 或沿用尚未關閉的 VS Code 程序，可能繼續使用原本的環境。

若舊啟動器缺少這個設定，可單獨修正（會備份原啟動器）：

```powershell
.\scripts\Enable-PortableCodex.ps1 -LauncherOnly -Apply
```

若要保留 C 槽現有的對話，**先關閉所有 VS Code 和 Codex，再從外部 PowerShell 執行**：

```powershell
# 預覽；依實際使用者資料位置修改來源。
.\scripts\Enable-PortableCodex.ps1 -SourceCodexHome 'C:\Users\N22\.codex'
# 確認預覽後執行。
.\scripts\Enable-PortableCodex.ps1 -SourceCodexHome 'C:\Users\N22\.codex' -Apply
```

若系統停用 PowerShell 腳本，可從外部 PowerShell 使用以下單次執行方式（不變更永久執行原則）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\scripts\Enable-PortableCodex.ps1' -SourceCodexHome 'C:\Users\N22\.codex' -Apply
```

可用 `-InstallRoot` 指定其他安裝位置。腳本只複製對話、索引、state/memory SQLite 資料庫（包含存在的 WAL）和記憶文件，逐檔驗證 SHA-256；目前未修正資料庫內 `rollout_path`，故不得宣稱此初次匯入已保證對話可用。不刪除來源，不匯入登入憑證、設定、skills 或 plugins。若中途失敗，來源仍保留；先檢查目標，不要直接重新執行或清空資料夾。

若來源與目標都已有對話資料，現有腳本會明確停止，不會合併。不要把拒絕非空目標視為合併成功。安全合併需先關閉所有 Codex/VS Code 程序、保留來源及目標原件並另做備份；使用 SQLite `Connection.backup()`/backup API 對 state/memories 資料庫建立一致快照（會包含 WAL 中已提交內容），不可直接複製活躍 DB 覆蓋。再將來源與目標 JSONL 依 session/thread ID 去重「檔案」，不可刪除同一對話內事件，修正索引 `rollout_path` 指向 D 槽的新 session 檔案；保留兩邊索引及資料庫，先在獨立 CODEX_HOME 驗證舊對話、新對話與索引，再切換使用。專案不提供將私有對話寫入版本庫的工具。遷移後透過啟動器開啟 VS Code，依需要重新登入，確認能從最近聊天開啟舊對話，並建立一段新對話後重開，確認能接續。關閉 VS Code/Codex 後備份整個 `data\home\.codex` 到另一個持久化儲存位置；此目錄可能含登入資料，請勿提交 Git 或放入課堂共用包。專案的重要決策與下一步另外記錄在各專案 `STATE.md`，讓新對話也能接手。

官方參考：[本機狀態與 CODEX_HOME](https://learn.chatgpt.com/docs/config-file/config-advanced)、[接續既有聊天](https://learn.chatgpt.com/docs/projects)。

### 安裝驗證

Portable PowerShell 終端機設定在 `config/settings.template.json`，只套用此可攜式 VS Code。啟動器以 `setlocal` 提供 `VSCODE_PORTABLE_ROOT`；`scripts/Initialize-PortableTerminal.ps1` 設定 UTF-8 輸入、輸出、pipeline 與檔案 cmdlet 預設編碼，並啟用 `PYTHONUTF8=1`、`PYTHONIOENCODING=utf-8`。全域 Registry 不變更。

可單獨檢查現有安裝：

```powershell
.\scripts\Verify-Classroom.ps1 -InstallRoot 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0'
```

安裝需要網路連線至 Microsoft、GitHub 及 VS Code Marketplace。Microsoft/Marketplace 帳號登入、Codex/Claude/Gemini/GitHub/Notion 憑證、VS Code 同步資料，以及 Autodesk 授權不會由 repro 專案建立。請確認學校的 D 槽在重製後會保留；若不會，必須把快取和專案放到外部或網路持久化儲存位置。
