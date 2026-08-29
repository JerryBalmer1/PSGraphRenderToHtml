function Get-SchemaViolationPath {
    <#
    .SYNOPSIS
        The JSON path out of a Test-Json failure message, when it names one.
    .DESCRIPTION
        Test-Json reports lines like
            "Schema validation failed: ... Path 'graph.nodes[2].label' ..."
        and the path is the only part a producer author can act on directly.
        When no path can be recovered the document root is returned rather than
        an empty string, so every violation this module reports carries SOME
        location and a caller can format them uniformly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Message)

    foreach ($pattern in @(
            "(?:Path|path)\s+'([^']+)'"
            '(?:Path|path)\s+"([^"]+)"'
            '#/([A-Za-z0-9_./\[\]-]+)'
        )) {
        $match = [regex]::Match($Message, $pattern)
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return '$'
}
