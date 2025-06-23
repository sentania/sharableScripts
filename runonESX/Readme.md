# Run-OnEsx.ps1

## Description

`Run-OnEsx.ps1` is a PowerShell Core script that executes a Python script on all ESXi hosts within a vCenter. It handles prerequisites checking, SSH enabling/disabling, secure file transfer, remote execution, and summarizes success/failure for each host.

## Prerequisites

- PowerShell Core 7.0 or higher
- VMware PowerCLI module
- OpenSSH client (`ssh` and `scp`)
- `sshpass` for non-interactive password authentication
- Network connectivity from the machine running this script to the vCenter and ESXi hosts
- Proper credentials for vCenter and ESXi hosts

## Installation

1. Install PowerCLI (if not already installed):
   ```powershell
   Install-Module -Name VMware.PowerCLI
   ```
2. Ensure `ssh`, `scp`, and `sshpass` are installed and in your PATH on the machine running the script.

## Usage

```powershell
$vcUser     = 'administrator@vsphere.local'
$vcPass     = 'YourVcPassword'
$esxiPass   = 'YourEsxiPassword'
$scriptPath = 'C:\path\to\your_script.py'
$params     = '-hp True -ke False'

.\Run-OnEsx.ps1 `
    -vcenterServer vc.example.com `
    -scriptPath $scriptPath `
    -scriptParams $params `
    -vCenterUser $vcUser `
    -vCenterPasswd $vcPass `
    -esxiPass $esxiPass `
    [-remotePath '/tmp/your_script.py'] `
    [-esxiUser root] `
    [-ignoreSSL]
```

## Parameters

- \`\`\
  FQDN or IP address of your vCenter Server.

- \`\`\
  Local path to the Python script to be executed on ESXi hosts.

- \`\` *(optional)*\
  Destination path on ESXi hosts. Default: `/tmp/script.py`.

- \`\` *(optional)*\
  Additional parameters to pass to the Python script.

- \`\`\
  Username for connecting to vCenter.

- \`\`\
  Password for the vCenter user (plaintext; converted internally to a secure string).

- \`\` *(optional)*\
  Username for SSH on ESXi hosts. Default: `root`.

- \`\`\
  Password for SSH on ESXi hosts.

- \`\` *(switch)*\
  Ignore invalid SSL certificates when connecting to vCenter.

## How It Works

1. **Prerequisite Checks**: Verifies you are running PowerShell Core 7+, that VMware.PowerCLI, `ssh`, `scp`, and `sshpass` are installed.
2. **vCenter Connection**: Converts vCenter credentials into a PSCredential and connects to vCenter.
3. **Host Loop**: For each connected ESXi host:
   - Enables the SSH service via PowerCLI.
   - Copies the Python script to the remote host using `scp`.
   - Executes the script via `ssh`, capturing and propagating the Python process’s exit code.
   - Stops the SSH service.
   - Records Success/Failure status and any error messages.
4. **Summary**: After processing all hosts, disconnects from vCenter, resets SSL behavior (if altered), and outputs a summary table of each host’s execution status.

## Example Output

```
=== Summary ===
Host                  Status    Message
----                  ------    -------
esxi01.example.com    Success
esxi02.example.com    Failed    Remote script exited with code 1
...
```

## Notes

- For key-based SSH authentication, you can omit `sshpass` and provide keys in your SSH agent.
- Adjust `-remotePath` if you prefer a different destination directory on ESXi hosts.

