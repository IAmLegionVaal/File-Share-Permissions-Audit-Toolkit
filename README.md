# File Share Permissions Audit Toolkit

A PowerShell toolkit for reviewing Windows file-share context and applying guarded SMB share-permission repairs.

## Audit mode

The repository's existing inventory and reporting content remains read-only and is intended for storage and share review.

## Repair script

Preview a permission change:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\File_Share_Permissions_Repair_Toolkit.ps1 -ShareName 'Finance' -GrantAccount 'CONTOSO\Finance Users' -AccessRight Change -DryRun
```

Examples:

```powershell
.\File_Share_Permissions_Repair_Toolkit.ps1 -ShareName 'Finance' -GrantAccount 'CONTOSO\Finance Users' -AccessRight Change
.\File_Share_Permissions_Repair_Toolkit.ps1 -ShareName 'Finance' -RevokeAccount 'CONTOSO\Former Contractor'
.\File_Share_Permissions_Repair_Toolkit.ps1 -RestartServerService
```

## Repair behaviour

- Grants one explicit account `Read`, `Change` or `Full` SMB share access.
- Revokes one explicit account's SMB share access.
- Restarts the Windows Server service only when requested.
- Refuses administrative and special shares.
- Captures share properties, share permissions, NTFS ACL evidence and service state before and after repair.
- Exports pre-change share, access and NTFS ACL evidence into the run backup directory.
- Supports `-DryRun`, confirmation prompts or `-Yes`, administrator checks, action logs and post-repair verification.

## Safety and exit codes

SMB share permissions and NTFS permissions are separate layers. This repair changes only the SMB share layer and does not change NTFS ACLs, create or delete shares, or alter share paths. Restarting the Server service can interrupt active SMB sessions.

Exit codes: `0` success, `2` invalid arguments, `3` unsupported platform or feature, `4` elevation required, `10` cancelled, `20` action failure and `30` verification failure.

## Validation note

The repair script was committed and statically reviewed, but it was not runtime-tested on a Windows file server.

## Author

Dewald Pretorius — L2 IT Support Engineer
