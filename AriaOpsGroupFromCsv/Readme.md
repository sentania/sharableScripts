# AriaOps Group Management Script

This PowerShell script automates the process of creating and updating groups in Aria Operations (vROPS) using data from CSV files. The script will:
- Authenticate with Aria Ops using provided credentials.
- Retrieve the current resource and group inventories.
- Compare the inventories with the groups and membership information provided in CSV files.
- Create or update groups accordingly. If an object is not listed in the CSV, it will be removed from the group.

## Requirements

- PowerShell 5.1 or later (or PowerShell Core if compatible with your Aria Ops environment).
- Access to a Aria Ops instance with API access enabled.
- Two CSV files:
  - **Groups CSV**: Contains the group name and resource kind key.
  - **Group Membership CSV**: Contains the object name, resource kind, and group name.

## Usage

Run the script from a PowerShell session by providing the required parameters. For example:

```powershell
.\create-CustomAriaOpsGroup.ps1 `
    -vROPSUser "yourUsername" `
    -vROPSpasswd "yourPassword" `
    -vROPSFQDN "vrops.example.com" `
    -groupInputListCsv "C:\path\to\groups.csv" `
    -groupMembershipInputListCsv "C:\path\to\groupMembership.csv" `
    -ignoreSSL $true
