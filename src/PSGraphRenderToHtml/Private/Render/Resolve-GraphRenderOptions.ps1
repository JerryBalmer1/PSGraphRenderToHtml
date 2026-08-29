function Resolve-GraphRenderOptions {
    <#
    .SYNOPSIS
        Apply the option precedence: explicit beats file beats built-in.
    .DESCRIPTION
        graphrender.defaults.psd1 at the producer repository root lets a
        producer state how its graphs should look without every caller
        repeating it. An explicit -Options object beats it, because a caller who
        named a value meant it.

        The merge is per key, not per object. A defaults file that sets only
        ZoomSpeed leaves Layout at its built-in rather than blanking it, which
        is what "defaults" has to mean to be usable.

        An unknown key in the file is refused by name. Silently ignoring one
        means a typo reads as "the setting did nothing" and costs somebody an
        afternoon.
    .PARAMETER Options
        The caller's explicit options, or $null.
    .PARAMETER DefaultsRoot
        Directory to look for graphrender.defaults.psd1 in.
    .OUTPUTS
        PSCustomObject - the effective options.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()] [AllowNull()] [object] $Options,
        [Parameter()] [AllowNull()] [string] $DefaultsRoot
    )

    # Explicit options win outright, and the file is not even read. Reading it
    # to merge under an object the caller fully specified would make the
    # result depend on where the graph happened to sit.
    if ($Options) { return $Options }

    $arguments = @{}
    if ($DefaultsRoot) {
        $file = Join-Path $DefaultsRoot 'graphrender.defaults.psd1'
        if (Test-Path -LiteralPath $file) {
            $data = Import-PowerShellDataFile -LiteralPath $file
            $known = @('Backend', 'Layout', 'ZoomSpeed', 'FocusDepth', 'NodeLimit',
                'MinReadableZoom', 'ColorBy', 'Theme', 'EditorLinkMap', 'Title')
            foreach ($key in @($data.Keys)) {
                if ($key -notin $known) {
                    throw "graphrender.defaults.psd1 sets '$key', which New-GraphRenderOptions has no parameter for. Known keys: $($known -join ', ')."
                }
                $arguments[$key] = $data[$key]
            }
            Write-Verbose "Applied $($arguments.Count) default(s) from $file"
        }
    }

    New-GraphRenderOptions @arguments
}
