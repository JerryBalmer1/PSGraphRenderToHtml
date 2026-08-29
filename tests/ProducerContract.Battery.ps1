#Requires -Version 7.2
<#
    THE ECOSYSTEM'S ENFORCEMENT POINT.

    This file is the contract between every producer and PSGraphRender, made
    executable. A producer does not "support" the contract because its author
    read the schema; it supports the contract because this battery is green
    against its real output, in its own build, on its own machine.

    Invoke it from a producer's own suite:

        Invoke-Pester -Container (New-PesterContainer `
            -Path <path to this file> `
            -Data @{ GraphPath = './output/graph.json' })

    It is deliberately parameterised on a FILE rather than an object. A producer
    that can hand this a file has serialised its graph, and serialisation is
    where the shapes that only exist in memory - a hashtable that is not a
    string, a date that is not a string - stop being valid and start being
    caught.

    Three layers, in dependency order. A failure in an early one makes the later
    ones meaningless, which is why each states what the previous established.
#>

param(
    [Parameter(Mandatory)]
    [string] $GraphPath,

    # Where PSGraphRenderToHtml is. Defaults to the checkout this file sits in,
    # so the battery works in place; a producer consuming the published module
    # passes its own path or leaves it to PSModulePath.
    [string] $ModulePath = "$PSScriptRoot/../src/PSGraphRenderToHtml/PSGraphRenderToHtml.psd1"
)

BeforeAll {
    $script:GraphPath = $GraphPath
    if (-not (Test-Path -LiteralPath $script:GraphPath)) {
        throw "The battery was pointed at '$script:GraphPath' and there is no such file. A producer that cannot produce a graph file has nothing for this to grade."
    }

    if (Test-Path -LiteralPath $ModulePath) {
        Import-Module $ModulePath -Force
    }
    else {
        Import-Module PSGraphRenderToHtml -Force
    }

    $script:Raw = Get-Content -LiteralPath $script:GraphPath -Raw
    $script:Graph = $script:Raw | ConvertFrom-Json
    $script:Result = Test-ProducerGraph -Path $script:GraphPath
}

Describe 'The graph a producer emits' {

    It 'is valid against the producer contract, with every violation named' {
        # The whole battery rests on this. Everything below assumes a graph
        # whose shape and semantics hold, and would report consequences rather
        # than causes if it did not.
        $detail = ($script:Result.Violations |
                ForEach-Object { "$($_.Path): [$($_.Rule)] $($_.Message)" }) -join '; '
        $script:Result.IsValid | Should-BeTrue -Because "the graph has $($script:Result.Violations.Count) violation(s): $detail"
    }

    It 'is not empty' {
        # A validator passes an empty collection every time. A producer that
        # emits zero nodes against a real source has failed silently, and this
        # is the assertion that says so.
        $script:Result.NodeCount | Should-BeGreaterThan 0
    }

    It 'states its own provenance' {
        # Not schema-required, because a payload written before the field
        # existed must still validate. Required HERE, because a graph nobody
        # can trace back to a producer and a version is a graph nobody can
        # debug six months later.
        $meta = $script:Graph.graph.PSObject.Properties['meta']
        $meta | Should-NotBeNull -Because 'graph.meta carries the producer name and version'
        $script:Graph.graph.meta.producer | Should-NotBeEmptyString
        $script:Graph.graph.meta.producerVersion | Should-NotBeEmptyString
    }

    It 'carries no node that stores its own depth' {
        # additionalProperties:false already refuses this at the schema layer,
        # so this assertion is about the REASON rather than the rule: depth is
        # a function of the parentId chain, and a stored copy is a second
        # source of truth that nothing would notice going stale.
        $offenders = @(
            foreach ($node in $script:Graph.graph.nodes) {
                foreach ($name in $node.PSObject.Properties.Name) {
                    if ($name -match '(?i)depth|level|tier') { "$($node.id).$name" }
                }
            }
        )
        ($offenders -join ', ') | Should-Be '' -Because 'depth is derived in ConvertTo-GraphRenderViewModel and nowhere else'
    }
}

Describe 'The graph converts to something the renderer accepts' {

    It 'maps to a view model that satisfies PSGraphRender contract 1.1.0' {
        # THE conversion smoke, and the reason this battery is worth running
        # rather than just validating the schema. A graph can be perfectly
        # valid against the producer contract and still map to a view model
        # the renderer refuses - that is a defect in THIS module, and a
        # producer running the battery is what finds it.
        $viewModel = ConvertTo-GraphRenderViewModel -Graph $script:Graph
        $json = $viewModel | ConvertTo-Json -Depth 20

        $renderModule = Get-Module PSGraphRender
        if (-not $renderModule) {
            Import-Module PSGraphRender -ErrorAction Stop
            $renderModule = Get-Module PSGraphRender
        }
        $schema = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $renderModule.Path))) 'contract/viewmodel.schema.json'
        if (-not (Test-Path -LiteralPath $schema)) {
            $schema = Join-Path (Split-Path -Parent $renderModule.Path) 'contract/viewmodel.schema.json'
        }

        # A missing schema must fail loudly. Skipping here would report a green
        # battery on the one assertion the battery exists for.
        Test-Path -LiteralPath $schema | Should-BeTrue -Because "the render contract must be findable beside PSGraphRender at $($renderModule.Path)"

        # Called directly, not wrapped. There is no Should-NotThrow in Pester 6,
        # and a try/catch that asserts in the catch passes when the code is
        # broken in a different way. An exception here fails the test on its own.
        $valid = $json | Test-Json -SchemaFile $schema -ErrorAction Stop
        $valid | Should-BeTrue
    }

    It 'derives a depth for every node' {
        $viewModel = ConvertTo-GraphRenderViewModel -Graph $script:Graph
        $missing = @($viewModel.data.nodes | Where-Object { $null -eq $_.metrics.depth })
        @($missing).Count | Should-Be 0 -Because 'a node with no derived depth cannot be placed by a layered layout'
    }

    It 'carries every unresolved reference through rather than dropping it' {
        # A producer that silently drops what it could not resolve reports a
        # graph that looks complete and is not. The count on both sides is the
        # cheapest statement that nothing was lost.
        $declared = @($script:Graph.graph.edges | Where-Object {
                $_.PSObject.Properties['resolved'] -and $_.resolved -eq $false
            })
        $viewModel = ConvertTo-GraphRenderViewModel -Graph $script:Graph
        @($viewModel.data.unresolved).Count | Should-Be @($declared).Count
    }
}
