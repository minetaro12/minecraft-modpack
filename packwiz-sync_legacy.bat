@echo off
setlocal DisableDelayedExpansion

rem ============================================================
rem packwiz manifest: HTTPS URL or local pack.toml path.
rem Relative paths are resolved from the folder of this BAT file.
rem CHANGE THIS LINE when distributing your modpack over HTTPS.
rem ============================================================
set "PW_SYNC_PACK_SOURCE=https://minecraft-modpack.minetaro12.workers.dev/pack.toml"

set "PW_SYNC_SELF=%~f0"
set "PW_SYNC_SELECT=%~1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:PW_SYNC_SELF,[Text.Encoding]::UTF8);$m='# === POWERSHELL ===';$i=$t.LastIndexOf($m);if($i -lt 0){throw 'PowerShell section missing'};&([ScriptBlock]::Create($t.Substring($i+$m.Length)))"
set "PW_SYNC_RESULT=%ERRORLEVEL%"
echo.
if "%PW_SYNC_RESULT%"=="0" (echo Sync finished.) else (echo Sync failed. Exit code: %PW_SYNC_RESULT%)
pause
exit /b %PW_SYNC_RESULT%

# === POWERSHELL ===
$ErrorActionPreference = 'Stop'

function Test-File([string]$Path) {
    return [IO.File]::Exists($Path)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Download-File([string]$Url, [string]$Path) {
    Write-Host "ダウンロード: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 180 -Headers @{ 'User-Agent' = 'PackwizProfileSync/1.0' } | Out-Null
    if (-not (Test-File $Path) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "ダウンロードされたファイルが空です: $Url"
    }
}

function Get-LauncherProfiles {
    $roaming = Join-Path $env:APPDATA '.minecraft'
    $store = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.4297127D64EC6_8wekyb3d8bbwe\LocalCache\Local\minecraft'
    $filenames = @(
        (Join-Path $roaming 'launcher_profiles_microsoft_store.json'),
        (Join-Path $roaming 'launcher_profiles.json'),
        (Join-Path $store 'launcher_profiles_microsoft_store.json'),
        (Join-Path $store 'launcher_profiles.json')
    ) | Select-Object -Unique

    foreach ($file in $filenames) {
        if (-not (Test-File $file)) { continue }
        try {
            $root = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $root -or $null -eq $root.profiles) { continue }
            foreach ($entry in $root.profiles.PSObject.Properties) {
                if ($null -eq $entry.Value) { continue }
                $name = [string]$entry.Value.name
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $entry.Name }
                $gameDir = [string]$entry.Value.gameDir
                if ([string]::IsNullOrWhiteSpace($gameDir)) { $gameDir = $roaming }
                $gameDir = [Environment]::ExpandEnvironmentVariables($gameDir)
                if (-not [IO.Path]::IsPathRooted($gameDir)) {
                    $gameDir = Join-Path $roaming $gameDir
                }
                $gameDir = [IO.Path]::GetFullPath($gameDir)
                [PSCustomObject]@{
                    ProfileFile = $file
                    Id          = [string]$entry.Name
                    Name        = $name
                    Version     = [string]$entry.Value.lastVersionId
                    GameDir     = $gameDir
                }
            }
        } catch {
            Write-Warning "プロファイルを読み取れませんでした: $file ($($_.Exception.Message))"
        }
    }
}

function Select-Profile($Profiles) {
    Write-Host ''
    Write-Host '=== Minecraft公式ランチャー: インストール先プロファイル ===' -ForegroundColor Cyan
    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $p = $Profiles[$i]
        Write-Host ('[{0}] {1} ({2})' -f ($i + 1), $p.Name, $p.Version)
        Write-Host ('    {0}' -f $p.GameDir) -ForegroundColor DarkGray
    }
    Write-Host '[0] キャンセル'
    while ($true) {
        $raw = Read-Host '選択番号を入力'
        $number = 0
        if ([int]::TryParse($raw, [ref]$number) -and $number -ge 1 -and $number -le $Profiles.Count) {
            return $Profiles[$number - 1]
        }
        if ($raw -eq '0') { throw 'ユーザーがキャンセルしました。' }
        Write-Host '有効な番号を入力してください。' -ForegroundColor Yellow
    }
}

function Get-JavaMajor([string]$Exe) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = '-version'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        $message = $process.StandardError.ReadToEnd() + $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        $code = $process.ExitCode
        $process.Dispose()
        if ($code -ne 0) { return 0 }
        if ($message -match '(?:openjdk|java) version "(1\.)?(\d+)') {
            return [int]$Matches[2]
        }
    } catch { return 0 }
    return 0
}

function Get-Java([string]$CacheDir) {
    $command = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $candidate = $command.Source
        $major = Get-JavaMajor $candidate
        if ($major -ge 17) {
            Write-Host "既存のJava $major を使用: $candidate" -ForegroundColor Green
            return $candidate
        }
    }

    $jreDir = Join-Path $CacheDir 'temurin17'
    $cached = Join-Path $jreDir 'bin\java.exe'
    if ((Test-File $cached) -and (Get-JavaMajor $cached) -ge 17) {
        Write-Host "保存済みのTemurin 17を使用: $cached" -ForegroundColor Green
        return $cached
    }

    Write-Host 'Java 17以降が見つからないため、Eclipse Temurin 17 JREを取得します。' -ForegroundColor Yellow
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x64' }
    $apiUrl = "https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=$arch&image_type=jre&os=windows&vendor=eclipse"
    $assets = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 60 -Headers @{ 'User-Agent' = 'PackwizProfileSync/1.0' }
    $asset = @($assets) | Select-Object -First 1
    if ($null -eq $asset -or $null -eq $asset.binary -or $null -eq $asset.binary.package) {
        throw 'Adoptium APIからJavaのダウンロード情報を取得できませんでした。'
    }
    $package = $asset.binary.package
    if ([string]::IsNullOrWhiteSpace([string]$package.link) -or [string]::IsNullOrWhiteSpace([string]$package.checksum)) {
        throw 'JavaのURLまたはSHA-256チェックサムがありません。'
    }

    $stage = Join-Path $CacheDir 'java-staging'
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        $zipPath = Join-Path $stage 'temurin17.zip'
        Download-File ([string]$package.link) $zipPath
        if ((Get-Sha256 $zipPath) -ine ([string]$package.checksum)) {
            throw 'JavaアーカイブのSHA-256が一致しません。ダウンロードを中止します。'
        }
        $extract = Join-Path $stage 'expanded'
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
        $javaFile = Get-ChildItem -LiteralPath $extract -Filter java.exe -File -Recurse |
            Where-Object { $_.FullName -match '\\bin\\java\.exe$' } | Select-Object -First 1
        if ($null -eq $javaFile) { throw 'Javaアーカイブ内にbin\java.exeがありません。' }
        $javaHome = Split-Path -Parent (Split-Path -Parent $javaFile.FullName)
        if (Test-Path -LiteralPath $jreDir) { Remove-Item -LiteralPath $jreDir -Recurse -Force }
        Move-Item -LiteralPath $javaHome -Destination $jreDir
        if ((Get-JavaMajor $cached) -lt 17) { throw '取得したJavaを起動できません。' }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
    Write-Host "Javaの準備が完了: $cached" -ForegroundColor Green
    return $cached
}

function Test-Jar([string]$JarPath) {
    $stream = [IO.File]::OpenRead($JarPath)
    try {
        $header = New-Object byte[] 4
        if ($stream.Read($header, 0, 4) -ne 4) { return $false }
        return ($header[0] -eq 0x50 -and $header[1] -eq 0x4B -and $header[2] -eq 0x03 -and $header[3] -eq 0x04)
    } finally { $stream.Dispose() }
}

function Get-Bootstrap([string]$ScriptDir, [string]$CacheDir) {
    $localJar = Join-Path $ScriptDir 'packwiz-installer-bootstrap.jar'
    if (Test-File $localJar) {
        if (-not (Test-Jar $localJar)) { throw "不正なJARファイルです: $localJar" }
        return $localJar
    }
    $cachedJar = Join-Path $CacheDir 'packwiz-installer-bootstrap.jar'
    if ((Test-File $cachedJar) -and (Test-Jar $cachedJar)) { return $cachedJar }

    Write-Host 'packwiz-installer-bootstrapをGitHub公式リリースから取得します。' -ForegroundColor Yellow
    $api = 'https://api.github.com/repos/packwiz/packwiz-installer-bootstrap/releases/latest'
    $release = Invoke-RestMethod -Uri $api -TimeoutSec 60 -Headers @{ 'User-Agent' = 'PackwizProfileSync/1.0'; 'Accept' = 'application/vnd.github+json' }
    $asset = @($release.assets) | Where-Object { $_.name -eq 'packwiz-installer-bootstrap.jar' } | Select-Object -First 1
    if ($null -eq $asset) { throw 'GitHubの公式リリースでbootstrap JARが見つかりません。' }
    $tempJar = Join-Path $CacheDir 'bootstrap.tmp'
    try {
        Download-File ([string]$asset.browser_download_url) $tempJar
        if (-not (Test-Jar $tempJar)) { throw '取得したファイルはJARではありません。' }
        if ([string]$asset.digest -match '^sha256:([a-fA-F0-9]{64})$') {
            if ((Get-Sha256 $tempJar) -ine $Matches[1]) { throw 'bootstrap JARのSHA-256が一致しません。' }
        }
        Move-Item -LiteralPath $tempJar -Destination $cachedJar -Force
    } finally {
        if (Test-File $tempJar) { Remove-Item -LiteralPath $tempJar -Force }
    }
    return $cachedJar
}

function Main {
    if ($env:PW_SYNC_SELECT -and $env:PW_SYNC_SELECT -notin @('--select', '--reset')) {
        throw '引数は --select のみ対応しています。'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $scriptDir = Split-Path -Parent $env:PW_SYNC_SELF
    $packSource = $env:PW_SYNC_PACK_SOURCE
    if ([string]::IsNullOrWhiteSpace($packSource)) { throw 'BAT冒頭のPW_SYNC_PACK_SOURCEを設定してください。' }
    if ($packSource -notmatch '^https?://') {
        if (-not [IO.Path]::IsPathRooted($packSource)) { $packSource = Join-Path $scriptDir $packSource }
        $packSource = [IO.Path]::GetFullPath($packSource)
        if (-not (Test-File $packSource)) { throw "pack.tomlが見つかりません: $packSource" }
    } elseif ($packSource -match '^http://' -and $packSource -notmatch '^http://(localhost|127\.0\.0\.1)(:|/)') {
        Write-Warning 'HTTP配信ではModpackが通信途中に改ざんされるリスクがあります。HTTPSを使用してください。'
    }

    $appDir = Join-Path $env:LOCALAPPDATA 'PackwizProfileSync'
    $cacheDir = Join-Path $appDir 'cache'
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($packSource))
        $key = ([BitConverter]::ToString($bytes)).Replace('-', '').Substring(0, 16).ToLowerInvariant()
    } finally { $sha.Dispose() }
    $selectionPath = Join-Path $appDir ("profile-$key.json")

    $profiles = @(Get-LauncherProfiles | Sort-Object Name, Version, ProfileFile)
    if ($profiles.Count -eq 0) {
        throw '公式ランチャーのプロファイルがありません。ランチャーで一度起動構成を作成してから再実行してください。'
    }

    $chosen = $null
    if ((Test-File $selectionPath) -and $env:PW_SYNC_SELECT -ne '--select' -and $env:PW_SYNC_SELECT -ne '--reset') {
        try {
            $saved = Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $chosen = $profiles | Where-Object { $_.ProfileFile -eq $saved.ProfileFile -and $_.Id -eq $saved.ProfileId } | Select-Object -First 1
        } catch {
            Write-Warning '前回のプロファイル選択を読み込めませんでした。再選択します。'
        }
    }
    if ($null -eq $chosen) {
        $chosen = Select-Profile $profiles
        Write-Host ''
        Write-Host ('選択: {0} / {1}' -f $chosen.Name, $chosen.Version) -ForegroundColor Cyan
        Write-Host ('同期先: {0}' -f $chosen.GameDir)
        Write-Warning '同じゲームディレクトリを使う他の起動構成にもModの変更が影響します。'
        if ($chosen.Version -notmatch '(?i)forge|fabric|quilt|neoforge') {
            Write-Warning '選択した起動構成はForgeなどのModローダーではない可能性があります。'
        }
        $answer = Read-Host 'このプロファイルを保存して同期しますか？ (y/N)'
        if ($answer -notin @('y','Y','yes','YES')) { throw 'キャンセルされました。' }
        if (-not (Test-Path -LiteralPath $chosen.GameDir -PathType Container)) {
            throw "ゲームディレクトリがありません: $($chosen.GameDir)。一度この起動構成でMinecraftを起動してください。"
        }
        $data = @{ ProfileFile = $chosen.ProfileFile; ProfileId = $chosen.Id }
        [IO.File]::WriteAllText($selectionPath, ($data | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    } else {
        Write-Host ('保存済みプロファイル: {0} ({1})' -f $chosen.Name, $chosen.Version) -ForegroundColor Cyan
        Write-Host ('同期先: {0}' -f $chosen.GameDir)
    }

    if (-not (Test-Path -LiteralPath $chosen.GameDir -PathType Container)) {
        throw "ゲームディレクトリがありません: $($chosen.GameDir)。一度この起動構成でMinecraftを起動してください。"
    }
    $packArgument = if ($packSource -match '^https?://') { $packSource } else { ([Uri]$packSource).AbsoluteUri }
    $java = Get-Java $cacheDir
    $bootstrap = Get-Bootstrap $scriptDir $cacheDir
    Write-Host ''
    Write-Host '=== packwiz GUI 同期開始 ===' -ForegroundColor Cyan
    Write-Host ('マニフェスト: {0}' -f $packSource)
    Push-Location -LiteralPath $chosen.GameDir
    try {
        & $java -jar $bootstrap -s client --title "Minecraft Mod Sync" --pack-folder $chosen.GameDir $packArgument
        if ($LASTEXITCODE -ne 0) { throw "packwiz-installerが終了コード $LASTEXITCODE を返しました。" }
    } finally {
        Pop-Location
    }
    Write-Host 'Modと設定ファイルの同期が完了しました。' -ForegroundColor Green
}

try { Main } catch {
    Write-Host ''
    Write-Host ('エラー: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
