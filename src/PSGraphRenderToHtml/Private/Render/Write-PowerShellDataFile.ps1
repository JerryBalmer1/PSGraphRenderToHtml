function Write-PowerShellDataFile {
    <#
    .SYNOPSIS
        Write a hashtable back out as a .psd1 an Import can read.
    .DESCRIPTION
        The overlay's settings and theme files. It refuses anything it cannot
        write rather than emitting something Import-PowerShellDataFile would
        reject at render time, three stages away from the cause.

        Values are emitted by type: numbers bare, booleans as $true/$false,
        $null as $null, strings single-quoted with internal quotes doubled,
        and MAPS AND LISTS RECURSIVELY. Writing a number as a string is not
        cosmetic - the renderer's own settings schema types them, and a quoted
        1.25 stops being a zoom multiplier.

        THE NESTED CASE IS NOT DECORATION, and v0.1.0 through v0.1.1 did not
        have it. This writer emits the WHOLE merged file, not the caller's
        keys, so PSGraphRender's own theme.psd1 - which declares KindColor,
        LinkColor and EdgeResolutionStyle as maps - had to survive the round
        trip before any theme key could be applied at all. It did not: passing
        a single scalar theme override threw on EdgeResolutionStyle, a key the
        caller had never mentioned. The effect was that -Theme was unusable in
        every form, which is why nothing had noticed - a parameter nobody could
        use has no wrong behaviour to report.

        A key's value is REPLACED, not deep-merged. Handing back half of a
        caller's KindColor map and half of the backend's would be a colour
        scheme neither of them wrote.

        .PSBase.Keys, NOT .Keys. On a hashtable PowerShell resolves a member
        name against the dictionary's ENTRIES before its properties, so a map
        containing a key called 'Keys' answers $map.Keys with that entry's
        value and the writer walks the wrong object. A KindColor map is keyed
        by the producer's classifications, and 'Keys', 'Values' and 'Count' are
        all things a producer might reasonably call a node type. The same trap
        caught the ColorBy schema read in v0.1.1's own test - $entry.Values
        returning every field of the entry instead of the enum it declares -
        which is twice in one release, in opposite directions.

        KEYS ARE QUOTED WHEN THEY HAVE TO BE, and the case is not exotic. A
        KindColor map is keyed by the PRODUCER's classifications, and
        `cross-cutting` written bare is read by the .psd1 parser as `cross`
        minus `cutting`. The file then fails to parse as a whole, the renderer
        warns and falls back to its built-in theme, and the page draws every
        node in the fallback grey - a diagram that renders, looks deliberate,
        and carries none of the meaning it was configured with.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Data
    )

    function Format-DataFileKey {
        <#
            A key as .psd1 source. Bare when it is a plain identifier, quoted
            when it is anything else - which a producer's classification very
            easily is: 'cross-cutting', 'powershell-module', 'tf'. Quoting
            everything unconditionally would work and would make the backend's
            own hand-written files unrecognisable next to their generated
            overlay, which is the file a reader diffs when a theme does not
            apply.
        #>
        param([Parameter(Mandatory)] [string] $Key)
        if ($Key -match '^[A-Za-z_][A-Za-z0-9_]*$') { return $Key }
        "'" + $Key.Replace("'", "''") + "'"
    }

    function ConvertTo-DataFileLiteral {
        <#
            One value, as .psd1 source. $Indent is the indentation the value's
            OPENING brace sits at, so a nested map closes where it started.
            $Trail names the key path for the refusal message: 'KindColor.Enum'
            says where to look, where "a hashtable" does not.
        #>
        param(
            [Parameter()] [AllowNull()] $Value,
            [Parameter(Mandatory)] [string] $Indent,
            [Parameter(Mandatory)] [string] $Trail
        )

        if ($null -eq $Value) { return '$null' }
        if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
        if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }
        if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) {
            # Invariant culture: a machine whose locale writes 1,25 emits a
            # .psd1 that parses as something else entirely.
            return ([double]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($Value -is [string]) { return "'" + $Value.Replace("'", "''") + "'" }

        if ($Value -is [System.Collections.IDictionary]) {
            if ($Value.Count -eq 0) { return '@{}' }
            $inner = $Indent + '    '
            $parts = [System.Collections.Generic.List[string]]::new()
            $parts.Add('@{')
            foreach ($key in ($Value.PSBase.Keys | Sort-Object)) {
                $literal = ConvertTo-DataFileLiteral -Value $Value[$key] -Indent $inner -Trail "$Trail.$key"
                $parts.Add(('{0}{1,-24} = {2}' -f $inner, (Format-DataFileKey -Key $key), $literal))
            }
            $parts.Add($Indent + '}')
            return ($parts -join [Environment]::NewLine)
        }

        # A string is IEnumerable and was returned above; order matters here.
        if ($Value -is [System.Collections.IEnumerable]) {
            $items = @($Value)
            if ($items.Count -eq 0) { return '@()' }
            $rendered = foreach ($i in 0..($items.Count - 1)) {
                ConvertTo-DataFileLiteral -Value $items[$i] -Indent $Indent -Trail "$Trail[$i]"
            }
            return '@(' + ($rendered -join ', ') + ')'
        }

        throw "Cannot write '$Trail': this writer handles scalars, maps and lists, and was given [$($Value.GetType().Name)]."
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Generated by PSGraphRenderToHtml. This is a temporary overlay of a')
    $lines.Add('# PSGraphRender backend, not that backend. Do not edit; do not commit.')
    $lines.Add('@{')

    foreach ($key in ($Data.PSBase.Keys | Sort-Object)) {
        $literal = ConvertTo-DataFileLiteral -Value $Data[$key] -Indent '    ' -Trail $key
        $lines.Add(('    {0,-24} = {1}' -f (Format-DataFileKey -Key $key), $literal))
    }

    $lines.Add('}')
    Set-Content -LiteralPath $Path -Value ($lines -join [Environment]::NewLine) -Encoding utf8NoBOM
}
