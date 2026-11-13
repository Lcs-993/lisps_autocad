# Empacota menu\src\* em menu\LISPS.cuix (CUIx = pacote ZIP/OPC).
# Uso:  pwsh -File menu\build_cuix.ps1
# Feche o menu no AutoCAD (CUIUNLOAD LISPS) antes de regerar, senao o arquivo fica travado.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$src = Join-Path $PSScriptRoot 'src'
$out = Join-Path $PSScriptRoot 'LISPS.cuix'

# Menu_Package_Info.xml com a data de modificacao de cada parte
$now   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffffffzzz')
$parts = '/Header.cui', '/MenuGroup.cui', '/PopMenuRoot.cui', '/RibbonRoot.cui', '/Menu_Package_Info.xml'
$info  = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<MenuPackageParts>`r`n"
foreach ($p in $parts) { $info += "  <PartData PartData_Name=`"$p`" PartData_Modified=`"$now`" />`r`n" }
$info += "</MenuPackageParts>"
[IO.File]::WriteAllText((Join-Path $src 'Menu_Package_Info.xml'), $info, [Text.UTF8Encoding]::new($true))

if (Test-Path $out) { Remove-Item $out -Force }
$zip = [IO.Compression.ZipFile]::Open($out, 'Create')
try {
    Get-ChildItem $src -Recurse -File -Force | ForEach-Object {
        $entry = $_.FullName.Substring($src.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry)
    }
} finally { $zip.Dispose() }

Write-Host "Gerado: $out"
