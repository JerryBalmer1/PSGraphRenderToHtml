function Get-ProducerGraphDepth {
    <#
    .SYNOPSIS
        Depth per node id, derived from parentId chains. The only place depth
        is computed.
    .DESCRIPTION
        Depth is a function of the parent chain, which is why the contract
        refuses to carry it: a stored depth and a parentId are two sources of
        truth for one fact, and nothing would notice them disagreeing.

        A root is depth 0. A node whose parent does not resolve is treated as a
        root, because the alternative is failing here on a graph that
        Test-ProducerGraph has already reported by name - one defect, one
        report.

        Memoised per id, so a chain shared by many leaves is walked once.

        The parameter is InputNode, not Node, deliberately. PowerShell variable
        names are case-INSENSITIVE, so a parameter $Node and a loop variable
        $node are one variable: the first foreach overwrites the parameter with
        its last element, and the second foreach then iterates a single object.
        It produced a depth table with one entry out of fifteen and no error at
        all.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $InputNode
    )

    $parentOf = @{}
    foreach ($node in $InputNode) {
        $parentOf[[string]$node.id] = [string](Get-ProducerGraphProperty -InputObject $node -Name 'parentId')
    }

    $depth = @{}
    foreach ($node in $InputNode) {
        $id = [string]$node.id
        if ($depth.ContainsKey($id)) { continue }

        # Iterative, and cycle-guarded. A cycle is already a named violation
        # from Test-ProducerGraph; here it must merely not hang.
        $chain = [System.Collections.Generic.List[string]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $current = $id

        while ($true) {
            if ($depth.ContainsKey($current)) { break }
            if (-not $seen.Add($current)) { $depth[$current] = 0; break }
            $chain.Add($current)
            $parent = $parentOf[$current]
            if ([string]::IsNullOrEmpty($parent) -or -not $parentOf.ContainsKey($parent)) {
                $depth[$current] = 0
                break
            }
            $current = $parent
        }

        for ($i = $chain.Count - 1; $i -ge 0; $i--) {
            $node2 = $chain[$i]
            if ($depth.ContainsKey($node2)) { continue }
            $parent = $parentOf[$node2]
            $depth[$node2] = if ([string]::IsNullOrEmpty($parent) -or -not $depth.ContainsKey($parent)) { 0 } else { $depth[$parent] + 1 }
        }
    }

    $depth
}
