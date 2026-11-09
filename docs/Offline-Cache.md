# 離線快取盤點與目前限制

## 2026-11-09 實際結果

已保存 37／37 個清單版本的 VSIX，最新盤點為 **4 PASS、39 UNVERIFIED、0 MISSING、0 FAIL**。VS Code、Git、uv、Node 的快取可按現有摘要／metadata 核對；37 個 VSIX 的套件 ID、版本與本機 sidecar 都一致，但未固定獨立可信的來源摘要，故仍列為 UNVERIFIED。另兩項 UNVERIFIED 是 Python runtime 與 uv cache。完整 Bootstrap 的全離線支援仍為 false。

隔離重建已實際通過 37 個擴充版本驗證；其中 Roo Code 舊版無法從 Marketplace 取得，透過保留的匹配 VSIX 完成安裝。持久快取不能只依賴 Marketplace 將來仍保留相同舊版。

## 保留已下載的 VSIX

`Save-ExtensionCache.py` 僅從既有 `CachedExtensionVSIXs` 讀取原始套件，核對 ZIP 內 `extension/package.json` 的 publisher/name/version；不下載、不從已安裝資料夾重新打包，也不讀取對話或登入內容。預設預覽，加 `--apply` 後保存並驗證本機 SHA-256 sidecar。不同的既有快取會停止，不會覆蓋。

```powershell
& 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0\portable-tools\Python\bin\python.exe' `
  .\scripts\Save-ExtensionCache.py `
  --source 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0\data\user-data\CachedExtensionVSIXs' `
  --cache-root 'D:\Night_Trains\@George\VSCode\installers\classroom-repro' --apply
```

`--source` 可以重複指定，例如加入隔離重建時產生的下載快取。完整套件與現機 JSON 報告均留在 Git 外；本機雜湊只能證明內容未變，不能單獨證明發行者身份。

`Test-OfflineCache.ps1` 讀取 `manifests/versions.json`、`manifests/extensions.json`、指定快取及安裝目錄中的版本 metadata，不讀取 `data`、Codex 對話、登入憑證或記憶。預設只讀快取與安裝檔；預設將盤點結果寫到 `output/offline-cache-report.json`，此現機報告已單獨加入 `.gitignore`。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-OfflineCache.ps1 `
  -InstallRoot 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0' `
  -CacheRoot 'D:\Night_Trains\@George\VSCode\installers\classroom-repro'
```

也可用 `-ReportPath` 指定另一個報告位置。腳本不下載、不安裝、不修改或清除快取；`FAIL` 表示已存在檔案的摘要／大小不符，`MISSING` 表示找不到預期檔案，`UNVERIFIED` 表示檔案存在但目前缺少可核對的固定摘要或本機 release metadata。

## 快取位置與驗證

- VS Code：`CacheRoot/vscode/VSCode-1.144.1-win32-x64.zip`，依 manifest 固定 bytes 和 SHA-256 比對；若 sidecar 存在也必須一致。
- PortableGit：`CacheRoot/Git/<GitHub release asset name>`；uv：`CacheRoot/uv/uv-x86_64-pc-windows-msvc.zip`。現行 manifest 沒有固定這兩個 archive 的摘要。單獨 `.sha256` sidecar 只可自我比對，不足以證明下載來源；要標記 `PASS`，需有相符 sidecar，以及 `<archive>.release.json`（含 repository、releaseTag、assetName、size、sha256）或安裝目錄 `portable-tools/versions.json` 內對應 pinned release 的 hash/size metadata。
- Node.js：`CacheRoot/node/node-v24.22.2-win-x64.zip`，依 manifest 固定 SHA-256 驗證。
- 擴充功能：`CacheRoot/extensions/<publisher>.<extension>-<version>.vsix`。盤點會讀 VSIX 內的 `extension/package.json` 驗證 publisher/name/version，並比對存在的 `.sha256` sidecar。若 metadata 與 sidecar 都一致，`integrityState` 會標成 `NOT_PINNED_HASH_VERIFIED`，但狀態仍是 `UNVERIFIED`、`originState=UNKNOWN`，因為 manifest 沒有可信任的固定摘要；只有 ID/version metadata 而無 sidecar 時也不能證明 archive 原始來源。缺檔時 Bootstrap 會使用 Marketplace。
- Python：現行安裝器透過 `uv python install` 建立 `InstallRoot/portable-tools/Python/runtimes`，uv cache 位於 `InstallRoot/portable-tools/Python/cache`。報告分開列已安裝 runtime 與 uv cache；uv cache 不是 manifest 固定的 Python archive，兩者都不能證明新機可離線重建。

## 完全離線的缺口

目前 Bootstrap 對 Git 和 uv 會查詢 GitHub release API 取得 asset 名稱與 metadata，即使相應 archive 已快取仍需網路。Marketplace 也可能需要網路，除非所有 37 個 VSIX 均已預存且可驗證。Python 由 uv 管理，流程沒有固定且可攜的 Python 離線 archive。Node、VS Code ZIP 或個別 VSIX 盤點為 `PASS` 只代表該項快取可按已知摘要核對，不代表 Bootstrap 已支援全離線。要達成全離線重建，仍需保存並信任 Git/uv 的 release metadata、固定 VSIX 摘要、提供 Python 離線來源，並調整安裝流程避免依賴線上 API/Marketplace。
