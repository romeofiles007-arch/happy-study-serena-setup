param(
    [string]$TunnelId = '',
    [string]$ApiKey = ''
)

# Values may also arrive via environment variables (preferred over command-line
# arguments, which are visible to any local process in the process list).
if ([string]::IsNullOrWhiteSpace($TunnelId)) { $TunnelId = $env:HAPPY_STUDY_TUNNEL_ID }
if ([string]::IsNullOrWhiteSpace($ApiKey))   { $ApiKey   = $env:HAPPY_STUDY_API_KEY }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DefaultInstall = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Happy Study\DWB Serena Tunnel'

$BrandTitle  = 'Happy Study'
$BrandAuthor = 'by อ.คฑาวุฐ'

# Where tunnel-client is fetched from when it is not shipped beside this script.
# Overridden by HAPPY_STUDY_CLIENT_URL or a "tunnel client url" line in .env.
$DefaultClientUrl = 'https://github.com/romeofiles007-arch/happy-study-serena-setup/releases/download/v1.0.0/tunnel-client.zip'

# ---------------------------------------------------------------- palette ----
$ColHeader = [System.Drawing.Color]::FromArgb(17, 109, 97)
$ColHeader2= [System.Drawing.Color]::FromArgb(23, 143, 126)
$ColGo     = [System.Drawing.Color]::FromArgb(22, 155, 88)
$ColGoHot  = [System.Drawing.Color]::FromArgb(26, 176, 100)
$ColCard   = [System.Drawing.Color]::FromArgb(246, 248, 249)
$ColLine   = [System.Drawing.Color]::FromArgb(222, 228, 230)
$ColText   = [System.Drawing.Color]::FromArgb(33, 37, 41)
$ColMuted  = [System.Drawing.Color]::FromArgb(112, 121, 128)
$ColOk     = [System.Drawing.Color]::FromArgb(22, 140, 80)
$ColRun    = [System.Drawing.Color]::FromArgb(19, 116, 190)
$ColBad    = [System.Drawing.Color]::FromArgb(190, 45, 45)
$ColWarn   = [System.Drawing.Color]::FromArgb(176, 122, 12)

function New-Font([single]$Size, [string]$Style = 'Regular') {
    New-Object System.Drawing.Font('Segoe UI', $Size, [System.Drawing.FontStyle]::$Style)
}

# ============================================================ install core ====

function Pump-UI { [System.Windows.Forms.Application]::DoEvents() }

function Set-Status([string]$Text, [int]$Percent) {
    $status.Text = $Text
    $progress.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
    Pump-UI
}

function Add-UserBinToPath {
    $candidateDirs = @(
        (Join-Path $HOME '.local\bin'),
        (Join-Path $env:USERPROFILE '.local\bin'),
        (Join-Path $env:LOCALAPPDATA 'Programs\uv\bin')
    ) | Select-Object -Unique

    foreach ($dir in $candidateDirs) {
        if ((Test-Path $dir) -and (($env:PATH -split ';') -notcontains $dir)) {
            $env:PATH = "$dir;$env:PATH"
        }
    }
}

function Get-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-Native {
    # Tools such as uv write progress AND errors to stderr.  In Windows PowerShell
    # 5.1, "& tool ... 2>&1" while $ErrorActionPreference is 'Stop' turns the first
    # stderr line into a terminating error, so the caller never gets to look at the
    # real exit code.  That is why "uv python find 3.13" failing on a machine
    # without Python aborted the installer instead of falling through to
    # "uv python install 3.13".  Capture output as plain text and report the exit
    # code instead.
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $exitCode = -1
    $lines = @()
    try {
        $lines = & $FilePath @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
        }
        $exitCode = $LASTEXITCODE
    }
    catch {
        $lines = @($_.Exception.Message)
        $exitCode = -1
    }
    finally {
        $ErrorActionPreference = $previous
    }

    if ($null -eq $lines) { $lines = @() }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Lines    = $lines
        Text     = (($lines -join "`r`n").Trim())
    }
}

function Test-PythonUsable([string]$PythonPath) {
    if ([string]::IsNullOrWhiteSpace($PythonPath)) { return $false }
    $probe = Invoke-Native $PythonPath @('-c', 'import runpy')
    return ($probe.ExitCode -eq 0)
}

function Get-ExistingEnvConfiguration {
    # Accepts both the loose "openai api key : sk-..." style used by this bundle
    # and standard dotenv "OPENAI_API_KEY=sk-..." lines.
    $result = [PSCustomObject]@{ TunnelId = ''; ApiKey = ''; ClientUrl = '' }

    $searchDirs = @(
        $PSScriptRoot,
        (Split-Path -Parent $PSScriptRoot)
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($dir in $searchDirs) {
        $envFile = Join-Path $dir '.env'
        if (-not (Test-Path -LiteralPath $envFile)) { continue }

        foreach ($line in (Get-Content -LiteralPath $envFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*#') { continue }
            if ($line -match '^\s*(?:tunnel[_\s-]*client[_\s-]*url|client[_\s-]*url|download[_\s-]*url)\s*[:=]\s*(.+?)\s*$') {
                if ([string]::IsNullOrWhiteSpace($result.ClientUrl)) { $result.ClientUrl = $Matches[1].Trim() }
            }
            elseif ($line -match '^\s*(?:tunnel[_\s-]*id)\s*[:=]\s*(.+?)\s*$') {
                if ([string]::IsNullOrWhiteSpace($result.TunnelId)) { $result.TunnelId = $Matches[1].Trim() }
            }
            elseif ($line -match '^\s*(?:api[_\s-]*key|openai[_\s-]*api[_\s-]*key)\s*[:=]\s*(.+?)\s*$') {
                if ([string]::IsNullOrWhiteSpace($result.ApiKey)) { $result.ApiKey = $Matches[1].Trim() }
            }
        }
        if ($result.TunnelId -and $result.ApiKey -and $result.ClientUrl) { break }
    }
    return $result
}

function Convert-ToDirectDownloadUrl([string]$Url) {
    # Share links from common hosts point at an HTML preview page, not the file.
    # Rewrite the ones we recognise so Invoke-WebRequest receives real bytes.
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    $u = $Url.Trim()

    if ($u -match 'drive\.google\.com/file/d/([^/]+)') {
        return "https://drive.google.com/uc?export=download&id=$($Matches[1])"
    }
    if ($u -match 'drive\.google\.com/open\?id=([^&]+)') {
        return "https://drive.google.com/uc?export=download&id=$($Matches[1])"
    }
    if ($u -match 'dropbox\.com') {
        $u = $u -replace '[?&]dl=0', ''
        if ($u -notmatch 'dl=1') { $u += $(if ($u.Contains('?')) { '&dl=1' } else { '?dl=1' }) }
        return $u
    }
    if ($u -match '^https://github\.com/(.+)/blob/(.+)$') {
        return "https://raw.githubusercontent.com/$($Matches[1])/$($Matches[2])"
    }
    if ($u -match 'huggingface\.co/.+/blob/') {
        return ($u -replace '/blob/', '/resolve/')
    }
    if ($u -match '1drv\.ms|onedrive\.live\.com') {
        return $u
    }
    return $u
}

function Reset-PythonRuntimeEnvironment {
    # A machine-wide PYTHONHOME/PYTHONPATH can make the Python used by uv/Serena
    # unable to import standard-library modules such as runpy.  Do not let it leak
    # into the installer process or the child processes it starts.
    foreach ($name in @('PYTHONHOME', 'PYTHONPATH', 'PYTHONEXECUTABLE', 'VIRTUAL_ENV', 'CONDA_PREFIX')) {
        Remove-Item ("Env:" + $name) -ErrorAction SilentlyContinue
    }
}

function Ensure-Uv {
    Reset-PythonRuntimeEnvironment
    Add-UserBinToPath
    $uv = Get-CommandPath 'uv'
    if ($uv) { return $uv }

    Set-Status 'กำลังดาวน์โหลดและติดตั้ง uv...' 22
    $installScript = Join-Path $env:TEMP ("happy-study-uv-" + [guid]::NewGuid().ToString('N') + '.ps1')
    try {
        Invoke-WebRequest -UseBasicParsing 'https://astral.sh/uv/install.ps1' -OutFile $installScript
        $run = Invoke-Native 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installScript)
        if ($run.ExitCode -ne 0) {
            throw "ตัวติดตั้ง uv จบการทำงานด้วยรหัส $($run.ExitCode)`r`n`r`n$($run.Text)"
        }
    }
    catch [System.Net.WebException] {
        throw "ดาวน์โหลด uv ไม่สำเร็จ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่`r`n`r`n$($_.Exception.Message)"
    }
    finally {
        Remove-Item $installScript -Force -ErrorAction SilentlyContinue
    }

    Add-UserBinToPath
    $uv = Get-CommandPath 'uv'
    if (-not $uv) {
        foreach ($fallback in @((Join-Path $HOME '.local\bin\uv.exe'), (Join-Path $env:USERPROFILE '.local\bin\uv.exe'))) {
            if (Test-Path $fallback) { $uv = $fallback; break }
        }
    }
    if (-not $uv) { throw 'ติดตั้ง uv แล้ว แต่ยังไม่พบไฟล์ uv.exe กรุณาปิดโปรแกรมแล้วลองใหม่อีกครั้ง' }
    return $uv
}

function Find-ExistingPython313 {
    $candidates = @(
        'python',
        'python3',
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
        (Join-Path $env:ProgramFiles 'Python313\python.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Python313\python.exe')
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        $probe = Invoke-Native $candidate @('--version')
        if ($probe.ExitCode -eq 0 -and $probe.Text -match 'Python 3\.13') {
            $resolved = (Get-Command $candidate -ErrorAction SilentlyContinue).Source
            if ($resolved) { return $resolved }
            return $candidate
        }
    }
    return $null
}

function Get-UvPython313([string]$UvPath) {
    # "uv python find" exits non-zero and writes to stderr when nothing matches.
    # That is an expected outcome on a fresh machine, not an installer failure.
    $find = Invoke-Native $UvPath @('python', 'find', '3.13')
    if ($find.ExitCode -ne 0) { return $null }
    $candidate = $find.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    return $candidate.Trim()
}

function Ensure-Python313([string]$UvPath) {
    Reset-PythonRuntimeEnvironment
    Set-Status 'กำลังตรวจสอบ Python 3.13...' 36

    $existingPython = Find-ExistingPython313
    if ($existingPython -and (Test-PythonUsable $existingPython)) {
        Set-Status 'พบ Python 3.13 ในเครื่องแล้ว' 44
        return $existingPython
    }

    Set-Status 'กำลังค้นหา Python 3.13...' 38
    $managed = Get-UvPython313 $UvPath
    if ($managed -and (Test-PythonUsable $managed)) {
        Set-Status 'พบ Python 3.13 ที่ uv ติดตั้งไว้แล้ว' 44
        return $managed
    }

    # Nothing usable found - this is the normal path on a fresh machine.
    Set-Status 'กำลังดาวน์โหลด Python 3.13 (อาจใช้เวลา 1-3 นาที)...' 40
    $install = Invoke-Native $UvPath @('python', 'install', '3.13')
    if ($install.ExitCode -ne 0) {
        throw "ดาวน์โหลด Python 3.13 ไม่สำเร็จ (รหัส $($install.ExitCode))`r`n`r`n$($install.Text)"
    }

    Set-Status 'กำลังตรวจสอบ Python 3.13 ที่เพิ่งติดตั้ง...' 44
    $managed = Get-UvPython313 $UvPath
    if (-not $managed) {
        $listed = Invoke-Native $UvPath @('python', 'list', '--only-installed')
        throw ("ติดตั้ง Python 3.13 แล้ว แต่ยังค้นหาไม่พบ`r`n`r`n" +
               "ผลการติดตั้ง:`r`n$($install.Text)`r`n`r`n" +
               "รายการที่ติดตั้งอยู่:`r`n$($listed.Text)")
    }
    if (-not (Test-PythonUsable $managed)) {
        throw "Python 3.13 ติดตั้งแล้ว แต่เริ่มทำงานไม่ได้ (import runpy ไม่สำเร็จ)`r`n`r`n$managed"
    }
    return $managed
}

function Test-Serena([string]$SerenaPath) {
    if ([string]::IsNullOrWhiteSpace($SerenaPath) -or -not (Test-Path $SerenaPath)) { return $false }
    Reset-PythonRuntimeEnvironment
    $probe = Invoke-Native $SerenaPath @('--version')
    return ($probe.ExitCode -eq 0)
}

function Find-Serena {
    Add-UserBinToPath
    $candidates = @()
    $cmd = Get-CommandPath 'serena'
    if ($cmd) { $candidates += $cmd }
    $candidates += @(
        (Join-Path $HOME '.local\bin\serena.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\serena.exe'),
        (Join-Path $env:APPDATA 'Python\Scripts\serena.exe')
    )
    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Serena $candidate) { return $candidate }
    }
    return $null
}

function Ensure-Serena([string]$UvPath, [string]$PythonPath) {
    Reset-PythonRuntimeEnvironment
    $serena = Find-Serena
    if (-not $serena) {
        Set-Status 'กำลังติดตั้ง Serena (อาจใช้เวลาสักครู่)...' 48

        # Reuse the interpreter located by Ensure-Python313 when it is a real path,
        # so this step cannot download a second copy of Python 3.13.
        $pySpec = '3.13'
        if ($PythonPath -and (Test-Path -LiteralPath $PythonPath)) { $pySpec = $PythonPath }

        Reset-PythonRuntimeEnvironment
        $toolInstall = Invoke-Native $UvPath @('tool', 'install', '-p', $pySpec, 'serena-agent', '--force')
        if ($toolInstall.ExitCode -ne 0) {
            throw "ติดตั้ง Serena ไม่สำเร็จ (รหัส $($toolInstall.ExitCode))`r`n`r`n$($toolInstall.Text)"
        }
        Add-UserBinToPath
        $serena = Find-Serena
    }
    if (-not $serena) { throw 'ติดตั้ง Serena แล้ว แต่ยังเรียกใช้งานไม่ได้ กรุณาปิดโปรแกรมแล้วลองใหม่' }

    Set-Status 'กำลังตั้งค่า Serena...' 56
    $init = Invoke-Native $serena @('init')
    if ($init.ExitCode -ne 0) {
        throw "ตั้งค่า Serena ไม่สำเร็จ (รหัส $($init.ExitCode))`r`n`r`n$($init.Text)"
    }

    return $serena
}

function Prepare-InstallationFolder([string]$TargetDir) {
    Set-Status 'กำลังเตรียมโฟลเดอร์ติดตั้ง...' 8
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}

function Find-TunnelClientBundle {
    # The tunnel-client folder ships alongside this Setup folder.  Accept it in the
    # Setup folder itself, one level up, or two levels up.
    $roots = @(
        $PSScriptRoot,
        (Split-Path -Parent $PSScriptRoot),
        (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($root in $roots) {
        $candidate = Join-Path $root 'tunnel-client'
        if (Test-Path -LiteralPath (Join-Path $candidate 'tunnel-client.exe')) { return $candidate }
    }
    return $null
}

$CacheRoot   = Join-Path $env:LOCALAPPDATA 'Happy Study\cache'
$CacheBundle = Join-Path $CacheRoot 'tunnel-client'

function Find-CachedTunnelClient {
    # Downloaded once, reused by every later install on this machine.
    if (Test-Path -LiteralPath (Join-Path $CacheBundle 'tunnel-client.exe')) { return $CacheBundle }
    return $null
}

function Get-TunnelClientDownloadUrl {
    # Order: environment override, then .env, then the built-in default.  The
    # default matters because tunnel-client is not stored in git (57 MB of
    # binaries), so a plain "Download ZIP" of the repository has no bundle and
    # must still be able to fetch one without the user configuring anything.
    if (-not [string]::IsNullOrWhiteSpace($env:HAPPY_STUDY_CLIENT_URL)) {
        return $env:HAPPY_STUDY_CLIENT_URL.Trim()
    }
    $cfg = Get-ExistingEnvConfiguration
    if (-not [string]::IsNullOrWhiteSpace($cfg.ClientUrl)) { return $cfg.ClientUrl }
    if (-not [string]::IsNullOrWhiteSpace($DefaultClientUrl)) { return $DefaultClientUrl }
    return $null
}

function Save-TunnelClientToCache([string]$Url) {
    # Downloads a .zip that contains tunnel-client.exe (at the root or inside a
    # single folder) and unpacks it into the machine-wide cache.
    $direct = Convert-ToDirectDownloadUrl $Url
    $tempZip = Join-Path $env:TEMP ("happy-study-tc-" + [guid]::NewGuid().ToString('N') + '.zip')
    $tempDir = Join-Path $env:TEMP ("happy-study-tc-" + [guid]::NewGuid().ToString('N'))

    try {
        Set-Status 'กำลังดาวน์โหลด tunnel-client (ประมาณ 26 MB)...' 60
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $direct -OutFile $tempZip -TimeoutSec 600
        }
        catch {
            throw ("ดาวน์โหลด tunnel-client ไม่สำเร็จ`r`n`r`n" +
                   "URL: $direct`r`n`r`n" +
                   "$($_.Exception.Message)`r`n`r`n" +
                   "กรุณาตรวจสอบอินเทอร์เน็ต และตรวจว่าลิงก์เปิดได้แบบสาธารณะ (ไม่ต้องล็อกอิน)")
        }

        $size = (Get-Item -LiteralPath $tempZip).Length
        if ($size -lt 1MB) {
            throw ("ไฟล์ที่ดาวน์โหลดมามีขนาดเพียง {0:N0} KB ซึ่งเล็กเกินไป`r`n`r`n" -f ($size / 1KB) +
                   "มักเกิดจากลิงก์ที่ต้องล็อกอินก่อน หรือเป็นหน้าเว็บแทนที่จะเป็นไฟล์`r`n" +
                   "กรุณาใช้ลิงก์ที่กดแล้วดาวน์โหลดไฟล์ได้ทันทีโดยไม่ต้องล็อกอิน")
        }

        Set-Status 'กำลังแตกไฟล์ tunnel-client...' 63
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        try { Expand-Archive -LiteralPath $tempZip -DestinationPath $tempDir -Force }
        catch { throw "แตกไฟล์ไม่สำเร็จ ไฟล์ที่ดาวน์โหลดมาอาจไม่ใช่ไฟล์ ZIP`r`n`r`n$($_.Exception.Message)" }

        $found = Get-ChildItem -LiteralPath $tempDir -Recurse -Filter 'tunnel-client.exe' -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if (-not $found) { throw 'ไฟล์ ZIP ที่ดาวน์โหลดมาไม่มี tunnel-client.exe อยู่ข้างใน' }

        Set-Status 'กำลังบันทึก tunnel-client ไว้ใช้ครั้งต่อไป...' 64
        if (Test-Path -LiteralPath $CacheBundle) { Remove-Item -LiteralPath $CacheBundle -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $CacheBundle | Out-Null
        Copy-Item -Path (Join-Path $found.Directory.FullName '*') -Destination $CacheBundle -Recurse -Force

        if (-not (Test-Path -LiteralPath (Join-Path $CacheBundle 'tunnel-client.exe'))) {
            throw 'บันทึกลง cache แล้วแต่ไม่พบ tunnel-client.exe'
        }
        return $CacheBundle
    }
    finally {
        Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-TunnelClientBundle {
    # 1. shipped beside Setup   2. previously downloaded cache   3. download now
    $bundle = Find-TunnelClientBundle
    if ($bundle) { return $bundle }

    $bundle = Find-CachedTunnelClient
    if ($bundle) {
        Set-Status 'ใช้ tunnel-client ที่ดาวน์โหลดไว้แล้ว' 63
        return $bundle
    }

    $url = Get-TunnelClientDownloadUrl
    if (-not $url) {
        throw ("ไม่พบ tunnel-client และยังไม่ได้ตั้งค่าลิงก์ดาวน์โหลด`r`n`r`n" +
               "วิธีแก้ เลือกอย่างใดอย่างหนึ่ง:`r`n`r`n" +
               "1) เปิดไฟล์ .env แล้วเพิ่มบรรทัดนี้`r`n" +
               "      tunnel client url : https://ลิงก์ไฟล์ zip ของคุณ`r`n`r`n" +
               "2) วางโฟลเดอร์ tunnel-client ไว้ในโฟลเดอร์ Setup`r`n`r`n" +
               "ไฟล์ zip ต้องมี tunnel-client.exe อยู่ข้างใน และเปิดดาวน์โหลดได้โดยไม่ต้องล็อกอิน")
    }
    return (Save-TunnelClientToCache $url)
}

function Install-TunnelClient([string]$TargetDir) {
    Set-Status 'กำลังติดตั้ง OpenAI tunnel-client...' 60
    $bundle = Resolve-TunnelClientBundle

    $dest = Join-Path $TargetDir 'tunnel-client'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $bundle '*') -Destination $dest -Recurse -Force

    $client = Join-Path $dest 'tunnel-client.exe'
    if (-not (Test-Path $client)) { throw 'ติดตั้ง tunnel-client เสร็จแล้วแต่ไม่พบ tunnel-client.exe' }
    Set-Status 'ติดตั้ง tunnel-client เรียบร้อย' 66
}

function Save-SecureConfiguration([string]$TargetDir, [string]$TunnelId, [string]$ApiKey) {
    Set-Status 'กำลังบันทึก Tunnel ID และเข้ารหัส API Key...' 74
    $configDir  = Join-Path $TargetDir 'config'
    $configPath = Join-Path $configDir 'team.ps1'
    $secretPath = Join-Path $configDir 'api-key.dpapi'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    $escapedTunnel = $TunnelId.Replace("'", "''")
    $configContent = @"
# Happy Study - DWB Serena Tunnel local configuration
# API key is stored separately using Windows DPAPI.

`$TunnelId = '$escapedTunnel'
"@
    Set-Content -Path $configPath -Value $configContent -Encoding UTF8

    $secureKey = ConvertTo-SecureString -String $ApiKey -AsPlainText -Force
    $encryptedKey = ConvertFrom-SecureString -SecureString $secureKey
    Set-Content -Path $secretPath -Value $encryptedKey -Encoding ASCII
}

function Create-StartFiles([string]$TargetDir, [string]$SerenaExe) {
    Set-Status 'กำลังสร้างไฟล์เริ่มใช้งาน...' 82
    $startScript = Join-Path $TargetDir 'start.ps1'

    $startScriptContent = @'
$ErrorActionPreference = 'Stop'

function Stop-WithMessage([string]$Message) {
    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Red
    Write-Host '  เกิดข้อผิดพลาด - Tunnel ยังไม่ได้เริ่มทำงาน' -ForegroundColor Red
    Write-Host '==================================================' -ForegroundColor Red
    Write-Host ''
    Write-Host $Message -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'กรุณาถ่ายรูปหน้าจอนี้ส่งให้ผู้ดูแลระบบ' -ForegroundColor Gray
    Write-Host 'กด Enter เพื่อปิดหน้าต่างนี้' -ForegroundColor Gray
    [void](Read-Host)
    exit 1
}

trap { Stop-WithMessage $_.Exception.Message }

foreach ($name in @('PYTHONHOME', 'PYTHONPATH', 'PYTHONEXECUTABLE', 'VIRTUAL_ENV', 'CONDA_PREFIX')) {
    Remove-Item ("Env:" + $name) -ErrorAction SilentlyContinue
}

$Root       = $PSScriptRoot
$ConfigDir  = Join-Path $Root 'config'
$ConfigPath = Join-Path $ConfigDir 'team.ps1'
$SecretPath = Join-Path $ConfigDir 'api-key.dpapi'
$Client     = Join-Path $Root 'tunnel-client\tunnel-client.exe'

if (-not (Test-Path -LiteralPath $ConfigPath) -or -not (Test-Path -LiteralPath $SecretPath)) {
    Stop-WithMessage 'ไม่พบข้อมูลการตั้งค่า กรุณารัน Setup ใหม่อีกครั้ง'
}
if (-not (Test-Path -LiteralPath $Client)) {
    Stop-WithMessage 'ไม่พบ OpenAI tunnel-client กรุณารัน Setup ใหม่อีกครั้ง'
}

# Serena location recorded at install time, with discovery as a fallback so that
# a machine whose uv bin directory differs still starts correctly.
$SerenaExe = '__SERENA_EXE__'
if (-not (Test-Path -LiteralPath $SerenaExe)) {
    $found = $null
    foreach ($candidate in @(
        (Join-Path $env:USERPROFILE '.local\bin\serena.exe'),
        (Join-Path $HOME '.local\bin\serena.exe'),
        (Join-Path $env:APPDATA 'Python\Scripts\serena.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $found = $candidate; break }
    }
    if (-not $found) {
        $cmd = Get-Command 'serena' -ErrorAction SilentlyContinue
        if ($cmd) { $found = $cmd.Source }
    }
    if (-not $found) { Stop-WithMessage 'ไม่พบ Serena ในเครื่อง กรุณารัน Setup ใหม่อีกครั้ง' }
    $SerenaExe = $found
}

$SerenaBin = Split-Path -Parent $SerenaExe
$env:PATH = "$SerenaBin;$env:PATH"

. $ConfigPath

$encryptedKey = (Get-Content -LiteralPath $SecretPath -Raw).Trim()
try { $secureKey = ConvertTo-SecureString -String $encryptedKey }
catch { Stop-WithMessage 'ถอดรหัส API Key ไม่สำเร็จ - ไฟล์นี้ใช้ได้เฉพาะกับ Windows user ที่ติดตั้งไว้เท่านั้น กรุณารัน Setup ใหม่ด้วยผู้ใช้คนเดิม' }
$keyPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $env:CONTROL_PLANE_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPtr) }

# The config lives inside the install folder and is passed with --config, so the
# tunnel does not depend on where tunnel-client happens to look for named
# profiles.  That location changes with HOME / XDG_CONFIG_HOME / APPDATA, which
# silently broke startup on machines where HOME is set.
$profilePath = Join-Path $ConfigDir 'tunnel-client.yaml'

# The control plane drops a command - and with it the whole MCP session - once
# it has been in flight for roughly 143 seconds.  Serena's own tool timeout
# defaults to 240s, so a hung tool used to outlive the tunnel and take it down.
# Keeping Serena below the tunnel deadline turns that into an ordinary "tool
# timed out" answer that ChatGPT can read and work around.
$serenaArgs = '--context chatgpt --tool-timeout 90'

# Optional: put a Serena project name in config\project.txt and Serena activates
# it on every start, so a reconnect does not come back with "No active project".
# tunnel-client re-splits this command string before Serena sees it, and its
# quoting rules are not worth betting a Windows path on, so only a value without
# whitespace is passed through - which is what a project name always is.
$projectFile = Join-Path $ConfigDir 'project.txt'
if (Test-Path -LiteralPath $projectFile) {
    $projectName = (Get-Content -LiteralPath $projectFile -Raw).Trim()
    if ($projectName -match '\s') {
        Write-Host ('  ข้าม project.txt: ค่ามีช่องว่าง ให้ใส่ "ชื่อโปรเจกต์" แทน path เต็ม') -ForegroundColor Yellow
    }
    elseif ($projectName) {
        $serenaArgs += ' --project ' + $projectName
    }
}

@"
config_version: 1
control_plane:
  base_url: "https://api.openai.com"
  tunnel_id: "$TunnelId"
  api_key: "env:CONTROL_PLANE_API_KEY"
health:
  listen_addr: 127.0.0.1:18010
admin_ui:
  open_browser: false
log:
  level: info
  format: json
mcp:
  commands:
    - channel: main
      command: serena start-mcp-server $serenaArgs
"@ | Set-Content -LiteralPath $profilePath -Encoding utf8

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '   Happy Study - DWB Serena Tunnel' -ForegroundColor Cyan
Write-Host '   by อ.คฑาวุฐ' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ("  Tunnel : " + $TunnelId)
Write-Host  '  Serena : ' -NoNewline; Write-Host $SerenaExe
Write-Host  '  Health : http://127.0.0.1:18010/ui'
Write-Host ''
Write-Host '  เปิดหน้าต่างนี้ค้างไว้ขณะใช้งาน ChatGPT' -ForegroundColor Yellow
Write-Host '  ปิดหน้าต่างนี้ = ตัดการเชื่อมต่อ' -ForegroundColor Yellow
Write-Host '  ถ้าการเชื่อมต่อหลุด ระบบจะเชื่อมต่อใหม่ให้เองอัตโนมัติ' -ForegroundColor Gray
Write-Host ''

# tunnel-client exits non-zero when the control plane tears down the MCP
# session mid-flight - most often because a tool call outlived the per-command
# response_timeout, which closes the stdio child and takes the only routable
# channel with it.  That is recoverable, so reconnect instead of making the user
# reopen Start.bat.  A client that dies straight after starting is a real
# misconfiguration (bad key, port in use), so that case still stops with the
# error on screen.
$restarts    = 0
$maxRestarts = 20

while ($true) {
    $startedAt = Get-Date
    & $Client run --config $profilePath
    $clientExit  = $LASTEXITCODE
    $ranSeconds  = ((Get-Date) - $startedAt).TotalSeconds

    Write-Host ''
    if ($clientExit -eq 0) { break }

    if ($ranSeconds -lt 20) {
        Stop-WithMessage ("tunnel-client หยุดทำงานด้วยรหัส " + $clientExit + " ทันทีหลังเริ่มทำงาน (ข้อความ error อยู่ด้านบน)")
    }

    # A tunnel that held up for a long stretch before dropping is not a crash
    # loop, so it does not eat into the reconnect budget.
    if ($ranSeconds -gt 600) { $restarts = 0 }

    $restarts++
    if ($restarts -gt $maxRestarts) {
        Stop-WithMessage ("tunnel-client หยุดทำงานด้วยรหัส " + $clientExit + " และเชื่อมต่อใหม่ครบ " + $maxRestarts + " ครั้งแล้ว (ข้อความ error อยู่ด้านบน)")
    }

    Write-Host ("  การเชื่อมต่อหลุด (รหัส " + $clientExit + ") - กำลังเชื่อมต่อใหม่ ครั้งที่ " + $restarts + "/" + $maxRestarts) -ForegroundColor Yellow
    Write-Host '  ไม่ต้องปิดหน้าต่างนี้ ระบบจะกลับมาใช้งานได้เองใน 5 วินาที' -ForegroundColor Gray
    Write-Host '  ถ้าเพิ่งสั่งงานที่ใช้เวลานานมาก (เช่น pip install) ให้สั่งใหม่อีกครั้งหลังเชื่อมต่อสำเร็จ' -ForegroundColor Gray
    Write-Host ''
    Start-Sleep -Seconds 5
}

Write-Host 'Tunnel หยุดทำงานแล้ว' -ForegroundColor Yellow
Write-Host 'กด Enter เพื่อปิดหน้าต่างนี้' -ForegroundColor Gray
[void](Read-Host)
'@

    $startScriptContent = $startScriptContent.Replace('__SERENA_EXE__', $SerenaExe.Replace("'", "''"))
    Set-Content -LiteralPath $startScript -Value $startScriptContent -Encoding UTF8

    $startBatch = Join-Path $TargetDir 'Start.bat'
    $batchContent = @'
@echo off
setlocal
cd /d "%~dp0"
title Happy Study - DWB Serena Tunnel
set PYTHONHOME=
set PYTHONPATH=
set PYTHONEXECUTABLE=
set VIRTUAL_ENV=
set CONDA_PREFIX=
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
if errorlevel 1 pause
'@
    Set-Content -LiteralPath $startBatch -Value $batchContent -Encoding ASCII
    return $startBatch
}

function Create-DesktopShortcut([string]$TargetDir) {
    Set-Status 'กำลังสร้าง Shortcut บน Desktop...' 86
    $startBatch = Join-Path $TargetDir 'Start.bat'
    if (-not (Test-Path $startBatch)) { throw "ไม่พบ Start.bat ที่ $startBatch" }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'Happy Study - DWB Serena Tunnel.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $startBatch
    $shortcut.WorkingDirectory = $TargetDir
    $shortcut.Description = 'Happy Study - DWB Serena Tunnel by อ.คฑาวุฐ'
    $shortcut.Save()
}

function Start-And-Test([string]$TargetDir) {
    # Returns a status object instead of throwing: by this point everything is
    # already installed, so a health-check problem must not be reported as a
    # failed installation.
    Set-Status 'กำลังเปิด Tunnel เพื่อทดสอบ...' 92
    $startBatch = Join-Path $TargetDir 'Start.bat'
    if (-not (Test-Path -LiteralPath $startBatch)) { throw "ไม่พบ Start.bat ที่ $startBatch" }

    $existingListener = Get-NetTCPConnection -LocalPort 18010 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingListener) {
        $existingProcess = Get-Process -Id $existingListener.OwningProcess -ErrorAction SilentlyContinue
        $processName = 'unknown'
        if ($existingProcess) { $processName = $existingProcess.ProcessName }
        return [PSCustomObject]@{ Status = 'PortBusy'; Detail = "$processName (PID $($existingListener.OwningProcess))" }
    }

    $proc = Start-Process -FilePath $startBatch -WorkingDirectory $TargetDir -PassThru

    $healthUrl = 'http://127.0.0.1:18010/ui'
    $deadline = (Get-Date).AddSeconds(60)

    while ((Get-Date) -lt $deadline) {
        Pump-UI
        Start-Sleep -Milliseconds 700

        if ($proc -and $proc.HasExited) {
            return [PSCustomObject]@{ Status = 'Crashed'; Detail = "รหัส $($proc.ExitCode)" }
        }
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 2
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
                return [PSCustomObject]@{ Status = 'Ok'; Detail = $healthUrl }
            }
        }
        catch { }
    }
    return [PSCustomObject]@{ Status = 'Timeout'; Detail = '60 วินาที' }
}

# ================================================================== the UI ====

$form = New-Object System.Windows.Forms.Form
$form.Text = "$BrandTitle - DWB Serena Tunnel Setup"
$form.ClientSize = New-Object System.Drawing.Size(700, 700)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Font 9.75

# ---- header band ----
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(700, 112)
$header.BackColor = $ColHeader
$form.Controls.Add($header)

$accent = New-Object System.Windows.Forms.Panel
$accent.Location = New-Object System.Drawing.Point(0, 108)
$accent.Size = New-Object System.Drawing.Size(700, 4)
$accent.BackColor = $ColGo
$form.Controls.Add($accent)

$hTitle = New-Object System.Windows.Forms.Label
$hTitle.Text = $BrandTitle
$hTitle.Font = New-Font 25 'Bold'
$hTitle.ForeColor = [System.Drawing.Color]::White
$hTitle.BackColor = [System.Drawing.Color]::Transparent
$hTitle.AutoSize = $true
$hTitle.Location = New-Object System.Drawing.Point(30, 20)
$header.Controls.Add($hTitle)

$hAuthor = New-Object System.Windows.Forms.Label
$hAuthor.Text = $BrandAuthor
$hAuthor.Font = New-Font 12
$hAuthor.ForeColor = [System.Drawing.Color]::FromArgb(198, 235, 226)
$hAuthor.BackColor = [System.Drawing.Color]::Transparent
$hAuthor.AutoSize = $true
$hAuthor.Location = New-Object System.Drawing.Point(34, 66)
$header.Controls.Add($hAuthor)

$hRight = New-Object System.Windows.Forms.Label
$hRight.Text = "DWB Serena Tunnel`r`nติดตั้งอัตโนมัติ"
$hRight.Font = New-Font 9.5
$hRight.ForeColor = [System.Drawing.Color]::FromArgb(198, 235, 226)
$hRight.BackColor = [System.Drawing.Color]::Transparent
$hRight.TextAlign = 'MiddleRight'
$hRight.Size = New-Object System.Drawing.Size(220, 44)
$hRight.Location = New-Object System.Drawing.Point(444, 40)
$header.Controls.Add($hRight)

# ---- settings summary card ----
$card = New-Object System.Windows.Forms.Panel
$card.Location = New-Object System.Drawing.Point(28, 134)
$card.Size = New-Object System.Drawing.Size(644, 128)
$card.BackColor = $ColCard
$form.Controls.Add($card)
$card.Add_Paint({
    $pen = New-Object System.Drawing.Pen($ColLine, 1)
    $_.Graphics.DrawRectangle($pen, 0, 0, $card.Width - 1, $card.Height - 1)
    $pen.Dispose()
})

$cardHead = New-Object System.Windows.Forms.Label
$cardHead.Text = 'การตั้งค่าที่เตรียมไว้ให้แล้ว'
$cardHead.Font = New-Font 10 'Bold'
$cardHead.ForeColor = $ColText
$cardHead.BackColor = [System.Drawing.Color]::Transparent
$cardHead.AutoSize = $true
$cardHead.Location = New-Object System.Drawing.Point(16, 12)
$card.Controls.Add($cardHead)

$editLink = New-Object System.Windows.Forms.LinkLabel
$editLink.Text = 'แก้ไข'
$editLink.Font = New-Font 9.5
$editLink.AutoSize = $true
$editLink.LinkColor = $ColRun
$editLink.BackColor = [System.Drawing.Color]::Transparent
$editLink.Location = New-Object System.Drawing.Point(586, 13)
$card.Controls.Add($editLink)

function New-CardRow([int]$Y, [string]$Caption) {
    $lab = New-Object System.Windows.Forms.Label
    $lab.Text = $Caption
    $lab.Font = New-Font 9.25
    $lab.ForeColor = $ColMuted
    $lab.BackColor = [System.Drawing.Color]::Transparent
    $lab.AutoSize = $true
    $lab.Location = New-Object System.Drawing.Point(16, $Y)
    $card.Controls.Add($lab)

    $val = New-Object System.Windows.Forms.Label
    $val.Font = New-Font 9.25
    $val.ForeColor = $ColText
    $val.BackColor = [System.Drawing.Color]::Transparent
    $val.AutoEllipsis = $true
    $val.Size = New-Object System.Drawing.Size(500, 18)
    $val.Location = New-Object System.Drawing.Point(112, $Y)
    $card.Controls.Add($val)
    return $val
}

$valFolder = New-CardRow 40 'โฟลเดอร์'
$valTunnel = New-CardRow 62 'Tunnel ID'
$valKey    = New-CardRow 84 'API Key'
$valBundle = New-CardRow 106 'tunnel-client'

# ---- the one button ----
$install = New-Object System.Windows.Forms.Button
$install.Text = 'เริ่มติดตั้งอัตโนมัติ'
$install.Size = New-Object System.Drawing.Size(644, 62)
$install.Location = New-Object System.Drawing.Point(28, 280)
$install.Font = New-Font 14 'Bold'
$install.BackColor = $ColGo
$install.ForeColor = [System.Drawing.Color]::White
$install.FlatStyle = 'Flat'
$install.FlatAppearance.BorderSize = 0
$install.FlatAppearance.MouseOverBackColor = $ColGoHot
$install.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($install)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = 'กดปุ่มเดียว ระบบจะติดตั้ง Python, uv, Serena และเปิด Tunnel ให้อัตโนมัติ'
$hint.Font = New-Font 9.25
$hint.ForeColor = $ColMuted
$hint.AutoSize = $true
$hint.Location = New-Object System.Drawing.Point(30, 350)
$form.Controls.Add($hint)

# ---- progress ----
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(28, 376)
$progress.Size = New-Object System.Drawing.Size(644, 16)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'พร้อมติดตั้ง'
$status.Font = New-Font 10 'Bold'
$status.ForeColor = $ColText
$status.AutoEllipsis = $true
$status.Size = New-Object System.Drawing.Size(644, 22)
$status.Location = New-Object System.Drawing.Point(28, 402)
$form.Controls.Add($status)

# ---- step checklist ----
$StepNames = @(
    'เตรียมโฟลเดอร์ติดตั้ง',
    'ติดตั้ง uv',
    'ติดตั้ง Python 3.13',
    'ติดตั้ง Serena',
    'ติดตั้ง OpenAI tunnel-client',
    'บันทึกและเข้ารหัส API Key',
    'สร้างไฟล์เริ่มใช้งานและ Shortcut',
    'ทดสอบการเชื่อมต่อ'
)

$StepLabels = @()
for ($i = 0; $i -lt $StepNames.Count; $i++) {
    $sl = New-Object System.Windows.Forms.Label
    $sl.Font = New-Font 9.75
    $sl.AutoSize = $true
    $sl.ForeColor = $ColMuted
    $sl.Text = '○  ' + $StepNames[$i]
    $sl.Location = New-Object System.Drawing.Point(32, (434 + ($i * 23)))
    $form.Controls.Add($sl)
    $StepLabels += $sl
}

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "$BrandTitle $BrandAuthor"
$footer.Font = New-Font 9.5 'Bold'
$footer.ForeColor = $ColMuted
$footer.AutoSize = $true
$footer.Location = New-Object System.Drawing.Point(30, 636)
$form.Controls.Add($footer)

$verLab = New-Object System.Windows.Forms.Label
$verLab.Text = 'DWB Serena Tunnel Setup'
$verLab.Font = New-Font 9
$verLab.ForeColor = [System.Drawing.Color]::FromArgb(170, 178, 184)
$verLab.TextAlign = 'MiddleRight'
$verLab.Size = New-Object System.Drawing.Size(300, 18)
$verLab.Location = New-Object System.Drawing.Point(372, 637)
$form.Controls.Add($verLab)

# ------------------------------------------------------------ UI helpers ----

function Set-Step([int]$Index, [string]$State) {
    if ($Index -lt 0 -or $Index -ge $StepLabels.Count) { return }
    $lab = $StepLabels[$Index]
    switch ($State) {
        'run'  { $lab.Text = '▶  ' + $StepNames[$Index]; $lab.ForeColor = $ColRun;   $lab.Font = New-Font 9.75 'Bold' }
        'done' { $lab.Text = '✓  ' + $StepNames[$Index]; $lab.ForeColor = $ColOk;    $lab.Font = New-Font 9.75 }
        'warn' { $lab.Text = '!  ' + $StepNames[$Index]; $lab.ForeColor = $ColWarn;  $lab.Font = New-Font 9.75 }
        'fail' { $lab.Text = '✕  ' + $StepNames[$Index]; $lab.ForeColor = $ColBad;   $lab.Font = New-Font 9.75 'Bold' }
        default{ $lab.Text = '○  ' + $StepNames[$Index]; $lab.ForeColor = $ColMuted; $lab.Font = New-Font 9.75 }
    }
    Pump-UI
}

function Reset-Steps {
    for ($i = 0; $i -lt $StepLabels.Count; $i++) { Set-Step $i 'pending' }
}

function Mask-Secret([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '— ยังไม่ได้ตั้งค่า —' }
    if ($Value.Length -le 14) { return ('*' * $Value.Length) }
    return ($Value.Substring(0, 8) + ('*' * 10) + $Value.Substring($Value.Length - 4))
}

function Update-Card {
    if ([string]::IsNullOrWhiteSpace($script:CfgFolder)) { $valFolder.Text = '— ยังไม่ได้ตั้งค่า —' } else { $valFolder.Text = $script:CfgFolder }
    if ([string]::IsNullOrWhiteSpace($script:CfgTunnel)) { $valTunnel.Text = '— ยังไม่ได้ตั้งค่า —' } else { $valTunnel.Text = $script:CfgTunnel }
    $valKey.Text = Mask-Secret $script:CfgKey

    # Work out up front where tunnel-client will come from, so a problem shows
    # now rather than after several minutes of installing uv, Python and Serena.
    $script:BundlePath = Find-TunnelClientBundle
    $script:CanGetBundle = $true
    if ($script:BundlePath) {
        $valBundle.Text = '✓ พบในชุดติดตั้ง'
        $valBundle.ForeColor = $ColOk
    }
    elseif (Find-CachedTunnelClient) {
        $valBundle.Text = '✓ มีที่ดาวน์โหลดเก็บไว้แล้ว'
        $valBundle.ForeColor = $ColOk
    }
    elseif (Get-TunnelClientDownloadUrl) {
        $valBundle.Text = '↓ จะดาวน์โหลดอัตโนมัติ'
        $valBundle.ForeColor = $ColRun
    }
    else {
        $valBundle.Text = '✕ ไม่พบ และยังไม่ได้ตั้งลิงก์ดาวน์โหลดใน .env'
        $valBundle.ForeColor = $ColBad
        $script:CanGetBundle = $false
    }

    $ready = -not ([string]::IsNullOrWhiteSpace($script:CfgFolder) -or
                   [string]::IsNullOrWhiteSpace($script:CfgTunnel) -or
                   [string]::IsNullOrWhiteSpace($script:CfgKey))

    if (-not $script:CanGetBundle) {
        $cardHead.Text = 'ยังติดตั้งไม่ได้  —  ไม่พบ tunnel-client'
        $cardHead.ForeColor = $ColBad
        $install.BackColor = [System.Drawing.Color]::FromArgb(150, 160, 165)
        $install.Text = 'ยังติดตั้งไม่ได้'
        $status.Text = 'คัดลอกโฟลเดอร์ Setup มาไม่ครบ กดปุ่มเพื่อดูวิธีแก้'
        $status.ForeColor = $ColBad
    }
    elseif ($ready) {
        $cardHead.Text = 'การตั้งค่าที่เตรียมไว้ให้แล้ว  ✓ พร้อมติดตั้ง'
        $cardHead.ForeColor = $ColOk
        $install.BackColor = $ColGo
        $install.Text = 'เริ่มติดตั้งอัตโนมัติ'
        $status.Text = 'พร้อมติดตั้ง'
        $status.ForeColor = $ColText
    }
    else {
        $cardHead.Text = 'การตั้งค่า  —  ยังไม่ครบ กรุณากด "แก้ไข"'
        $cardHead.ForeColor = $ColBad
        $install.BackColor = $ColGo
        $install.Text = 'เริ่มติดตั้งอัตโนมัติ'
    }
    Pump-UI
}

function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'แก้ไขการตั้งค่า'
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 306)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::White
    $dlg.Font = New-Font 9.75

    function New-DlgLabel([string]$Text, [int]$Y) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Text
        $l.Font = New-Font 9.75 'Bold'
        $l.ForeColor = $ColText
        $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point(24, $Y)
        $dlg.Controls.Add($l)
    }

    New-DlgLabel 'โฟลเดอร์ติดตั้ง' 20
    $fBox = New-Object System.Windows.Forms.TextBox
    $fBox.Size = New-Object System.Drawing.Size(410, 26)
    $fBox.Location = New-Object System.Drawing.Point(24, 44)
    $fBox.Text = $script:CfgFolder
    $dlg.Controls.Add($fBox)

    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = 'เลือก...'
    $browse.Size = New-Object System.Drawing.Size(90, 26)
    $browse.Location = New-Object System.Drawing.Point(444, 43)
    $browse.FlatStyle = 'Flat'
    $dlg.Controls.Add($browse)
    $browse.Add_Click({
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fd.Description = 'เลือกโฟลเดอร์สำหรับติดตั้ง'
        if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $fBox.Text = Join-Path $fd.SelectedPath 'DWB Serena Tunnel'
        }
    })

    New-DlgLabel 'Tunnel ID' 84
    $tBox = New-Object System.Windows.Forms.TextBox
    $tBox.Size = New-Object System.Drawing.Size(510, 26)
    $tBox.Location = New-Object System.Drawing.Point(24, 108)
    $tBox.Text = $script:CfgTunnel
    $dlg.Controls.Add($tBox)

    New-DlgLabel 'OpenAI API Key' 148
    $kBox = New-Object System.Windows.Forms.TextBox
    $kBox.Size = New-Object System.Drawing.Size(510, 26)
    $kBox.Location = New-Object System.Drawing.Point(24, 172)
    $kBox.UseSystemPasswordChar = $true
    $kBox.Text = $script:CfgKey
    $dlg.Controls.Add($kBox)

    $showKey = New-Object System.Windows.Forms.CheckBox
    $showKey.Text = 'แสดง API Key'
    $showKey.AutoSize = $true
    $showKey.Location = New-Object System.Drawing.Point(24, 204)
    $dlg.Controls.Add($showKey)
    $showKey.Add_CheckedChanged({ $kBox.UseSystemPasswordChar = -not $showKey.Checked })

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = 'บันทึก'
    $okBtn.Size = New-Object System.Drawing.Size(120, 36)
    $okBtn.Location = New-Object System.Drawing.Point(414, 250)
    $okBtn.BackColor = $ColGo
    $okBtn.ForeColor = [System.Drawing.Color]::White
    $okBtn.FlatStyle = 'Flat'
    $okBtn.FlatAppearance.BorderSize = 0
    $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($okBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'ยกเลิก'
    $cancelBtn.Size = New-Object System.Drawing.Size(100, 36)
    $cancelBtn.Location = New-Object System.Drawing.Point(304, 250)
    $cancelBtn.FlatStyle = 'Flat'
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancelBtn)

    $dlg.AcceptButton = $okBtn
    $dlg.CancelButton = $cancelBtn

    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:CfgFolder = $fBox.Text.Trim()
        $script:CfgTunnel = $tBox.Text.Trim()
        $script:CfgKey    = $kBox.Text.Trim()
        Update-Card
    }
    $dlg.Dispose()
}

# ------------------------------------------------- initial configuration ----

$script:CfgFolder = $DefaultInstall
$script:CfgTunnel = ''
$script:CfgKey    = ''

$envCfg = Get-ExistingEnvConfiguration
if (-not [string]::IsNullOrWhiteSpace($TunnelId))       { $script:CfgTunnel = $TunnelId.Trim() }
elseif (-not [string]::IsNullOrWhiteSpace($envCfg.TunnelId)) { $script:CfgTunnel = $envCfg.TunnelId }

if (-not [string]::IsNullOrWhiteSpace($ApiKey))         { $script:CfgKey = $ApiKey.Trim() }
elseif (-not [string]::IsNullOrWhiteSpace($envCfg.ApiKey))   { $script:CfgKey = $envCfg.ApiKey }

Update-Card

$editLink.Add_LinkClicked({ Show-SettingsDialog })

# -------------------------------------------------------------- the run ----

$script:CurrentStep = -1

$install.Add_Click({

    # Fail fast: never start installing uv/Python/Serena when the bundle that
    # step 5 needs is not present.
    if (-not $script:CanGetBundle) {
        $here = $PSScriptRoot
        [System.Windows.Forms.MessageBox]::Show(
            ("ยังติดตั้งไม่ได้ เพราะหา tunnel-client ไม่เจอ`r`n`r`n" +
             "โฟลเดอร์ที่กำลังรันอยู่ตอนนี้:`r`n   $here`r`n`r`n" +
             "แก้ได้ 2 วิธี เลือกอย่างใดอย่างหนึ่ง`r`n`r`n" +
             "วิธีที่ 1 (แนะนำ) ให้ดาวน์โหลดอัตโนมัติ`r`n" +
             "   เปิดไฟล์ .env ด้วย Notepad แล้วเพิ่มบรรทัดนี้`r`n`r`n" +
             "      tunnel client url : https://ลิงก์ไฟล์ zip ของคุณ`r`n`r`n" +
             "   ไฟล์ zip ต้องมี tunnel-client.exe อยู่ข้างใน`r`n" +
             "   และต้องกดโหลดได้ทันทีโดยไม่ต้องล็อกอิน`r`n" +
             "   ดาวน์โหลดครั้งเดียว ครั้งต่อไปใช้ของที่เก็บไว้`r`n`r`n" +
             "วิธีที่ 2 วางไฟล์เอง`r`n" +
             "   วางโฟลเดอร์ tunnel-client ไว้ในโฟลเดอร์ Setup`r`n" +
             "   ให้มี Setup\tunnel-client\tunnel-client.exe"),
            'ยังติดตั้งไม่ได้', 'OK', 'Error') | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($script:CfgFolder) -or
        [string]::IsNullOrWhiteSpace($script:CfgTunnel) -or
        [string]::IsNullOrWhiteSpace($script:CfgKey)) {
        [System.Windows.Forms.MessageBox]::Show(
            "ข้อมูลการตั้งค่ายังไม่ครบ`r`n`r`nกรุณากด ""แก้ไข"" เพื่อกรอกโฟลเดอร์ติดตั้ง, Tunnel ID และ OpenAI API Key ให้ครบก่อน",
            'Happy Study Setup', 'OK', 'Warning') | Out-Null
        Show-SettingsDialog
        return
    }

    $install.Enabled = $false
    $editLink.Enabled = $false
    $install.Text = 'กำลังติดตั้ง...'
    $install.BackColor = [System.Drawing.Color]::FromArgb(150, 160, 165)
    $status.ForeColor = $ColText
    Reset-Steps
    Pump-UI

    $targetDir = $script:CfgFolder
    $ok = $false

    try {
        $script:CurrentStep = 0; Set-Step 0 'run'
        Prepare-InstallationFolder $targetDir
        Set-Step 0 'done'

        $script:CurrentStep = 1; Set-Step 1 'run'
        $uv = Ensure-Uv
        Set-Step 1 'done'

        $script:CurrentStep = 2; Set-Step 2 'run'
        $py = Ensure-Python313 $uv
        Set-Step 2 'done'

        $script:CurrentStep = 3; Set-Step 3 'run'
        $serena = Ensure-Serena $uv $py
        Set-Step 3 'done'

        $script:CurrentStep = 4; Set-Step 4 'run'
        Install-TunnelClient $targetDir
        Set-Step 4 'done'

        $script:CurrentStep = 5; Set-Step 5 'run'
        Save-SecureConfiguration $targetDir $script:CfgTunnel $script:CfgKey
        Set-Step 5 'done'

        $script:CurrentStep = 6; Set-Step 6 'run'
        [void](Create-StartFiles $targetDir $serena)
        Create-DesktopShortcut $targetDir
        Set-Step 6 'done'

        $script:CurrentStep = 7; Set-Step 7 'run'
        $test = Start-And-Test $targetDir

        switch ($test.Status) {
            'Ok' {
                Set-Step 7 'done'
                Set-Status 'ติดตั้งและทดสอบสำเร็จ พร้อมใช้งาน' 100
                $status.ForeColor = $ColOk
                $ok = $true
                Start-Process 'http://127.0.0.1:18010/ui' | Out-Null
                [System.Windows.Forms.MessageBox]::Show(
                    ("ติดตั้งสำเร็จ และทดสอบการเชื่อมต่อผ่านแล้ว`r`n`r`n" +
                     "ตำแหน่งติดตั้ง: $targetDir`r`n" +
                     "Shortcut อยู่บน Desktop แล้ว`r`n`r`n" +
                     "หน้าต่าง Tunnel สีดำที่เปิดอยู่ ห้ามปิด`r`nถ้าปิด = ตัดการเชื่อมต่อกับ ChatGPT"),
                    'Happy Study Setup', 'OK', 'Information') | Out-Null
            }
            'PortBusy' {
                Set-Step 7 'warn'
                Set-Status 'ติดตั้งสำเร็จ (ข้ามการทดสอบ เพราะ Tunnel เปิดอยู่แล้ว)' 100
                $status.ForeColor = $ColWarn
                $ok = $true
                [System.Windows.Forms.MessageBox]::Show(
                    ("ติดตั้งสำเร็จแล้ว`r`n`r`n" +
                     "ข้ามขั้นตอนทดสอบ เพราะพอร์ต 18010 กำลังถูกใช้งานโดย $($test.Detail)`r`n" +
                     "แปลว่ามี Tunnel เปิดค้างอยู่แล้ว ซึ่งไม่ใช่ปัญหา`r`n`r`n" +
                     "ถ้าต้องการใช้ค่าใหม่ ให้ปิดหน้าต่าง Tunnel เดิม แล้วเปิดจาก Shortcut บน Desktop"),
                    'Happy Study Setup', 'OK', 'Information') | Out-Null
            }
            'Crashed' {
                Set-Step 7 'fail'
                Set-Status 'ติดตั้งเสร็จ แต่ Tunnel เปิดไม่สำเร็จ' 100
                $status.ForeColor = $ColBad
                [System.Windows.Forms.MessageBox]::Show(
                    ("ติดตั้งไฟล์ครบแล้ว แต่ Tunnel ปิดตัวเองทันที ($($test.Detail))`r`n`r`n" +
                     "หน้าต่างสีดำจะค้างไว้พร้อมข้อความ error`r`nกรุณาถ่ายรูปหน้าจอนั้นส่งให้ผู้ดูแลระบบ`r`n`r`n" +
                     "สาเหตุที่พบบ่อยคือ API Key หรือ Tunnel ID ไม่ถูกต้อง"),
                    'Happy Study Setup', 'OK', 'Warning') | Out-Null
            }
            default {
                Set-Step 7 'warn'
                Set-Status 'ติดตั้งเสร็จ แต่ทดสอบไม่ตอบกลับ' 100
                $status.ForeColor = $ColWarn
                [System.Windows.Forms.MessageBox]::Show(
                    ("ติดตั้งไฟล์ครบแล้ว แต่ยังไม่ได้รับการตอบกลับภายใน $($test.Detail)`r`n`r`n" +
                     "กรุณาดูหน้าต่าง Tunnel สีดำที่เปิดอยู่`r`nถ้ามีข้อความ error กรุณาถ่ายรูปส่งให้ผู้ดูแลระบบ"),
                    'Happy Study Setup', 'OK', 'Warning') | Out-Null
            }
        }
    }
    catch {
        if ($script:CurrentStep -ge 0) { Set-Step $script:CurrentStep 'fail' }
        Set-Status 'ติดตั้งไม่สำเร็จ' $progress.Value
        $status.ForeColor = $ColBad
        [System.Windows.Forms.MessageBox]::Show(
            ("เกิดข้อผิดพลาดในขั้นตอน: $($StepNames[[Math]::Max(0,$script:CurrentStep)])`r`n`r`n" +
             "$($_.Exception.Message)"),
            'Happy Study Setup', 'OK', 'Error') | Out-Null
    }
    finally {
        $editLink.Enabled = $true
        $install.Enabled = $true
        if ($ok) {
            $install.Text = 'ติดตั้งอีกครั้ง'
            $install.BackColor = $ColHeader2
        } else {
            $install.Text = 'ลองติดตั้งอีกครั้ง'
            $install.BackColor = $ColGo
        }
        Pump-UI
    }
})

[void]$form.ShowDialog()
