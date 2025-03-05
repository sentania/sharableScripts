# Aria Operations Batched Metrics Extraction Script

## Overview

This PowerShell script authenticates to a Aria Operations (Aria Ops) instance, retrieves the full resource inventory,
and then performs a batched GET call to query metric statistics for a set of objects. The script accepts two CSV files:
- **Objects CSV:** Contains objects with columns `ObjectName` and `ResourceKind`.
- **Metrics CSV:** Contains metric definitions for each resource kind. The first column must be `ResourceKind`, and
  subsequent columns list the `statKey` values (e.g. `cpu|usage_average`, `mem|workload`) to query.  Additional column headers are allowed, but not required.

## Parameters

- **vROPSUser**: Username for Aria Ops authentication.
- **vROPSpasswd**: Password for Aria Ops authentication.
- **vROPSFQDN**: Fully qualified domain name or IP address of the Aria Ops instance.
- **StartTime**: Start time (DateTime) for the query.
- **EndTime**: End time (DateTime) for the query.
- **RollupInterval**: The rollup interval to use.  
  *Valid values (case-insensitive):* MINUTES, HOURS, SECONDS, DAYS, WEEKS, MONTHS, YEARS  
  **Note:** You must enter one of these exact values. The script will convert your input to uppercase.
- **RollupType**: The rollup type for the query.  
  *Valid values (case-insensitive):* SUM, AVG, MIN, MAX, NONE, LATEST, COUNT  
  **Note:** You must enter one of these exact values.
- **ObjectCsv**: Path to the CSV file containing the objects.
- **MetricsCsv**: Path to the CSV file defining statKeys per resource kind.
- **OutputDirectory**: (Optional) Directory for output CSV files (defaults to the current directory).
- **ignoreSSL**: (Optional) Should the script validate the SSL certifcate (default is $FALSE)

## Usage Example

```powershell
.\Get-vROPsMetrics.ps1 -vROPSUser admin -vROPSpasswd P@ssw0rd -vROPSFQDN operations.example.com `
    -StartTime "2025-02-20T00:00:00" -EndTime "2025-02-20T23:59:59" `
    -RollupInterval MINUTES -RollupType AVG `
    -ObjectCsv "C:\Inputs\objects.csv" -MetricsCsv "C:\Inputs\metrics.csv" `
    -OutputDirectory "C:\Outputs" `
    -ignoreSSL $FALSE
