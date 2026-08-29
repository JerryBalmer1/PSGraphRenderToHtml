#Requires -Version 7.2

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToHtmlUnderTest
    $script:Sample = Join-Path $PSScriptRoot '../docs/samples/sample-graph.json'
    $script:Graph = Get-Content -LiteralPath $script:Sample -Raw | ConvertFrom-Json
    $script:ViewModel = ConvertTo-GraphRenderViewModel -Graph $script:Graph
}

Describe 'ConvertTo-GraphRenderViewModel derives depth, and only here' {

    It 'gives every node a depth' {
        @($script:ViewModel.data.nodes | Where-Object { $null -eq $_.metrics.depth }).Count | Should-Be 0
    }

    It 'puts a root at depth 0 and a three-level chain at 3' {
        $byId = @{}
        foreach ($node in $script:ViewModel.data.nodes) { $byId[$node.id] = $node }
        $byId['repo:services'].metrics.depth | Should-Be 0
        $byId['services:root'].metrics.depth | Should-Be 1
        $byId['services:api'].metrics.depth | Should-Be 2
        $byId['services:api.worker'].metrics.depth | Should-Be 3
    }

    It 'derives depth from the chain rather than reading it' {
        # The claim the contract's additionalProperties:false is protecting. A
        # graph that never stated a depth still gets correct depths, which is
        # only possible if they are computed.
        $graph = Get-ConformingGraph
        $viewModel = ConvertTo-GraphRenderViewModel -Graph $graph
        $byId = @{}
        foreach ($node in $viewModel.data.nodes) { $byId[$node.id] = $node }
        $byId['r'].metrics.depth | Should-Be 0
        $byId['a'].metrics.depth | Should-Be 1
        $byId['b'].metrics.depth | Should-Be 2
    }

    It 'survives a parent chain that is a cycle without hanging' {
        # A cycle is a named violation from Test-ProducerGraph. Here it must
        # merely terminate: one defect, one report.
        $graph = Get-ViolatingGraph -Case 'parent-cycle'
        $viewModel = ConvertTo-GraphRenderViewModel -Graph $graph
        @($viewModel.data.nodes).Count | Should-Be 3
    }
}

Describe 'ConvertTo-GraphRenderViewModel satisfies the render contract' {

    It 'produces a payload valid against PSGraphRender 1.1.0' {
        $render = Get-Module PSGraphRender
        $schema = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $render.Path))) 'contract/viewmodel.schema.json'
        if (-not (Test-Path -LiteralPath $schema)) {
            $schema = Join-Path (Split-Path -Parent $render.Path) 'contract/viewmodel.schema.json'
        }
        Test-Path -LiteralPath $schema | Should-BeTrue

        $valid = ($script:ViewModel | ConvertTo-Json -Depth 20) | Test-Json -SchemaFile $schema -ErrorAction Stop
        $valid | Should-BeTrue
    }

    It 'declares the contract version it was written against' {
        $script:ViewModel.meta.contractVersion | Should-Be '1.1.0'
    }

    It 'never emits containment as a link' {
        # parentId and a contains edge would be two statements of one fact.
        @($script:ViewModel.data.links | Where-Object { $_.kind -eq 'contains' }).Count | Should-Be 0
    }
}

Describe 'ConvertTo-GraphRenderViewModel carries what it must not lose' {

    It 'lists every unresolved reference' {
        @($script:ViewModel.data.unresolved).Count | Should-Be 1
        $script:ViewModel.data.unresolved[0].reason | Should-MatchString 'no scanned repository'
    }

    It 'marks the unresolved link resolution rather than dropping the link' {
        $link = @($script:ViewModel.data.links | Where-Object { $_.target -eq 'services:missing' })
        @($link).Count | Should-Be 1
        $link[0].resolution | Should-Be 'unresolved'
    }

    It 'leaves resolution absent when the producer did not state one' {
        # Absent means NOT STATED in the render contract, and writing a value
        # the producer never gave would be inventing certainty.
        $link = @($script:ViewModel.data.links | Where-Object { $_.source -eq 'services:env' })
        @($link).Count | Should-Be 1
        $link[0].PSObject.Properties['resolution'] | Should-BeNull
    }

    It 'emits a vscode link only for the nodes the map names' {
        $options = New-GraphRenderOptions -EditorLinkMap @{ 'services:api' = 'C:\estate\services\modules\api\main.tf' }
        $viewModel = ConvertTo-GraphRenderViewModel -Graph $script:Graph -Options $options
        $withLink = @($viewModel.data.nodes | Where-Object { $_.PSObject.Properties['editorUri'] })
        @($withLink).Count | Should-Be 1
        $withLink[0].editorUri | Should-Be 'vscode://file/C:/estate/services/modules/api/main.tf'
    }

    It 'counts nodes and edges in stats' {
        $script:ViewModel.meta.stats.NodeCount | Should-Be 15
        $script:ViewModel.meta.stats.EdgeCount | Should-Be 10
        $script:ViewModel.meta.stats.MaxDepth | Should-Be 3
    }
}
