# sharableScripts

A collection of PowerShell scripts designed to automate and streamline various tasks in VMware environments.

## Table of Contents

- [sharableScripts](#sharablescripts)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Repository Structure](#repository-structure)
  - [Prerequisites](#prerequisites)

## Introduction

This repository contains a set of PowerShell scripts aimed at automating tasks within VMware environments, including vRealize Operations (vROps) and VMware Cloud Foundation (VCF). These scripts are intended to simplify operations, enhance efficiency, and reduce manual intervention.

## Repository Structure

The repository is organized as follows:

sharableScripts/
├── AriaOpsGroupFromCsv/
├── OpsDashboards/
├── VCF Aggregator/
├── vRO Packages/
├── vROPS Property/
├── vROPSCost/
├── vROPSGroups/
├── vropsMetrics/
├── affinity-rule-by-tags.ps1
├── fixExpiredEvalLicense.ps1
├── get-vropsReport.ps1
├── serviceCheck.ps1
└── vROPS-custom-group.ps1

- **Directories**: Contain scripts and resources related to specific functionalities or modules.
- **Standalone Scripts**: Individual PowerShell scripts for specific tasks.

## Prerequisites

- **PowerShell**: Ensure you have PowerShell installed on your system. You can download it from the [official PowerShell repository](https://github.com/PowerShell/PowerShell).

- **VMware PowerCLI**: Some scripts may require VMware PowerCLI modules. Install them using:

  ```powershell
  Install-Module -Name VMware.PowerCLI
