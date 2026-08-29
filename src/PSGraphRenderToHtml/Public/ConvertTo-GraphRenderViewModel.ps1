function ConvertTo-GraphRenderViewModel {
    <#
    .SYNOPSIS
        Map a producer graph onto PSGraphRender's view model, contract 1.1.0.
    .DESCRIPTION
        The whole point of this module: a producer states what it found, and
        everything derivable is derived HERE so that no producer has to compute
        it and no two producers compute it differently.

        Derived here and only here:

        - depth, from the parentId chains, into metrics.depth
        - dependents / dependencies, by counting edges
        - the unresolved list, from edges carrying resolved=false
        - stats

        Mapping decisions worth knowing:

        - producer `type` becomes the view model's `kind`. Both are free
          strings neither module enumerates.
        - producer `scope` is carried as a node property and as a metric-free
          classification; the renderer colours by it only if a theme says so.
        - producer `parentId` becomes metrics.depth and a `parentId` property.
          It does NOT become a link: containment is not a relationship the
          graph draws, and emitting it as one would double every node's edges.
        - an edge with resolved=false maps to resolution 'unresolved' AND an
          entry in data.unresolved. The renderer invents a node for each
          unresolved target in its own vocabulary; the edge keeps its endpoints
          so the producer's own record is not rewritten.

        It does not validate the input. Test-ProducerGraph does that, and doing
        it here too would make one bad graph produce two different reports.
    .PARAMETER Graph
        A producer graph conforming to producer-graph.schema.json.
    .PARAMETER Options
        From New-GraphRenderOptions. Defaults are used when omitted.
    .OUTPUTS
        PSCustomObject valid against PSGraphRender's viewmodel.schema.json 1.1.0.
    .EXAMPLE
        $vm = ConvertTo-GraphRenderViewModel -Graph $graph

        Maps with default options.
    .EXAMPLE
        $vm = $graph | ConvertTo-GraphRenderViewModel -Options (New-GraphRenderOptions -Title 'Estate')

        Sets the title carried in meta.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [object] $Graph,

        [Parameter()]
        [object] $Options
    )

    process {
        if (-not $Options) { $Options = New-GraphRenderOptions }

        $nodes = @($Graph.graph.nodes)
        $edges = @($Graph.graph.edges)
        $depth = Get-ProducerGraphDepth -InputNode $nodes

        $dependents = @{}
        $dependencies = @{}
        foreach ($node in $nodes) {
            $dependents[[string]$node.id] = 0
            $dependencies[[string]$node.id] = 0
        }
        foreach ($edge in $edges) {
            $from = [string]$edge.from
            $to = [string]$edge.to
            if ($dependencies.ContainsKey($from)) { $dependencies[$from]++ }
            if ($dependents.ContainsKey($to)) { $dependents[$to]++ }
        }

        $linkMap = $Options.EditorLinkMap
        $vmNodes = foreach ($node in $nodes) {
            $id = [string]$node.id
            $path = [string](Get-ProducerGraphProperty -InputObject $node -Name 'path')
            $attributes = Get-ProducerGraphProperty -InputObject $node -Name 'attributes'

            $metrics = [ordered]@{
                depth        = $depth[$id]
                dependents   = $dependents[$id]
                dependencies = $dependencies[$id]
            }
            # Numeric attributes become metrics; everything else stays a string
            # property. metrics is typed additionalProperties: number in the
            # render contract, so a string here would fail validation for a
            # reason the producer author could not see.
            if ($attributes) {
                foreach ($property in Get-ProducerGraphPropertyName -InputObject $attributes) {
                    $value = Get-ProducerGraphProperty -InputObject $attributes -Name $property
                    if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) {
                        $metrics[$property] = $value
                    }
                }
            }

            $vmNode = [ordered]@{
                id      = $id
                name    = [string]$node.label
                kind    = [string]$node.type
                scope   = [string]$node.scope
                metrics = $metrics
            }

            $parent = [string](Get-ProducerGraphProperty -InputObject $node -Name 'parentId')
            if ($parent) { $vmNode['parentId'] = $parent }
            if ($path) { $vmNode['path'] = $path }

            if ($linkMap -and $linkMap.ContainsKey($id)) {
                # vscode://file/<absolute path>. Forward slashes and no drive
                # colon-escaping: that is the form VS Code accepts on Windows.
                $target = ([string]$linkMap[$id]) -replace '\\', '/'
                $vmNode['editorUri'] = "vscode://file/$target"
            }

            if ($attributes) {
                foreach ($property in Get-ProducerGraphPropertyName -InputObject $attributes) {
                    $value = Get-ProducerGraphProperty -InputObject $attributes -Name $property
                    if (-not ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal])) {
                        $vmNode[$property] = $value
                    }
                }
            }

            [pscustomobject]$vmNode
        }

        $byId = @{}
        foreach ($node in $nodes) { $byId[[string]$node.id] = $node }

        $unresolved = [System.Collections.Generic.List[object]]::new()
        $vmLinks = foreach ($edge in $edges) {
            $from = [string]$edge.from
            $to = [string]$edge.to
            $resolvedFlag = Get-ProducerGraphProperty -InputObject $edge -Name 'resolved'
            $isUnresolved = ($resolvedFlag -is [bool] -and -not $resolvedFlag)

            $link = [ordered]@{
                source = $from
                target = $to
                kind   = [string]$edge.kind
            }
            if ($byId.ContainsKey($from)) { $link['sourceName'] = [string]$byId[$from].label }
            if ($byId.ContainsKey($to)) { $link['targetName'] = [string]$byId[$to].label }

            $edgePath = [string](Get-ProducerGraphProperty -InputObject $edge -Name 'path')
            if ($edgePath) { $link['path'] = $edgePath }

            if ($isUnresolved) {
                # Absent means NOT STATED in the render contract, so this is
                # written only when the producer actually said so.
                $link['resolution'] = 'unresolved'
                $entry = [ordered]@{
                    source     = $from
                    targetName = if ($byId.ContainsKey($to)) { [string]$byId[$to].label } else { $to }
                }
                if ($byId.ContainsKey($from)) { $entry['sourceName'] = [string]$byId[$from].label }
                $reason = [string](Get-ProducerGraphProperty -InputObject $edge -Name 'reason')
                if ($reason) { $entry['reason'] = $reason }
                $unresolved.Add([pscustomobject]$entry)
            }
            elseif ($resolvedFlag -is [bool]) {
                $link['resolution'] = 'resolved'
            }

            [pscustomobject]$link
        }

        $meta = Get-ProducerGraphProperty -InputObject $Graph.graph -Name 'meta'
        $producer = [string](Get-ProducerGraphProperty -InputObject $meta -Name 'producer')
        $producerVersion = [string](Get-ProducerGraphProperty -InputObject $meta -Name 'producerVersion')
        $rootPath = ''
        $roots = Get-ProducerGraphProperty -InputObject $meta -Name 'roots'
        if ($roots) { $rootPath = [string]@($roots)[0] }

        $scopes = @($nodes | ForEach-Object { [string]$_.scope } | Sort-Object -Unique)
        $kinds = @($nodes | ForEach-Object { [string]$_.type } | Sort-Object -Unique)

        [pscustomobject]@{
            meta = [pscustomobject]([ordered]@{
                    contractVersion = '1.1.0'
                    title           = [string]$Options.Title
                    version         = $producerVersion
                    generatedAt     = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    rootPath        = $rootPath
                    stats           = [pscustomobject]([ordered]@{
                            NodeCount       = @($vmNodes).Count
                            EdgeCount       = @($vmLinks).Count
                            UnresolvedCount = $unresolved.Count
                            ScopeCount      = $scopes.Count
                            KindCount       = $kinds.Count
                            MaxDepth        = if ($depth.Count) { ($depth.Values | Measure-Object -Maximum).Maximum } else { 0 }
                        })
                })
            data = [pscustomobject]([ordered]@{
                    nodes      = @($vmNodes)
                    links      = @($vmLinks)
                    unresolved = @($unresolved.ToArray())
                    stats      = [pscustomobject]([ordered]@{
                            producer        = $producer
                            producerVersion = $producerVersion
                        })
                })
        }
    }
}
