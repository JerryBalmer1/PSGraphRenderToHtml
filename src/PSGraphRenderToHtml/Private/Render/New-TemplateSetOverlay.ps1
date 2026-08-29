function New-TemplateSetOverlay {
    <#
    .SYNOPSIS
        A caller-owned copy of a PSGraphRender backend with settings applied.
    .DESCRIPTION
        PSGraphRender resolves settings from the template set directory alone -
        New-RenderDocument has no -Settings parameter, deliberately, because
        "adding a setting must require editing data files only" is one of that
        repository's load-bearing rules.

        So an option is applied by copying the backend to a temporary directory,
        merging the caller's values over its Config/settings.psd1 and
        Config/theme.psd1, and passing the copy with -TemplateSetPath. That
        parameter exists precisely to make a backend PSGraphRender does not ship
        possible, and using it means applying an option never edits the
        renderer.

        Only keys the backend already declares are written. A setting the
        backend has never heard of would be carried into the page as dead
        config, and silently accepting one is how a typo becomes a support
        question.
    .PARAMETER TemplateSetPath
        The backend to copy.
    .PARAMETER Settings
        Values merged over Config/settings.psd1.
    .PARAMETER Theme
        Values merged over Config/theme.psd1.
    .OUTPUTS
        String - the overlay directory. The caller owns it and must remove it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $TemplateSetPath,
        [Parameter()] [System.Collections.IDictionary] $Settings = @{},
        [Parameter()] [System.Collections.IDictionary] $Theme = @{}
    )

    $overlay = Join-Path ([System.IO.Path]::GetTempPath()) ('psgraphrendertohtml-' + [guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $TemplateSetPath -Destination $overlay -Recurse -Force

    foreach ($pair in @(
            @{ File = 'Config/settings.psd1'; Values = $Settings; What = 'setting' }
            @{ File = 'Config/theme.psd1'; Values = $Theme; What = 'theme key' }
        )) {
        if (-not $pair.Values -or $pair.Values.Count -eq 0) { continue }

        $path = Join-Path $overlay $pair.File
        if (-not (Test-Path -LiteralPath $path)) {
            throw "The backend at '$TemplateSetPath' has no $($pair.File); this module cannot apply $($pair.What)s to it."
        }

        $current = Import-PowerShellDataFile -LiteralPath $path
        foreach ($key in @($pair.Values.Keys)) {
            if (-not $current.Contains($key)) {
                throw "The backend declares no $($pair.What) named '$key'. Applying one it has never heard of would put dead config in the page."
            }
            $current[$key] = $pair.Values[$key]
        }

        Write-PowerShellDataFile -Path $path -Data $current
    }

    $overlay
}
