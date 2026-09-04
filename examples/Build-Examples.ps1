#requires -Version 7.0
<#
.SYNOPSIS
    Regenerates the committed examples under examples/.
.DESCRIPTION
    Run from the repository root. Every row in examples/README.md names the
    exact invocation that rebuilds it, and this script is what those commands
    call.

    The three precedence examples render the SAME graph three ways and differ
    only in where their options came from. That is the whole point of them:
    explicit beats the defaults file beats the built-ins, and each level is a
    whole-key merge rather than a whole-object replacement.

    This module renders no HTML itself - every byte comes from PSGraphRender.
.PARAMETER Only
    Build one example instead of all of them.
.EXAMPLE
    pwsh -NoProfile -File examples/Build-Examples.ps1 -Only explicit
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('all', 'nesting', 'builtins', 'file', 'explicit')]
    [string] $Only = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$examplesRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $examplesRoot
$inputRoot = Join-Path $examplesRoot 'input'

# -- both modules, built output first, source second -------------------------
function Import-Local {
    param([string] $Root, [string] $Name)

    $built = Join-Path $Root "output/$Name/$Name.psd1"
    $source = Join-Path $Root "src/$Name/$Name.psd1"
    $manifest = if (Test-Path -LiteralPath $built) { $built } else { $source }
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw "No $Name manifest found under '$Root'. Run ./build.ps1 there first."
    }
    Import-Module -Name $manifest -Force -ErrorAction Stop
    Get-Module -Name $Name
}

# PSGraphRender is a sibling checkout in the development workspace, and an
# installed module anywhere else. Prefer the sibling so an example always
# renders with the renderer this repository is being developed against.
$sibling = Join-Path (Split-Path -Parent $repoRoot) 'PSGraphRender'
if (Test-Path -LiteralPath $sibling) {
    $render = Import-Local -Root $sibling -Name 'PSGraphRender'
}
else {
    Import-Module -Name 'PSGraphRender' -ErrorAction Stop
    $render = Get-Module -Name 'PSGraphRender'
}
$toHtml = Import-Local -Root $repoRoot -Name 'PSGraphRenderToHtml'

Write-Host "PSGraphRenderToHtml $($toHtml.Version) -> PSGraphRender $($render.Version)"

function Write-Example {
    param([string] $OutFile, [scriptblock] $Render)

    $full = Join-Path $examplesRoot $OutFile
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    & $Render $full
    Write-Host ("  wrote {0} ({1:N0} bytes)" -f $OutFile, (Get-Item $full).Length)
}

$nested = Join-Path $inputRoot 'nested-graph.json'
$precedence = Join-Path $inputRoot 'precedence-graph.json'
$precedenceRoot = Join-Path $examplesRoot 'precedence'

# One colour per classification THIS producer emits. The renderer knows none
# of these words - repository, module, variable, output, provider, local are
# the graph's own vocabulary, and a map naming them is the documented way to
# get colour out of it. Without one every node draws in KindColorFallback,
# which is exactly what precedence/builtins.html shows.
$estateTheme = @{
    KindColor         = @{
        repository = '#3b7fc4'
        module     = '#00a884'
        variable   = '#c98a1e'
        output     = '#b4536b'
        provider   = '#9b8cff'
        local      = '#5f9ea0'
    }
    KindColorFallback = '#8895a7'
    LinkColor         = @{
        references  = '#c9a227'
        'passes-to' = '#4cc9f0'
    }
}

if ($Only -in 'all', 'nesting') {
    Write-Host 'building nesting'
    Write-Example 'nesting/nested.html' {
        param($out)
        Export-ProducerGraphHtml -Path $nested -OutputPath $out -Options (
            New-GraphRenderOptions -Layout foundation -Theme $estateTheme -Title 'Estate - three repositories, nested modules'
        )
    }
}

# -- the three precedence renders -------------------------------------------
# 3. built-ins only. -DefaultsRoot is the graph's own directory, which holds no
#    graphrender.defaults.psd1, so nothing overrides New-GraphRenderOptions.
if ($Only -in 'all', 'builtins') {
    Write-Host 'building builtins'
    Write-Example 'precedence/builtins.html' {
        param($out)
        Export-ProducerGraphHtml -Path $precedence -OutputPath $out
    }
}

# 2. the defaults file. Same graph, same call, one extra argument: the
#    directory holding graphrender.defaults.psd1.
if ($Only -in 'all', 'file') {
    Write-Host 'building file'
    Write-Example 'precedence/file-defaults.html' {
        param($out)
        Export-ProducerGraphHtml -Path $precedence -DefaultsRoot $precedenceRoot -OutputPath $out
    }
}

# 1. explicit options, with the SAME defaults file still in play. Layout and
#    ColorBy come from -Options and beat the file.
#
#    Note what happens to ZoomSpeed, because it is the part that surprises:
#    the file says 2.5 and the rendered document says 1.25. -Options is not a
#    patch, it is a COMPLETE object - New-GraphRenderOptions fills every
#    parameter it was not given with that parameter's default - so an explicit
#    object outranks the file on every key, including the ones the caller
#    never mentioned. The whole-key merge that lets a three-line defaults file
#    work is the merge between the FILE and the built-ins, one level down.
if ($Only -in 'all', 'explicit') {
    Write-Host 'building explicit'
    Write-Example 'precedence/explicit.html' {
        param($out)
        Export-ProducerGraphHtml -Path $precedence -DefaultsRoot $precedenceRoot -OutputPath $out -Options (
            New-GraphRenderOptions -Layout callflow -ColorBy structure -Theme $estateTheme -Title 'Explicit options win'
        )
    }
}

Write-Host 'done.'
