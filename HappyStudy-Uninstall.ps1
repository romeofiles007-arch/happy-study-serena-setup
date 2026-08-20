Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'

$BrandTitle  = 'Happy Study'
$BrandAuthor = 'by อ.คฑาวุฐ'

$DefaultInstall = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Happy Study\DWB Serena Tunnel'
$ShortcutPath   = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Happy Study - DWB Serena Tunnel.lnk'
$ProfilePath    = Join-Path $env:APPDATA 'tunnel-client\happy-study-serena.yaml'
$SerenaHome     = Join-Path $env:USERPROFILE '.serena'

$ColHeader = [System.Drawing.Color]::FromArgb(17, 109, 97)
$ColAccent = [System.Drawing.Color]::FromArgb(22, 155, 88)
$ColDanger = [System.Drawing.Color]::FromArgb(178, 40, 40)
$ColDangHot= [System.Drawing.Color]::FromArgb(200, 52, 52)
$ColCard   = [System.Drawing.Color]::FromArgb(246, 248, 249)
$ColLine   = [System.Drawing.Color]::FromArgb(222, 228, 230)
$ColText   = [System.Drawing.Color]::FromArgb(33, 37, 41)
$ColMuted  = [System.Drawing.Color]::FromArgb(112, 121, 128)
$ColOk     = [System.Drawing.Color]::FromArgb(22, 140, 80)
$ColWarn   = [System.Drawing.Color]::FromArgb(176, 122, 12)

function New-Font([single]$Size, [string]$Style = 'Regular') {
    New-Object System.Drawing.Font('Segoe UI', $Size, [System.Drawing.FontStyle]::$Style)
}

function Pump-UI { [System.Windows.Forms.Application]::DoEvents() }

# ============================================================== helpers =======

function Invoke-Native {
    # Same guard as the installer: uv writes to stderr, and under
    # $ErrorActionPreference='Stop' a 2>&1 redirect would turn that into a
    # terminating error before the exit code can be read.
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
    catch { $lines = @($_.Exception.Message); $exitCode = -1 }
    finally { $ErrorActionPreference = $previous }
    if ($null -eq $lines) { $lines = @() }
    return [PSCustomObject]@{ ExitCode = $exitCode; Text = (($lines -join "`r`n").Trim()) }
}

function Get-PathSize([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer) { return $item.Length }
        return (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object Length -Sum).Sum
    } catch { return $null }
}

function Format-Size($Bytes) {
    if ($null -eq $Bytes) { return '(ไม่พบ)' }
    if ($Bytes -lt 1MB) { return ('({0:N0} KB)' -f ($Bytes / 1KB)) }
    return ('({0:N1} MB)' -f ($Bytes / 1MB))
}

function Find-InstalledFolder {
    # Prefer the folder the Desktop shortcut points at, then the default path.
    if (Test-Path -LiteralPath $ShortcutPath) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $sc = $shell.CreateShortcut($ShortcutPath)
            $wd = $sc.WorkingDirectory
            if ($wd -and (Test-Path -LiteralPath $wd)) { return $wd }
        } catch { }
    }
    if (Test-Path -LiteralPath $DefaultInstall) { return $DefaultInstall }
    return ''
}

function Test-LooksLikeInstall([string]$Path) {
    # Refuse to delete a folder that is not one of ours.
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    foreach ($marker in @('start.ps1', 'config\api-key.dpapi', 'config\team.ps1', 'tunnel-client\tunnel-client.exe')) {
        if (Test-Path -LiteralPath (Join-Path $Path $marker)) { return $true }
    }
    return $false
}

function Get-UvPath {
    foreach ($dir in @((Join-Path $env:USERPROFILE '.local\bin'), (Join-Path $HOME '.local\bin'))) {
        $candidate = Join-Path $dir 'uv.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $cmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# ================================================================== UI ========

$form = New-Object System.Windows.Forms.Form
$form.Text = "$BrandTitle - ถอนการติดตั้ง"
$form.ClientSize = New-Object System.Drawing.Size(720, 742)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Font 9.75

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(720, 104)
$header.BackColor = $ColHeader
$form.Controls.Add($header)

$accent = New-Object System.Windows.Forms.Panel
$accent.Location = New-Object System.Drawing.Point(0, 104)
$accent.Size = New-Object System.Drawing.Size(720, 4)
$accent.BackColor = $ColDanger
$form.Controls.Add($accent)

$hTitle = New-Object System.Windows.Forms.Label
$hTitle.Text = $BrandTitle
$hTitle.Font = New-Font 23 'Bold'
$hTitle.ForeColor = [System.Drawing.Color]::White
$hTitle.BackColor = [System.Drawing.Color]::Transparent
$hTitle.AutoSize = $true
$hTitle.Location = New-Object System.Drawing.Point(30, 18)
$header.Controls.Add($hTitle)

$hAuthor = New-Object System.Windows.Forms.Label
$hAuthor.Text = $BrandAuthor
$hAuthor.Font = New-Font 11.5
$hAuthor.ForeColor = [System.Drawing.Color]::FromArgb(198, 235, 226)
$hAuthor.BackColor = [System.Drawing.Color]::Transparent
$hAuthor.AutoSize = $true
$hAuthor.Location = New-Object System.Drawing.Point(33, 60)
$header.Controls.Add($hAuthor)

$hRight = New-Object System.Windows.Forms.Label
$hRight.Text = "ถอนการติดตั้ง`r`nเลือกสิ่งที่ต้องการลบ"
$hRight.Font = New-Font 9.5
$hRight.ForeColor = [System.Drawing.Color]::FromArgb(198, 235, 226)
$hRight.BackColor = [System.Drawing.Color]::Transparent
$hRight.TextAlign = 'MiddleRight'
$hRight.Size = New-Object System.Drawing.Size(240, 42)
$hRight.Location = New-Object System.Drawing.Point(444, 36)
$header.Controls.Add($hRight)

# ---- install folder card ----
$card = New-Object System.Windows.Forms.Panel
$card.Location = New-Object System.Drawing.Point(28, 124)
$card.Size = New-Object System.Drawing.Size(664, 66)
$card.BackColor = $ColCard
$form.Controls.Add($card)
$card.Add_Paint({
    $pen = New-Object System.Drawing.Pen($ColLine, 1)
    $_.Graphics.DrawRectangle($pen, 0, 0, $card.Width - 1, $card.Height - 1)
    $pen.Dispose()
})

$cardHead = New-Object System.Windows.Forms.Label
$cardHead.Text = 'โฟลเดอร์ที่ติดตั้งไว้'
$cardHead.Font = New-Font 9.75 'Bold'
$cardHead.ForeColor = $ColText
$cardHead.BackColor = [System.Drawing.Color]::Transparent
$cardHead.AutoSize = $true
$cardHead.Location = New-Object System.Drawing.Point(14, 10)
$card.Controls.Add($cardHead)

$folderVal = New-Object System.Windows.Forms.Label
$folderVal.Font = New-Font 9.25
$folderVal.ForeColor = $ColText
$folderVal.BackColor = [System.Drawing.Color]::Transparent
$folderVal.AutoEllipsis = $true
$folderVal.Size = New-Object System.Drawing.Size(530, 20)
$folderVal.Location = New-Object System.Drawing.Point(14, 34)
$card.Controls.Add($folderVal)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'เลือก...'
$browse.Size = New-Object System.Drawing.Size(88, 26)
$browse.Location = New-Object System.Drawing.Point(560, 28)
$browse.FlatStyle = 'Flat'
$card.Controls.Add($browse)

function New-GroupLabel([string]$Text, [int]$Y, $Color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Font = New-Font 9.75 'Bold'
    $l.ForeColor = $Color
    $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point(30, $Y)
    $form.Controls.Add($l)
    return $l
}

function New-Check([string]$Text, [int]$Y, [bool]$Checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Font = New-Font 9.75
    $c.AutoSize = $true
    $c.Checked = $Checked
    $c.Location = New-Object System.Drawing.Point(40, $Y)
    $form.Controls.Add($c)
    return $c
}

[void](New-GroupLabel 'กลุ่ม 1 - เฉพาะโปรแกรมนี้ (ปลอดภัย ติ๊กไว้ให้แล้ว)' 202 $ColOk)
$chkProc     = New-Check 'หยุดโปรแกรมที่กำลังทำงาน (tunnel-client, serena)' 226 $true
$chkFolder   = New-Check 'ลบโฟลเดอร์ที่ติดตั้งไว้' 250 $true
$chkShortcut = New-Check 'ลบ Shortcut บน Desktop' 274 $true
$chkProfile  = New-Check 'ลบไฟล์ตั้งค่า tunnel-client (happy-study-serena.yaml)' 298 $true

[void](New-GroupLabel 'กลุ่ม 2 - สำหรับทดสอบติดตั้งใหม่ตั้งแต่ศูนย์ (ต้องติ๊กเอง)' 332 $ColWarn)
$chkSerena   = New-Check 'ถอน Serena ออกจาก uv (uv tool uninstall serena-agent)' 356 $false
$chkPython   = New-Check 'ถอน Python 3.13 ที่ uv ติดตั้ง (ตัวอื่นไม่ถูกแตะ)' 380 $false
$chkUv       = New-Check 'ถอน uv ทั้งหมด (uv.exe, uvx.exe และโฟลเดอร์ข้อมูล uv)' 404 $false

[void](New-GroupLabel 'กลุ่ม 3 - อันตราย จะลบข้อมูลผู้ใช้ (ไม่จำเป็นสำหรับการทดสอบ)' 438 $ColDanger)
$chkSerenaHome = New-Check 'ลบ .serena ทั้งโฟลเดอร์ (projects, memories, language servers)' 462 $false
$chkSerenaHome.ForeColor = $ColDanger

$note = New-Object System.Windows.Forms.Label
$note.Text = "หมายเหตุ: claude.exe (Claude Code) อยู่ในโฟลเดอร์เดียวกับ uv แต่จะไม่ถูกลบ`r`nตัวถอนนี้ลบเฉพาะไฟล์ที่ระบุไว้เท่านั้น ไม่ลบทั้งโฟลเดอร์"
$note.Font = New-Font 8.75
$note.ForeColor = $ColMuted
$note.AutoSize = $true
$note.Location = New-Object System.Drawing.Point(40, 492)
$form.Controls.Add($note)

$go = New-Object System.Windows.Forms.Button
$go.Text = 'ลบรายการที่เลือก'
$go.Size = New-Object System.Drawing.Size(664, 50)
$go.Location = New-Object System.Drawing.Point(28, 536)
$go.Font = New-Font 13 'Bold'
$go.BackColor = $ColDanger
$go.ForeColor = [System.Drawing.Color]::White
$go.FlatStyle = 'Flat'
$go.FlatAppearance.BorderSize = 0
$go.FlatAppearance.MouseOverBackColor = $ColDangHot
$go.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($go)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(28, 596)
$progress.Size = New-Object System.Drawing.Size(664, 14)
$form.Controls.Add($progress)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(28, 618)
$logBox.Size = New-Object System.Drawing.Size(664, 88)
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.BackColor = [System.Drawing.Color]::FromArgb(250, 251, 252)
$logBox.Font = New-Object System.Drawing.Font('Consolas', 8.75)
$form.Controls.Add($logBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "$BrandTitle $BrandAuthor"
$footer.Font = New-Font 9.5 'Bold'
$footer.ForeColor = $ColMuted
$footer.AutoSize = $true
$footer.Location = New-Object System.Drawing.Point(30, 714)
$form.Controls.Add($footer)

# ---------------------------------------------------------------- logic ------

function Log([string]$Message) {
    $logBox.AppendText($Message + "`r`n")
    Pump-UI
}

$script:InstallDir = Find-InstalledFolder

function Update-Labels {
    if ([string]::IsNullOrWhiteSpace($script:InstallDir)) {
        $folderVal.Text = '— ไม่พบโฟลเดอร์ติดตั้ง —'
        $folderVal.ForeColor = $ColMuted
    } else {
        $folderVal.Text = $script:InstallDir
        if (Test-LooksLikeInstall $script:InstallDir) { $folderVal.ForeColor = $ColText }
        else { $folderVal.ForeColor = $ColDanger }
    }

    $chkFolder.Text   = 'ลบโฟลเดอร์ที่ติดตั้งไว้ ' + (Format-Size (Get-PathSize $script:InstallDir))
    $chkShortcut.Text = 'ลบ Shortcut บน Desktop ' + $(if (Test-Path -LiteralPath $ShortcutPath) { '' } else { '(ไม่พบ)' })
    $chkProfile.Text  = 'ลบไฟล์ตั้งค่า tunnel-client ' + $(if (Test-Path -LiteralPath $ProfilePath) { '' } else { '(ไม่พบ)' })
    $chkSerenaHome.Text = 'ลบ .serena ทั้งโฟลเดอร์ ' + (Format-Size (Get-PathSize $SerenaHome))

    $uv = Get-UvPath
    if ($uv) {
        $uvBytes = (Get-PathSize $uv)
        foreach ($d in @((Join-Path $env:APPDATA 'uv'), (Join-Path $env:LOCALAPPDATA 'uv'))) {
            $s = Get-PathSize $d
            if ($s) { $uvBytes += $s }
        }
        $chkUv.Text = 'ถอน uv ทั้งหมด (uv.exe, uvx.exe และโฟลเดอร์ข้อมูล uv) ' + (Format-Size $uvBytes)
    } else {
        $chkUv.Text = 'ถอน uv ทั้งหมด (ไม่พบ uv)'
        $chkUv.Enabled = $false
        $chkSerena.Enabled = $false
        $chkPython.Enabled = $false
    }
    Pump-UI
}

Update-Labels

$browse.Add_Click({
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = 'เลือกโฟลเดอร์ที่ติดตั้ง Happy Study - DWB Serena Tunnel'
    if ($script:InstallDir) { $fd.SelectedPath = $script:InstallDir }
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:InstallDir = $fd.SelectedPath
        Update-Labels
    }
})

function Stop-TunnelProcesses {
    $stopped = 0
    foreach ($name in @('tunnel-client', 'cloudflared', 'serena')) {
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $stopped++; Log "   หยุด $name (PID $($p.Id))" } catch { }
        }
    }
    # Anything still tied to the install folder keeps it locked: the shell waiting
    # on the Start.bat error prompt (path appears in its command line) and any
    # executable running from inside the folder (path appears in ExecutablePath).
    if ($script:InstallDir) {
        $dir = $script:InstallDir.TrimEnd('\')
        foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
                    $_.ProcessId -ne $PID -and (
                        ($_.CommandLine     -and $_.CommandLine     -like "*$dir*") -or
                        ($_.ExecutablePath  -and $_.ExecutablePath  -like "$dir\*")
                    )
                })) {
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $stopped++; Log "   หยุด $($p.Name) (PID $($p.ProcessId))" } catch { }
        }
    }
    if ($stopped -eq 0) { Log '   ไม่มีโปรแกรมที่ต้องหยุด' }
    Start-Sleep -Milliseconds 1200
}

function Remove-PathSafely([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        Log "   ข้าม $Label (ไม่พบ)"
        return
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Log "   ลบแล้ว: $Label"
            return
        }
        catch {
            if ($attempt -eq 3) {
                Log "   ลบไม่สำเร็จ: $Label"
                if ($_.Exception.Message -like '*being used by another process*' -or
                    $_.Exception.Message -like '*ถูกใช้งาน*') {
                    Log '      สาเหตุ: มีโปรแกรมเปิดไฟล์นี้ค้างอยู่'
                    Log '      วิธีแก้: ปิดหน้าต่าง Tunnel สีดำ และหน้าต่าง Explorer ที่เปิดโฟลเดอร์นี้'
                    Log '              แล้วกด "ลบรายการที่เลือก" อีกครั้ง'
                } else {
                    Log "      $($_.Exception.Message)"
                }
                return
            }
            Start-Sleep -Milliseconds 900
        }
    }
}

$go.Add_Click({

    $plan = @()
    if ($chkProc.Checked)       { $plan += 'หยุดโปรแกรมที่กำลังทำงาน' }
    if ($chkFolder.Checked)     { $plan += "ลบโฟลเดอร์: $($script:InstallDir)" }
    if ($chkShortcut.Checked)   { $plan += 'ลบ Shortcut บน Desktop' }
    if ($chkProfile.Checked)    { $plan += 'ลบไฟล์ตั้งค่า tunnel-client' }
    if ($chkSerena.Checked)     { $plan += 'ถอน Serena ออกจาก uv' }
    if ($chkPython.Checked)     { $plan += 'ถอน Python 3.13 ที่ uv ติดตั้ง' }
    if ($chkUv.Checked)         { $plan += 'ถอน uv ทั้งหมด' }
    if ($chkSerenaHome.Checked) { $plan += 'ลบโฟลเดอร์ .serena ทั้งหมด (ข้อมูลผู้ใช้)' }

    if ($plan.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('ยังไม่ได้เลือกรายการที่จะลบ', 'ถอนการติดตั้ง', 'OK', 'Warning') | Out-Null
        return
    }

    if ($chkFolder.Checked) {
        if ([string]::IsNullOrWhiteSpace($script:InstallDir) -or -not (Test-Path -LiteralPath $script:InstallDir)) {
            [System.Windows.Forms.MessageBox]::Show('ไม่พบโฟลเดอร์ติดตั้ง กรุณากด "เลือก..." เพื่อระบุเอง หรือเอาเครื่องหมายถูกออก',
                'ถอนการติดตั้ง', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not (Test-LooksLikeInstall $script:InstallDir)) {
            [System.Windows.Forms.MessageBox]::Show(
                ("โฟลเดอร์นี้ไม่ใช่โฟลเดอร์ติดตั้งของ Happy Study`r`n`r`n$($script:InstallDir)`r`n`r`n" +
                 "เพื่อความปลอดภัย จะไม่ลบให้`r`nกรุณากด ""เลือก..."" เพื่อระบุโฟลเดอร์ที่ถูกต้อง"),
                'ถอนการติดตั้ง', 'OK', 'Error') | Out-Null
            return
        }
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        ("รายการที่จะถูกลบ:`r`n`r`n - " + ($plan -join "`r`n - ") + "`r`n`r`nยืนยันหรือไม่"),
        'ยืนยันการถอนการติดตั้ง', 'YesNo', 'Warning')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    if ($chkSerenaHome.Checked) {
        $c2 = [System.Windows.Forms.MessageBox]::Show(
            ("ยืนยันอีกครั้ง`r`n`r`nกำลังจะลบ $SerenaHome ทั้งโฟลเดอร์`r`n" +
             "ซึ่งมี projects, memories และ language servers ของ Serena ทั้งหมด`r`n`r`n" +
             "การทดสอบติดตั้งใหม่ไม่จำเป็นต้องลบส่วนนี้`r`nยืนยันจะลบจริงหรือไม่"),
            'คำเตือน - ลบข้อมูลผู้ใช้', 'YesNo', 'Error')
        if ($c2 -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $go.Enabled = $false
    $browse.Enabled = $false
    $logBox.Clear()
    $progress.Value = 0
    $total = $plan.Count
    $done = 0

    function Advance { $script:doneCount++; $progress.Value = [Math]::Min(100, [int](100 * $script:doneCount / $total)); Pump-UI }
    $script:doneCount = 0

    try {
        if ($chkProc.Checked) {
            Log 'หยุดโปรแกรมที่กำลังทำงาน...'
            Stop-TunnelProcesses
            Advance
        }
        if ($chkFolder.Checked) {
            Log 'ลบโฟลเดอร์ติดตั้ง...'
            Remove-PathSafely $script:InstallDir 'โฟลเดอร์ติดตั้ง'
            Advance
        }
        if ($chkShortcut.Checked) {
            Log 'ลบ Shortcut...'
            Remove-PathSafely $ShortcutPath 'Shortcut บน Desktop'
            Advance
        }
        if ($chkProfile.Checked) {
            Log 'ลบไฟล์ตั้งค่า tunnel-client...'
            Remove-PathSafely $ProfilePath 'happy-study-serena.yaml'
            Advance
        }

        $uv = Get-UvPath

        if ($chkSerena.Checked) {
            Log 'ถอน Serena...'
            if ($uv) {
                $r = Invoke-Native $uv @('tool', 'uninstall', 'serena-agent')
                if ($r.ExitCode -eq 0) { Log '   ถอน serena-agent แล้ว' }
                else { Log "   ถอนไม่สำเร็จ (รหัส $($r.ExitCode)): $($r.Text)" }
            } else { Log '   ข้าม (ไม่พบ uv)' }
            Advance
        }

        if ($chkPython.Checked) {
            Log 'ถอน Python 3.13 ที่ uv ติดตั้ง...'
            if ($uv) {
                $r = Invoke-Native $uv @('python', 'uninstall', '3.13')
                if ($r.ExitCode -eq 0) { Log '   ถอน Python 3.13 แล้ว' }
                else { Log "   ถอนไม่สำเร็จ (รหัส $($r.ExitCode)): $($r.Text)" }
            } else { Log '   ข้าม (ไม่พบ uv)' }
            Advance
        }

        if ($chkUv.Checked) {
            Log 'ถอน uv...'
            foreach ($dir in @((Join-Path $env:USERPROFILE '.local\bin'), (Join-Path $HOME '.local\bin')) | Select-Object -Unique) {
                foreach ($exe in @('uv.exe', 'uvx.exe', 'uvw.exe')) {
                    $p = Join-Path $dir $exe
                    if (Test-Path -LiteralPath $p) { Remove-PathSafely $p $exe }
                }
            }
            Remove-PathSafely (Join-Path $env:APPDATA 'uv')      'ข้อมูล uv (Roaming)'
            Remove-PathSafely (Join-Path $env:LOCALAPPDATA 'uv') 'ข้อมูล uv (Local)'
            Log '   หมายเหตุ: claude.exe และไฟล์อื่นในโฟลเดอร์เดิมไม่ถูกแตะ'
            Advance
        }

        if ($chkSerenaHome.Checked) {
            Log 'ลบโฟลเดอร์ .serena...'
            Remove-PathSafely $SerenaHome '.serena'
            Advance
        }

        $progress.Value = 100
        Log ''
        Log 'เสร็จสิ้น'
        [System.Windows.Forms.MessageBox]::Show(
            "ถอนการติดตั้งเสร็จแล้ว`r`n`r`nดูรายละเอียดในกล่องข้อความด้านล่าง`r`nตอนนี้สามารถทดสอบติดตั้งใหม่ได้",
            'ถอนการติดตั้ง', 'OK', 'Information') | Out-Null
    }
    catch {
        Log "เกิดข้อผิดพลาด: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("เกิดข้อผิดพลาด:`r`n`r`n$($_.Exception.Message)",
            'ถอนการติดตั้ง', 'OK', 'Error') | Out-Null
    }
    finally {
        $go.Enabled = $true
        $browse.Enabled = $true
        $script:InstallDir = Find-InstalledFolder
        Update-Labels
        Pump-UI
    }
})

[void]$form.ShowDialog()
