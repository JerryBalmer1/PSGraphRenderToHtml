function Test-ProducerGraph {
    <#
    .SYNOPSIS
        Validate a producer graph against the contract, schema and semantics.
    .DESCRIPTION
        Two layers, both always run. The schema catches shape; the semantic
        rules catch what a schema cannot express - unique ids, resolving edge
        endpoints, acyclic parent chains, and an unresolved edge that states no
        reason.

        Every violation is named with a JSON path into the document. Returning
        "invalid" without saying where is a result a producer author cannot act
        on, and this module exists to be run by producer authors.

        It returns a result object and does not throw on an invalid graph -
        -ThrowOnFailure is opt-in. A validator that throws by default forces the
        caller to choose between "tell me everything wrong" and "stop at the
        first thing", and the first is the only useful answer while a producer
        is being brought up. It NEVER returns a bare $true.
    .PARAMETER Graph
        The producer graph: a parsed object, or anything ConvertTo-Json can
        round-trip.
    .PARAMETER Path
        A .json file holding the graph, instead of -Graph.
    .PARAMETER ThrowOnFailure
        Throw naming the violation count instead of returning an invalid result.
    .OUTPUTS
        PSCustomObject with IsValid, Violations, NodeCount, EdgeCount.
    .EXAMPLE
        Test-ProducerGraph -Path ./graph.json

        Validates and returns a result. $result.Violations names every problem
        with its JSON path.
    .EXAMPLE
        Get-TfConfigurationGraph -Path ./repo | Test-ProducerGraph -ThrowOnFailure

        The form a producer's own build uses: a bad graph fails the build.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Graph')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Graph', ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [object] $Graph,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [switch] $ThrowOnFailure
    )

    process {
        $violations = [System.Collections.Generic.List[object]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "No such graph file: '$Path'."
            }
            $json = Get-Content -LiteralPath $Path -Raw
            try {
                $Graph = $json | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                throw "'$Path' is not valid JSON: $($_.Exception.Message)"
            }
        }
        else {
            $json = $Graph | ConvertTo-Json -Depth 20
        }

        # Schema first. A document whose shape is wrong produces semantic
        # violations that are consequences rather than causes, and reporting
        # both makes the reader find the real one.
        $schemaPath = Resolve-ProducerSchemaPath
        $schemaOk = $true
        try {
            $null = Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop
        }
        catch {
            $schemaOk = $false
            foreach ($line in ($_.Exception.Message -split "`n" | Where-Object { $_.Trim() })) {
                $violations.Add([pscustomobject]@{
                        Rule    = 'schema'
                        Path    = Get-SchemaViolationPath -Message $line
                        Message = $line.Trim()
                    })
            }
        }

        if ($schemaOk) {
            foreach ($violation in (Test-ProducerGraphSemantic -Graph $Graph)) {
                $violations.Add($violation)
            }
        }

        $nodeCount = 0
        $edgeCount = 0
        if ($schemaOk) {
            $nodeCount = @($Graph.graph.nodes).Count
            $edgeCount = @($Graph.graph.edges).Count
        }

        $result = [pscustomobject]@{
            PSTypeName = 'PSGraphRenderToHtml.ValidationResult'
            IsValid    = ($violations.Count -eq 0)
            Violations = $violations.ToArray()
            NodeCount  = $nodeCount
            EdgeCount  = $edgeCount
            SchemaPath = $schemaPath
        }

        if ($ThrowOnFailure -and -not $result.IsValid) {
            $detail = ($result.Violations | ForEach-Object { "  $($_.Path): [$($_.Rule)] $($_.Message)" }) -join "`n"
            throw "The producer graph has $($result.Violations.Count) violation(s):`n$detail"
        }

        $result
    }
}
