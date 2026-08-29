function Get-SchemaViolationPath {
    <#
    .SYNOPSIS
        The location out of a Test-Json failure message, as a JSON path.
    .DESCRIPTION
        Test-Json on PowerShell 7 reports a JSON POINTER at the end of each
        line:

            Required properties ["id"] are not present at '/graph/nodes/1'
            All values fail against the false schema at '/graph/nodes/1/depth'
            Value is "array" but should be "string" at '/graph/nodes/1/scope'

        That pointer is the only part of the message a producer author can act
        on, and it is converted to the same dotted-and-indexed form the semantic
        rules emit - graph.nodes[1].depth - so a caller can format every
        violation the same way regardless of which layer found it. Two
        vocabularies for one concept would make the report harder to read than
        no report at all.

        Other shapes are still matched, because the message format is a property
        of the runtime rather than of this module and has changed before. When
        nothing can be recovered the document root is returned, so every
        violation carries SOME location; a violation that names nowhere is one
        nobody can act on.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Message)

    # A JSON Pointer in quotes, which is what PowerShell 7's Test-Json emits.
    $pointer = [regex]::Match($Message, "at\s+'(/[^']*)'")
    if (-not $pointer.Success) {
        $pointer = [regex]::Match($Message, 'at\s+"(/[^"]*)"')
    }
    if ($pointer.Success) {
        return ConvertFrom-JsonPointer -Pointer $pointer.Groups[1].Value
    }

    # Older and alternative shapes.
    foreach ($pattern in @(
            "(?:Path|path)\s+'([^']+)'"
            '(?:Path|path)\s+"([^"]+)"'
            '#(/[A-Za-z0-9_./~\[\]-]*)'
        )) {
        $match = [regex]::Match($Message, $pattern)
        if ($match.Success) {
            $value = $match.Groups[1].Value
            if ($value.StartsWith('/')) { return ConvertFrom-JsonPointer -Pointer $value }
            return $value
        }
    }

    return '$'
}

function ConvertFrom-JsonPointer {
    <#
    .SYNOPSIS
        RFC 6901 pointer to the dotted-and-indexed path the semantic rules use.
    .DESCRIPTION
        /graph/nodes/1/depth becomes graph.nodes[1].depth. An all-digit segment
        is an array index, which is the only reading a JSON Pointer allows for
        one: object keys that look like integers are legal in JSON and are
        vanishingly rare in a schema this module owns, and the alternative -
        carrying the raw pointer - loses the correspondence with every other
        violation this module reports.

        The two RFC escapes are undone in the order the RFC requires: ~1 before
        ~0, or a literal ~1 in a key becomes a slash.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Pointer)

    if ([string]::IsNullOrEmpty($Pointer) -or $Pointer -eq '/') { return '$' }

    $path = [System.Text.StringBuilder]::new()
    foreach ($segment in ($Pointer.TrimStart('/') -split '/')) {
        if ($segment -eq '') { continue }
        $decoded = $segment.Replace('~1', '/').Replace('~0', '~')
        if ($decoded -match '^\d+$') {
            $null = $path.Append("[$decoded]")
        }
        elseif ($path.Length -eq 0) {
            $null = $path.Append($decoded)
        }
        else {
            $null = $path.Append('.').Append($decoded)
        }
    }

    if ($path.Length -eq 0) { return '$' }
    $path.ToString()
}
