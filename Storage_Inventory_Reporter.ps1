#requires -Version 5.1
<#
.SYNOPSIS
    Storage Inventory Reporter.
.DESCRIPTION
    Read-only Windows storage inventory reporter for support review.
#>
[CmdletBinding()]
param([string]$OutputPath)
$RunStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Storage_Inventory_Reports'}
New-Item -Path $OutputPath -ItemType Directory -Force|Out-Null
try{$shares=Get-SmbShare|Select-Object Name,Path,Description,Special;$shares|Export-Csv (Join-Path $OutputPath "share_inventory_$RunStamp.csv") -NoTypeInformation -Encoding UTF8}catch{$shares=@()}
$volumes=Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"|Select-Object DeviceID,VolumeName,FileSystem,Size,FreeSpace
$volumes|Export-Csv (Join-Path $OutputPath "volume_inventory_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$html="<h1>Storage Inventory - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p><h2>Shares</h2>$($shares|ConvertTo-Html -Fragment)<h2>Volumes</h2>$($volumes|ConvertTo-Html -Fragment)"
$html|ConvertTo-Html -Title 'Storage Inventory'|Set-Content (Join-Path $OutputPath "storage_inventory_$RunStamp.html") -Encoding UTF8
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
