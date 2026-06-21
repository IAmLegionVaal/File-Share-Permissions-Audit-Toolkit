[CmdletBinding()]
param(
    [string]$ShareName,
    [string]$GrantAccount,
    [string]$RevokeAccount,
    [ValidateSet('Read','Change','Full')]
    [string]$AccessRight = 'Change',
    [switch]$RestartServerService,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath = (Join-Path $env:ProgramData 'FileSharePermissionsRepair')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failures = 0
$script:VerificationFailures = 0
$script:Actions = 0

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') { Write-Error 'This tool requires Windows.'; exit 3 }
if (-not ($GrantAccount -or $RevokeAccount -or $RestartServerService)) { Write-Error 'Choose at least one repair action.'; exit 2 }
if (($GrantAccount -or $RevokeAccount) -and [string]::IsNullOrWhiteSpace($ShareName)) { Write-Error '-ShareName is required for access changes.'; exit 2 }
if ($GrantAccount -and $RevokeAccount -and $GrantAccount -eq $RevokeAccount) { Write-Error 'The same account cannot be granted and revoked in one run.'; exit 2 }
if (-not $DryRun -and -not (Test-Administrator)) { Write-Error 'Run from an elevated PowerShell session.'; exit 4 }
Import-Module SmbShare -ErrorAction Stop
$share = $null
if ($ShareName) {
    $share = Get-SmbShare -Name $ShareName -ErrorAction Stop
    if ($share.Special -or $share.Name -in @('ADMIN$','C$','IPC$')) { Write-Error 'Administrative and special shares are not supported.'; exit 2 }
}

$runPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd_HHmmss')
$backupPath = Join-Path $runPath 'backup'
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
$logPath = Join-Path $runPath 'repair.log'
$beforePath = Join-Path $runPath 'before.json'
$afterPath = Join-Path $runPath 'after.json'

function Write-Log([string]$Message) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Tee-Object -FilePath $logPath -Append }
function Invoke-RepairAction([string]$Description,[scriptblock]$Script) {
    $script:Actions++
    Write-Log "ACTION: $Description"
    if ($DryRun) { Write-Log "DRY-RUN: $Description"; return }
    try {
        $result = & $Script 2>&1
        if ($null -ne $result) { $result | Out-String | Add-Content $logPath }
        Write-Log "SUCCESS: $Description"
    } catch {
        $script:Failures++
        Write-Log "FAILED: $Description - $($_.Exception.Message)"
    }
}
function Get-RepairState {
    $currentShare = $null; $access = @(); $ntfs = $null
    if ($ShareName) {
        $currentShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue | Select-Object Name,Path,Description,EncryptData,FolderEnumerationMode,CachingMode,ContinuouslyAvailable
        $access = @(Get-SmbShareAccess -Name $ShareName -ErrorAction SilentlyContinue | Select-Object AccountName,AccessControlType,AccessRight)
        if ($currentShare -and (Test-Path $currentShare.Path)) {
            $acl = Get-Acl $currentShare.Path
            $ntfs = [pscustomobject]@{ Path=$currentShare.Path; Owner=$acl.Owner; Sddl=$acl.Sddl }
        }
    }
    [pscustomobject]@{
        Collected = Get-Date
        Share = $currentShare
        ShareAccess = $access
        NtfsAcl = $ntfs
        ServerService = Get-Service LanmanServer -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType
    }
}

$before = Get-RepairState
$before | ConvertTo-Json -Depth 8 | Set-Content $beforePath -Encoding UTF8
$before | Export-Clixml (Join-Path $backupPath 'share-and-permissions.xml')
if ($share -and (Test-Path $share.Path)) { (Get-Acl $share.Path).Sddl | Set-Content (Join-Path $backupPath 'ntfs-acl.sddl') -Encoding ASCII }

if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'Apply the selected SMB share repairs? Type YES') -cne 'YES') { Write-Log 'Repair cancelled.'; exit 10 }
}

if ($RestartServerService) {
    Invoke-RepairAction 'Restarting the Server service' { Restart-Service LanmanServer -Force; (Get-Service LanmanServer).WaitForStatus('Running',[TimeSpan]::FromSeconds(30)) }
}
if ($GrantAccount) {
    Invoke-RepairAction "Granting $AccessRight share access to $GrantAccount on $ShareName" { Grant-SmbShareAccess -Name $ShareName -AccountName $GrantAccount -AccessRight $AccessRight -Force | Out-Null }
}
if ($RevokeAccount) {
    Invoke-RepairAction "Revoking share access for $RevokeAccount on $ShareName" { Revoke-SmbShareAccess -Name $ShareName -AccountName $RevokeAccount -Force | Out-Null }
}

if (-not $DryRun) { Start-Sleep -Seconds 2 }
Get-RepairState | ConvertTo-Json -Depth 8 | Set-Content $afterPath -Encoding UTF8
if ($GrantAccount) {
    $grant = Get-SmbShareAccess -Name $ShareName -ErrorAction SilentlyContinue | Where-Object { $_.AccountName -eq $GrantAccount -and $_.AccessControlType -eq 'Allow' -and $_.AccessRight -eq $AccessRight }
    if (-not $grant) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: requested share grant is not present.' }
}
if ($RevokeAccount -and (Get-SmbShareAccess -Name $ShareName -ErrorAction SilentlyContinue | Where-Object AccountName -eq $RevokeAccount)) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: revoked account still has share access.' }
if ($RestartServerService -and (Get-Service LanmanServer).Status -ne 'Running') { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: LanmanServer is not running.' }

if ($script:Failures -gt 0) { exit 20 }
if ($script:VerificationFailures -gt 0) { exit 30 }
Write-Log "Repair completed. Actions: $script:Actions"
exit 0
