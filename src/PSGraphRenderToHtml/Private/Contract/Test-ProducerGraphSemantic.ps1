function Test-ProducerGraphSemantic {
    <#
    .SYNOPSIS
        The rules JSON Schema cannot express, each violation named with a path.
    .DESCRIPTION
        A schema-valid graph is not necessarily a usable one. Three facts are
        checkable only across the whole document:

        - ids are unique
        - every edge endpoint resolves to a node id
        - parentId chains are acyclic, and every parentId resolves

        Plus one that is a rule about honesty rather than shape: an edge
        carrying resolved=false must carry a reason, because an unresolved
        reference without one is a finding nobody can act on.

        Returns violation objects; it never writes and never throws on a bad
        graph. Throwing here would make the caller choose between "tell me
        everything wrong" and "stop at the first thing", and the first is the
        only useful answer when a producer is being brought up.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Graph
    )

    $nodes = @($Graph.graph.nodes)
    $edges = @($Graph.graph.edges)

    $byId = @{}
    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]
        if ($byId.ContainsKey($node.id)) {
            [pscustomobject]@{
                Rule    = 'unique-node-id'
                Path    = "graph.nodes[$i].id"
                Message = "duplicate node id '$($node.id)'; first declared at graph.nodes[$($byId[$node.id])]"
            }
            continue
        }
        $byId[$node.id] = $i
    }

    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]
        $parent = Get-ProducerGraphProperty -InputObject $node -Name 'parentId'
        if ([string]::IsNullOrEmpty($parent)) { continue }

        if (-not $byId.ContainsKey($parent)) {
            [pscustomobject]@{
                Rule    = 'parent-resolves'
                Path    = "graph.nodes[$i].parentId"
                Message = "node '$($node.id)' names parent '$parent', which is not a node in this graph"
            }
        }
    }

    # Walk each chain with a per-walk visited set. A shared set would report the
    # first node of a cycle and stay silent about every other node on it, which
    # reads as one defect where there are several.
    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $currentId = $nodes[$i].id
        [void]$seen.Add($currentId)

        while ($true) {
            $index = $byId[$currentId]
            if ($null -eq $index) { break }
            $parent = Get-ProducerGraphProperty -InputObject $nodes[$index] -Name 'parentId'
            if ([string]::IsNullOrEmpty($parent)) { break }
            if (-not $byId.ContainsKey($parent)) { break }

            if (-not $seen.Add($parent)) {
                [pscustomobject]@{
                    Rule    = 'acyclic-parent-chain'
                    Path    = "graph.nodes[$i].parentId"
                    Message = "node '$($nodes[$i].id)' sits on a parentId cycle through '$parent'"
                }
                break
            }
            $currentId = $parent
        }
    }

    for ($i = 0; $i -lt $edges.Count; $i++) {
        $edge = $edges[$i]
        foreach ($end in 'from', 'to') {
            $value = Get-ProducerGraphProperty -InputObject $edge -Name $end
            if (-not $byId.ContainsKey([string]$value)) {
                [pscustomobject]@{
                    Rule    = 'edge-endpoint-resolves'
                    Path    = "graph.edges[$i].$end"
                    Message = "edge $i ($($edge.kind)) names $end '$value', which is not a node in this graph"
                }
            }
        }

        $resolved = Get-ProducerGraphProperty -InputObject $edge -Name 'resolved'
        $reason = Get-ProducerGraphProperty -InputObject $edge -Name 'reason'
        if ($resolved -is [bool] -and -not $resolved -and [string]::IsNullOrWhiteSpace([string]$reason)) {
            [pscustomobject]@{
                Rule    = 'unresolved-states-a-reason'
                Path    = "graph.edges[$i].reason"
                Message = "edge $i is marked resolved=false and states no reason"
            }
        }

        $kind = [string](Get-ProducerGraphProperty -InputObject $edge -Name 'kind')
        if ($kind -eq 'contains') {
            [pscustomobject]@{
                Rule    = 'containment-is-not-an-edge'
                Path    = "graph.edges[$i].kind"
                Message = "edge $i uses kind 'contains'; containment is expressed by parentId, and stating it twice makes two facts that can disagree"
            }
        }
    }
}
