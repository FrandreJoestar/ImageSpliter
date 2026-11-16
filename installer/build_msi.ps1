# 构建 Flutter Windows 发布版，补齐 VC++ 运行库，并打包为免依赖的 MSI。
# 用法（在仓库根目录或任意位置执行）：
#   powershell -ExecutionPolicy Bypass -File installer\build_msi.ps1
# 可选：手动指定版本号（默认读取 pubspec.yaml）
#   powershell -ExecutionPolicy Bypass -File installer\build_msi.ps1 -Version 1.0.1

[CmdletBinding()]
param(
    [string]$Version
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$outputDir = Join-Path $repoRoot 'build\windows\installer'
$wxsFile = Join-Path $PSScriptRoot 'ImageSpliter.wxs'

# 运行库：exe 与插件实际依赖这三个 DLL，UCRT 由 Windows 10/11 自带
$runtimeDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

function Get-VersionFromPubspec {
    $line = Get-Content (Join-Path $repoRoot 'pubspec.yaml') |
        Where-Object { $_ -match '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' } |
        Select-Object -First 1
    if (-not $line) { throw '无法从 pubspec.yaml 解析版本号' }
    return [regex]::Match($line, '([0-9]+\.[0-9]+\.[0-9]+)').Groups[1].Value
}

function Get-CrtDirectory {
    $candidates = @()

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) { $candidates += (Join-Path $vsPath 'VC\Redist\MSVC') }
    }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        foreach ($vsRoot in @('Microsoft Visual Studio\2022', 'Microsoft Visual Studio\2019')) {
            $base = Join-Path $root $vsRoot
            if (-not (Test-Path $base)) { continue }
            Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates += (Join-Path $_.FullName 'VC\Redist\MSVC')
            }
        }
    }

    foreach ($redistRoot in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path $redistRoot)) { continue }
        $crt = Get-ChildItem $redistRoot -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($crt) { return $crt }
    }

    throw '未找到 Microsoft.VC143.CRT 目录，请确认已安装 Visual Studio 的 C++ 桌面开发工作负载'
}

if (-not $Version) { $Version = Get-VersionFromPubspec }
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "MSI 版本号必须是 x.y.z 格式，当前为：$Version"
}

Push-Location $repoRoot
try {
    Write-Host '==> flutter build windows --release' -ForegroundColor Cyan
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build 失败' }

    $exe = Join-Path $releaseDir 'imagespliter.exe'
    if (-not (Test-Path $exe)) { throw "未找到构建产物：$exe" }

    Write-Host '==> 拷贝 VC++ 运行库' -ForegroundColor Cyan
    $crtDir = Get-CrtDirectory
    Write-Host "    来源：$crtDir"
    foreach ($dll in $runtimeDlls) {
        Copy-Item (Join-Path $crtDir $dll) -Destination $releaseDir -Force
    }

    Write-Host '==> 生成 MSI' -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $msi = Join-Path $outputDir "ImageSpliter-$Version-x64.msi"
    wix build $wxsFile -arch x64 -d "ReleaseDir=$releaseDir" -d "ProductVersion=$Version" -o $msi
    if ($LASTEXITCODE -ne 0) { throw 'wix build 失败' }

    $size = [math]::Round((Get-Item $msi).Length / 1MB, 2)
    Write-Host "完成：$msi（$size MB）" -ForegroundColor Green
}
finally {
    Pop-Location
}
