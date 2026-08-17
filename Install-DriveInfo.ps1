$scriptDir = "C:\Scripts"
$scriptPath = Join-Path $scriptDir "Check-Drives.ps1"

if (!(Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null
}

$driveInfoScriptContent = @'
$drives = 65..90 | ForEach-Object { [char]$_ }

$pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue

$white255   = "$([char]27)[38;2;255;255;255m"
$resetColor = "$([char]27)[0m"

foreach ($letter in $drives) {
    $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
    if (-not $vol) { continue }
    
    if ($vol.DriveType -match 'CD') { continue }
    
    $driveLabel = if ($letter -eq 'C') { 
        'System' 
    } elseif ($letter -eq 'D') { 
        'Data' 
    } elseif ($vol.FileSystemLabel) { 
        $vol.FileSystemLabel 
    } else { 
        '[No Label]' 
    }
    
    $headerLabel = if ($letter -eq 'C') {
        "[System]"
    } elseif ($letter -eq 'D') {
        "[Data]"
    } else {
        ""
    }
    
    $physicalDisk = $null
    $disk = $null
    $reliability = $null
    $predictStatus = $null
    try {
        $partition = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
        if ($partition) {
            $disk = $partition | Get-Disk -ErrorAction SilentlyContinue
            if ($disk) {
                $physicalDisk = $disk | Get-PhysicalDisk -ErrorAction SilentlyContinue
                if ($physicalDisk) {
                    $reliability = $physicalDisk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                }
            }
        }
    } catch {
    }
    
    $diskDrive = $null
    $logicalDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${letter}:'" -ErrorAction SilentlyContinue
    if ($logicalDisk) {
        $cimPart = Get-CimAssociatedInstance -CimInstance $logicalDisk -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cimPart) {
            $diskDrive = Get-CimAssociatedInstance -CimInstance $cimPart -ResultClassName Win32_DiskDrive -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    }
    
    $win32Vol = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='${letter}:'" -ErrorAction SilentlyContinue
    
    $hasPageFile = $false
    $pageFileSize = "N/A"
    foreach ($pf in $pageFiles) {
        if ($pf.Name -like "${letter}:*") {
            $hasPageFile = $true
            $pageFileSize = "$($pf.AllocatedBaseSize) MB allocated"
            break
        }
    }
    
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " DRIVE: $($vol.DriveLetter):\ $headerLabel" -ForegroundColor White
    Write-Host "==================================================" -ForegroundColor Cyan
    
    Write-Host "${white255}--- VOLUME INFO ---$resetColor"
    $sec1 = ([PSCustomObject]@{
        "File System"        = $vol.FileSystem
        "Drive Label"        = $driveLabel
        "Drive Type"         = $vol.DriveType
        "Total Size"         = if ($vol.Size) { "{0:N2} GB" -f ($vol.Size / 1GB) } else { "N/A" }
        "Free Space"         = if ($vol.SizeRemaining) { "{0:N2} GB" -f ($vol.SizeRemaining / 1GB) } else { "N/A" }
        ">>>>> (%)"               = if ($vol.Size -gt 0) { "{0:P1}" -f ($vol.SizeRemaining / $vol.Size) } else { "N/A" }
        "Operational Status" = $vol.OperationalStatus
    } | Format-List | Out-String).Trim()
    if ($sec1) { Write-Host $sec1 }
    
    Write-Host "${white255}--- CONFIGURATION ---$resetColor"
    $sec2 = ([PSCustomObject]@{
        "Partition Style"      = if ($disk.PartitionStyle) { $disk.PartitionStyle } else { "N/A" }
        "Allocation Unit Size" = if ($win32Vol.BlockSize) { "$($win32Vol.BlockSize) bytes" } elseif ($vol.AllocationUnitSize) { "$($vol.AllocationUnitSize) bytes" } else { "N/A" }
        "Page File Hosting"    = if ($hasPageFile) { "Yes ($pageFileSize)" } else { "No" }
    } | Format-List | Out-String).Trim()
    if ($sec2) { Write-Host $sec2 }
    
    Write-Host "${white255}--- HARDWARE INFO ---$resetColor"
    $sec3 = ([PSCustomObject]@{
        "Disk Model"        = if ($physicalDisk.FriendlyName) { $physicalDisk.FriendlyName.Trim() } elseif ($diskDrive.Model) { $diskDrive.Model.Trim() } else { "N/A" }
        "Media Type"        = if ($physicalDisk.MediaType) { $physicalDisk.MediaType } else { "N/A" }
        "Bus Type"          = if ($physicalDisk.BusType) { $physicalDisk.BusType } elseif ($diskDrive.InterfaceType) { $diskDrive.InterfaceType } else { "N/A" }
        "Firmware Revision" = if ($diskDrive.FirmwareRevision) { $diskDrive.FirmwareRevision.Trim() } else { "N/A" }
        "Serial Number"     = if ($physicalDisk.SerialNumber) { $physicalDisk.SerialNumber.Trim() } elseif ($diskDrive.SerialNumber) { $diskDrive.SerialNumber.Trim() } else { "N/A" }
        "Bytes Per Sector"  = if ($diskDrive.BytesPerSector) { $diskDrive.BytesPerSector } else { "N/A" }
    } | Format-List | Out-String).Trim()
    if ($sec3) { Write-Host $sec3 }
	
    $tempVal    = if ($reliability -and $null -ne $reliability.Temperature) { "$($reliability.Temperature) °C" } else { "N/A (Driver Restricted)" }
    $pwrHours   = if ($reliability -and $null -ne $reliability.PowerOnHours) { "$($reliability.PowerOnHours) hrs" } else { "N/A (Driver Restricted)" }
    $pwrCount   = if ($reliability -and $null -ne $reliability.StartStopCycleCount) { $reliability.StartStopCycleCount } else { "N/A (Driver Restricted)" }

    Write-Host "${white255}--- S.M.A.R.T. INFO ---$resetColor"
    $sec4 = ([PSCustomObject]@{
        "Drive Health"       = if ($physicalDisk.HealthStatus) { $physicalDisk.HealthStatus } else { "N/A" }
        "Temperature"        = $tempVal
        "Power-On Hours"     = $pwrHours
        "Power-On Count"     = $pwrCount
    } | Format-List | Out-String).Trim()
    if ($sec4) { Write-Host $sec4 }
}
'@

Set-Content -Path $scriptPath -Value $driveInfoScriptContent

if (!(Test-Path $PROFILE)) {
    $profileDir = Split-Path $PROFILE -Parent
    if (!(Test-Path $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }
    New-Item -Type File -Force $PROFILE | Out-Null
}

$profileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
$functionDefinition = "`nfunction driveinfo { & `"$scriptPath`" }"

if ($profileContent -notmatch "function driveinfo") {
    Add-Content -Path $PROFILE -Value $functionDefinition
}

. $PROFILE
Write-Host "DriveInfo (v1.03-1) — by MT-96_" -ForegroundColor Cyan