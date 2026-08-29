function Resolve-ProducerSchemaPath {
    <#
    .SYNOPSIS
        Where producer-graph.schema.json is, under either loader.
    .DESCRIPTION
        The build copies contract/ into output/<Name>/contract/, so the schema
        sits beside the module. Under the dev loader $script:ModuleRoot is
        src/<Name>/ and the schema is two levels up in the repository. Both are
        tried, in that order, and the failure names both places rather than
        saying the file is missing.

        A module that cannot find its own schema is a module whose validation
        silently stops validating, which is worse than one that cannot start.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $candidates = @(
        Join-Path $script:ModuleRoot 'contract/producer-graph.schema.json'
        Join-Path $script:ModuleRoot '../../contract/producer-graph.schema.json'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw ("producer-graph.schema.json was not found. Looked in: " + ($candidates -join '; '))
}
