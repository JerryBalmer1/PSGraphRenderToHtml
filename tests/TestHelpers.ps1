#Requires -Version 7.2
<#
    Shared by every test file. Pester 6 runs discovery and execution per file,
    so nothing leaks between them and each file dot-sources this itself.
#>

function Import-ToHtmlUnderTest {
    <#
    .SYNOPSIS
        Import the BUILT module when there is one, else the source.
    .DESCRIPTION
        The built psm1 is what ships and what coverage is measured against, so
        it is preferred. Falling back to src lets a test run before a build,
        which is what makes the ordered runner's early layers useful.
    #>
    [CmdletBinding()]
    param()

    $repo = Split-Path -Parent $PSScriptRoot

    # PSGraphRender is a runtime dependency. Resolve it the same way the build
    # does, so a test run and a build agree about which renderer is in play.
    if (-not (Get-Module -Name PSGraphRender)) {
        $renderCandidates = @(
            $env:PSGRAPHRENDER_MODULE_PATH
            (Join-Path (Split-Path -Parent $repo) 'PSGraphRender/output/PSGraphRender/PSGraphRender.psd1')
            (Join-Path (Split-Path -Parent $repo) 'PSGraphRender/src/PSGraphRender/PSGraphRender.psd1')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

        if ($renderCandidates) {
            Import-Module -Name $renderCandidates[0] -Force -ErrorAction Stop
        }
        else {
            Import-Module -Name PSGraphRender -Force -ErrorAction Stop
        }
    }

    $built = Join-Path $repo 'output/PSGraphRenderToHtml/PSGraphRenderToHtml.psd1'
    $source = Join-Path $repo 'src/PSGraphRenderToHtml/PSGraphRenderToHtml.psd1'
    $target = if (Test-Path -LiteralPath $built) { $built } else { $source }

    Import-Module -Name $target -Force -ErrorAction Stop
}

function Get-ConformingGraph {
    <#
    .SYNOPSIS
        A small graph that satisfies the contract, as a mutable hashtable.
    .DESCRIPTION
        Built in memory rather than read from the sample, so a violating case
        can be produced by changing exactly one thing about a graph that is
        otherwise known good. A violation derived from a large file leaves the
        reader guessing which difference mattered.
    #>
    [CmdletBinding()]
    param()

    @{
        graph = @{
            meta  = @{
                producer        = 'PSGraphRenderToHtml.Tests'
                producerVersion = '0.1.0'
                contractVersion = '0.1.0'
            }
            nodes = @(
                @{ id = 'r'; label = 'root'; type = 'repository'; scope = 's' }
                @{ id = 'a'; label = 'a'; type = 'module'; scope = 's'; parentId = 'r' }
                @{ id = 'b'; label = 'b'; type = 'module'; scope = 's'; parentId = 'a' }
            )
            edges = @(
                @{ from = 'a'; to = 'b'; kind = 'sources' }
            )
        }
    }
}

function Get-ViolatingGraph {
    <#
    .SYNOPSIS
        The known-good graph with exactly one thing wrong with it.
    .DESCRIPTION
        Eight cases, one per mechanism the contract is supposed to refuse. Each
        starts from Get-ConformingGraph and changes one thing, so a red result
        names the mechanism rather than a document.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('missing-id', 'duplicate-id', 'dangling-edge', 'parent-cycle',
            'stored-depth', 'unknown-key', 'wrong-type', 'empty-label')]
        [string] $Case
    )

    $graph = Get-ConformingGraph

    switch ($Case) {
        'missing-id' { $graph.graph.nodes[1].Remove('id') }
        'duplicate-id' { $graph.graph.nodes[2]['id'] = 'a' }
        'dangling-edge' { $graph.graph.edges[0]['to'] = 'nope' }
        'parent-cycle' { $graph.graph.nodes[0]['parentId'] = 'b' }
        'stored-depth' { $graph.graph.nodes[1]['depth'] = 1 }
        'unknown-key' { $graph.graph['vertices'] = @() }
        'wrong-type' { $graph.graph.nodes[1]['scope'] = @(1, 2, 3) }
        'empty-label' { $graph.graph.nodes[1]['label'] = '' }
    }

    $graph
}

function Invoke-ResolveOptions {
    <#
    .SYNOPSIS
        Call the module's private Resolve-GraphRenderOptions from a test.
    .DESCRIPTION
        Precedence is a private concern with a public consequence, so it is
        tested directly rather than inferred from a rendered document. Invoked
        in the module's own scope, which is the supported way to reach a
        function the manifest does not export.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [AllowNull()] [object] $Options,
        [Parameter()] [string] $DefaultsRoot
    )

    $module = Get-Module -Name PSGraphRenderToHtml
    & $module { param($o, $r) Resolve-GraphRenderOptions -Options $o -DefaultsRoot $r } $Options $DefaultsRoot
}
