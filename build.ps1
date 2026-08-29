#Requires -Version 7.2
<#
.SYNOPSIS
    Bootstrap and invoke the PSGraphRenderToHtml build.
.PARAMETER Task
    InvokeBuild task name(s). Default: .
#>
[CmdletBinding()]
param([string[]] $Task = '.')

$ErrorActionPreference = 'Stop'

# Resolve rather than install. A build that reaches the gallery on its own can
# change what it is testing between two runs.
foreach ($name in (Import-PowerShellDataFile "$PSScriptRoot/Requirements.psd1").Keys) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        throw "Missing build dependency '$name'. Install it and re-run."
    }
    Import-Module -Name $name -Force
}

try {
    Invoke-Build -Task $Task -File "$PSScriptRoot/PSGraphRenderToHtml.build.ps1"
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
