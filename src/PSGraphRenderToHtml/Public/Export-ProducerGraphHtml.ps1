function Export-ProducerGraphHtml {
    <#
    .SYNOPSIS
        Producer graph to a finished HTML report, in one call.
    .DESCRIPTION
        Composes ConvertTo-GraphRenderViewModel with PSGraphRender's
        New-RenderDocument. This is the only function a producer needs.

        Option precedence, highest first:

        1. an explicit -Options object
        2. graphrender.defaults.psd1 at -DefaultsRoot (or beside the graph file)
        3. New-GraphRenderOptions' built-in defaults

        Explicit beats file beats built-in, and each level is a whole-key merge
        rather than a whole-object replacement: a defaults file that sets only
        ZoomSpeed leaves every other value at its built-in. The precedence is
        tested, because a precedence nobody has watched invert is a precedence
        nobody knows.

        This module renders no HTML itself. Every byte of the document comes
        from PSGraphRender; what happens here is mapping and configuration.
    .PARAMETER Graph
        A producer graph.
    .PARAMETER Path
        A .json file holding the graph, instead of -Graph. Its directory is the
        default -DefaultsRoot.
    .PARAMETER Options
        From New-GraphRenderOptions. Beats the defaults file.
    .PARAMETER DefaultsRoot
        Where to look for graphrender.defaults.psd1 - normally the producer
        repository root.
    .PARAMETER OutputPath
        Write the document here. Without it the document is returned as a string.
    .PARAMETER SkipValidation
        Do not validate the graph before rendering. For deliberately exercising
        a shape the contract does not describe yet, which is a proposal rather
        than a habit.
    .OUTPUTS
        String - the document, or the path written.
    .EXAMPLE
        Export-ProducerGraphHtml -Path ./graph.json -OutputPath ./report.html

        Renders with defaults, honouring graphrender.defaults.psd1 beside the graph.
    .EXAMPLE
        $graph | Export-ProducerGraphHtml -Options (New-GraphRenderOptions -Layout callflow) -OutputPath ./flow.html

        An explicit option beats anything the defaults file says.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Graph')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Graph', ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [object] $Graph,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [object] $Options,

        [Parameter()]
        [string] $DefaultsRoot,

        [Parameter()]
        [string] $OutputPath,

        [Parameter()]
        [switch] $SkipValidation
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) { throw "No such graph file: '$Path'." }
            $Graph = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            if (-not $DefaultsRoot) { $DefaultsRoot = Split-Path -Parent (Resolve-Path -LiteralPath $Path).Path }
        }

        if (-not $SkipValidation) {
            $null = Test-ProducerGraph -Graph $Graph -ThrowOnFailure
        }

        $effective = Resolve-GraphRenderOptions -Options $Options -DefaultsRoot $DefaultsRoot

        $renderModule = Get-Module -Name PSGraphRender
        if (-not $renderModule) {
            Import-Module -Name PSGraphRender -ErrorAction Stop
            $renderModule = Get-Module -Name PSGraphRender
        }

        $setPath = Join-Path (Split-Path -Parent $renderModule.Path) "TemplateSets/$($effective.Backend)"
        if (-not (Test-Path -LiteralPath $setPath)) {
            throw "PSGraphRender $($renderModule.Version) at $($renderModule.Path) ships no '$($effective.Backend)' template set. Looked in $setPath."
        }

        $viewModel = ConvertTo-GraphRenderViewModel -Graph $Graph -Options $effective

        # 'plain' has no settings to apply and no layouts; overlaying it would
        # throw on the first key it has never heard of.
        $overlay = $null
        try {
            if ($effective.Backend -eq 'plain') {
                $document = New-RenderDocument -ViewModel $viewModel.data -Meta $viewModel.meta `
                    -Title $effective.Title -TemplateSetPath $setPath
            }
            else {
                $overlay = New-TemplateSetOverlay -TemplateSetPath $setPath `
                    -Settings $effective.Settings -Theme $effective.Theme
                $document = New-RenderDocument -ViewModel $viewModel.data -Meta $viewModel.meta `
                    -Title $effective.Title -TemplateSetPath $overlay
            }
        }
        finally {
            if ($overlay -and (Test-Path -LiteralPath $overlay)) {
                Remove-Item -LiteralPath $overlay -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if ($OutputPath) {
            $parent = Split-Path -Parent $OutputPath
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            Set-Content -LiteralPath $OutputPath -Value $document -Encoding utf8NoBOM
            return (Resolve-Path -LiteralPath $OutputPath).Path
        }

        $document
    }
}
