<#
.SYNOPSIS
    把 Quartus 的 .mif 存储器初始化文件转换为 Vivado 的 .coe 文件。

.DESCRIPTION
    支持的 .mif 格式:
        DEPTH = <n>;
        WIDTH = <n>;
        ADDRESS_RADIX = HEX|DEC|BIN|OCT;
        DATA_RADIX    = HEX|DEC|BIN|OCT;
        CONTENT BEGIN
            <addr> : <data>;
            ...
        END;
    输出 .coe 固定使用 16 进制 (memory_initialization_radix=16)。

.EXAMPLE
    powershell -File scripts\mif2coe.ps1 -InputFile ..\Sin_Wave.mif -OutputFile ..\Sin_Wave.coe
#>
param(
    [Parameter(Mandatory = $true)][string]$InputFile,
    [Parameter(Mandatory = $true)][string]$OutputFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputFile)) {
    throw "输入文件不存在: $InputFile"
}

$lines   = Get-Content -LiteralPath $InputFile
$depth   = 0
$inBody  = $false
$entries = New-Object System.Collections.Generic.List[string]

foreach ($raw in $lines) {
    $line = $raw.Trim()
    if ($line -eq '' -or $line.StartsWith('--')) { continue }

    if (-not $inBody) {
        if ($line -match '^DEPTH\s*=\s*(\d+)') { $depth = [int]$Matches[1]; continue }
        if ($line -match '^CONTENT') { $inBody = $true; continue }
        continue
    }

    if ($line -match '^END\s*;?\s*$') { break }

    if ($line -match '^([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;') {
        $entries.Add($Matches[2].ToUpper())
    }
}

if ($depth -le 0) { $depth = $entries.Count }
if ($entries.Count -ne $depth) {
    throw "条目数 ($($entries.Count)) 与 DEPTH ($depth) 不一致: $InputFile"
}

$dir = Split-Path -Parent $OutputFile
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('memory_initialization_radix=16;')
[void]$sb.AppendLine('memory_initialization_vector=')
for ($i = 0; $i -lt $entries.Count; $i++) {
    $sep = if ($i -eq $entries.Count - 1) { ';' } else { ',' }
    [void]$sb.AppendLine($entries[$i] + $sep)
}

Set-Content -LiteralPath $OutputFile -Value $sb.ToString() -Encoding ascii
Write-Output ("{0} -> {1} ({2} entries, WIDTH from file)" -f $InputFile, $OutputFile, $entries.Count)
