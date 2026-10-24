<#
  encoding.ps1 -- HDL / 约束文件编码转换（UTF-8 <-> GBK）

  为什么要这个脚本：
    1) Vivado 的文本编辑器按 Windows 系统 ANSI 解码文件。
       简体中文系统的 ANSI = GBK(CP936)，所以 UTF-8 文件里的中文注释
       在 Vivado 里会显示成乱码（例如 "软件" 变成 "杞欢"）。
    2) HDL 文件不能加 UTF-8 BOM —— 实测 xvlog 会直接报
       "syntax error near 'non-printable character with the hex value 0xef'"。
    3) 所以本工程的 .v / .xdc 统一保存成 GBK：
       - Vivado 编辑器：中文正常
       - 记事本 / Notepad++(ANSI) / Keil：中文正常
       - xsim / xvlog 编译：中文只在注释里，不受影响

  什么时候用它：
    用 Codex / apply_patch 改代码之前，先把文件转成 UTF-8：
        powershell -ExecutionPolicy Bypass -File encoding.ps1 -To utf8
    改完再转回 GBK（交回给 Vivado 看）：
        powershell -ExecutionPolicy Bypass -File encoding.ps1 -To gbk

  默认处理本工程 src 目录（.v / .sv / .vh / .xdc / .tcl），也可用 -Path 指定别的目录。
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet("gbk", "utf8")][string]$To,
    [string]$Path = ""          # 可以是目录，也可以是单个文件；留空则自动找 <工程>\src 或 <工程>\*.srcs
)

$gbk   = [System.Text.Encoding]::GetEncoding(936)                                  # CP936 简体中文 ANSI
$gb18030 = [System.Text.Encoding]::GetEncoding(54936)                              # GBK 的超集，个别生僻字用
$u8str = New-Object System.Text.UTF8Encoding($false, $true)                        # 严格 UTF-8（用来判断）
$u8    = New-Object System.Text.UTF8Encoding($false)                               # UTF-8 无 BOM

$isFile = $false
if ([string]::IsNullOrWhiteSpace($Path)) {
    $proj = Split-Path $PSScriptRoot -Parent
    $cands = @("$proj\src")
    $cands += (Get-ChildItem -LiteralPath $proj -Directory -Filter "*.srcs" -ErrorAction SilentlyContinue |
               ForEach-Object { $_.FullName })
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $Path = $c; break } }
}
if (-not (Test-Path -LiteralPath $Path)) { Write-Host "路径不存在: $Path"; exit 1 }
if ((Get-Item -LiteralPath $Path).PSIsContainer -eq $false) { $isFile = $true; $Path = (Get-Item -LiteralPath $Path).FullName }
$Path = $Path.TrimEnd("\")

$targets = if ($isFile) {
    ,(Get-Item -LiteralPath $Path)
} else {
    Get-ChildItem -LiteralPath $Path -Recurse -File |
        Where-Object { $_.Extension -in @(".v", ".sv", ".vh", ".xdc", ".tcl") }
}

$ok = 0
foreach ($f in $targets) {

    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)

    # 顺手去掉 UTF-8 BOM（Vivado 的 xvlog 不接受 BOM）
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
        [System.IO.File]::WriteAllBytes($f.FullName, $bytes)
        Write-Host ("[去BOM ] " + $f.Name)
    }

    # 纯 ASCII 的文件两种编码一样，跳过
    $nonAscii = $false
    foreach ($x in $bytes) { if ($x -gt 0x7F) { $nonAscii = $true; break } }
    if (-not $nonAscii) { continue }

    $isUtf8 = $true
    try { [void]$u8str.GetString($bytes) } catch { $isUtf8 = $false }

    if ($To -eq "gbk") {
        if (-not $isUtf8) { continue }                       # 已经是 GBK
        $text = $u8str.GetString($bytes)
        $enc  = $gbk
        if ($gbk.GetString($gbk.GetBytes($text)) -ne $text) { $enc = $gb18030 }
        [System.IO.File]::WriteAllBytes($f.FullName, $enc.GetBytes($text))
        Write-Host ("[UTF8->GBK] " + $f.Name)
        $ok++
    }
    else {
        if ($isUtf8) { continue }                            # 已经是 UTF-8
        $text = $gbk.GetString($bytes)
        [System.IO.File]::WriteAllText($f.FullName, $text, $u8)
        Write-Host ("[GBK->UTF8] " + $f.Name)
        $ok++
    }
}

Write-Host ("完成: 处理 $ok 个文件 (目录 $Path)")
