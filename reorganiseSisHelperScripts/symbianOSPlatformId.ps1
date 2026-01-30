param(
    [Parameter(Mandatory=$true)]
    [string]$SisFile
)

if (-not (Test-Path $SisFile)) {
    Write-Error "File not found: $SisFile"
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Pattern for s60 v1, s60 v2, s80 and s90 platforms id
$s60s80s90PlatformPattern = "10 00 00 00 00 00 00 00 00 22 00 00 00"
# Pattern for UIQ platform id
$uiqPlatformPattern = "10 02 00 00 00 00 00 00 00 1C 00 00 00"
# Pattern for UIQ product id. Some old UIQ apps only have product id.
$uiqProductPattern = "10 01 00 00 00 00 00 00 00 42 00 00 00"

# Symbian OS release markers
$epoc6Release = "10003A12"
$symbian9Release = "10201A7A"

# Reduce sis file bytes max length pattern matching for optimization
$searchFirstPercent = 0.20

$bytes = [IO.File]::ReadAllBytes($SisFile)

if ($bytes.Length -lt 8) { 
    Write-Host "0x00000000"
    exit 
}

# Check for Symbian OS 9+ (first 4 bytes)
$firstFourBytes = $bytes[0..3] | ForEach-Object { $_.ToString('X2') }
[Array]::Reverse($firstFourBytes)
$symbian9ReleaseJoined = $firstFourBytes -join ''

# Check for EPOC6 (bytes 4-7)
$epoc6Bytes = $bytes[4..7] | ForEach-Object { $_.ToString('X2') }
[Array]::Reverse($epoc6Bytes)
$epoc6ReleaseJoined = $epoc6Bytes -join ''

# FIRST: Check if it's Symbian OS 9+
if ($symbian9ReleaseJoined -eq $symbian9Release) {
    $sisInfoPath = Join-Path $scriptDir 'sisinfo\sisinfo.exe'
    
    if (Test-Path $sisInfoPath) {
        try {
            $output = & $sisInfoPath -s "--file=$SisFile" 2>$null
            $filteredLines = $output -split "`n" | Where-Object {
                $_ -match 'PrerequisitiesField' -or $_ -match 'UidField 0x'
            }
            
            $uidLines = $filteredLines | Where-Object { $_ -match 'UidField 0x' }
            
            if ($uidLines -and $uidLines.Count -ge 2) {
                $secondUidLine = $uidLines[1]
                $parts = $secondUidLine -split '\s+'
                $uid = $parts[2]
                if ($uid) {
                    Write-Host $uid
                    exit
                }
            }
        }
        catch { }
    }
    
    # If sisinfo didn't return a UID, return the Symbian OS 9 marker
    Write-Host "0x$symbian9ReleaseJoined"
    exit
}

# SECOND: Check if it's EPOC6 (Symbian OS 6/7/8)
if ($epoc6ReleaseJoined -eq $epoc6Release) {
    $patterns = @($s60s80s90PlatformPattern, $uiqPlatformPattern, $uiqProductPattern)
    
    foreach ($patternStr in $patterns) {
        $pattern = $patternStr.Split(' ') | ForEach-Object { [Convert]::ToByte($_, 16) }
        $maxIndex = [Math]::Floor($bytes.Length * $searchFirstPercent) - $pattern.Length
        
        for ($i = 0; $i -le $maxIndex; $i++) {
            $match = $true
            
            for ($j = 0; $j -lt $pattern.Length; $j++) {
                if ($bytes[$i + $j] -ne $pattern[$j]) {
                    $match = $false
                    break
                }
            }
            
            if ($match) {
                $start = [Math]::Max(0, $i - 3)
                $before = $bytes[$start..($i - 1)] | ForEach-Object { $_.ToString('X2') }
                [Array]::Reverse($before)
                $output = '0x10' + ($before -join '')
                Write-Host $output
                exit
            }
        }
    }
    
    # If no pattern matched but it's EPOC6, return the EPOC6 marker
    Write-Host "0x$epoc6ReleaseJoined"
    exit
}

# If neither Symbian OS 9+ nor EPOC6
Write-Host "0x00000000"