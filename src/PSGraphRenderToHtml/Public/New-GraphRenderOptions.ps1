function New-GraphRenderOptions {
    <#
    .SYNOPSIS
        Build the options object that drives a render.
    .DESCRIPTION
        Four groups: which backend and opening layout, the interaction knobs,
        the theme, and the editor-link map.

        Every layout name and every interaction default here was READ from
        PSGraphRender v0.13.0's cytoscape template set rather than guessed -
        FLOW_LAYOUT in scripts/render.js for the layouts, Config/settings.psd1
        for the knobs and their current values, and Config/settings.schema.psd1
        for the ColorBy set. A list written from memory is a list that silently
        stops matching the renderer, and ColorBy is the one that did: see its
        parameter help.

        This function validates and normalises; it renders nothing. Settings
        reach PSGraphRender only through a template-set directory, so
        Export-ProducerGraphHtml materialises a caller-owned overlay of the
        chosen backend and hands it over with -TemplateSetPath. That is the
        seam PSGraphRender documents for a backend that does not ship with it,
        and it means applying an option never edits the renderer.
    .PARAMETER Backend
        Which template set renders. 'cytoscape' draws an interactive graph;
        'plain' renders tables and vendors nothing.
    .PARAMETER Layout
        Which view the report OPENS in - PSGraphRender's DefaultFlow setting.
        'foundation' lays itself out and is not dagre; 'testorder' and
        'callflow' are dagre with different rankers. Ignored by 'plain', which
        has no layouts, and saying so is better than pretending it applies.
    .PARAMETER ZoomSpeed
        Wheel/scroll zoom multiplier. The renderer's own bounds are
        ZoomSpeedMin 0.25 to ZoomSpeedMax 5, and this refuses anything outside
        them rather than emitting a setting the page will clamp silently.
    .PARAMETER FocusDepth
        How many hops focus mode keeps around the selected node.
    .PARAMETER NodeLimit
        Above this many nodes the report warns before drawing.
    .PARAMETER MinReadableZoom
        Below this zoom labels are hidden.
    .PARAMETER ColorBy
        Which channel carries node FILL, and the set is PSGraphRender's, not
        this module's. `structure` gives one colour per classification, read
        from the theme's KindColor map; every other member names a metric and
        gives a heat ramp over it.

        THE SET IS THE CONSUMER'S. Up to v0.1.0 this parameter validated
        against { structure, scope, type } while PSGraphRender v0.13.0's
        cytoscape settings schema accepted { structure, dependents,
        blastRadius, dependencies, reach } - two sets sharing exactly one
        member. A `ValidateSet` is a promise about what the CALLEE accepts, and
        here the callee is a different repository at a different version, so
        the promise was false in both directions: `scope` and `type` were taken
        and then silently downgraded, and the four metrics the renderer does
        colour by could not be asked for at all. The set is now read from
        Config/settings.schema.psd1 and asserted against it by
        Options.Tests.ps1, so the two cannot drift again without a red test.

        To colour by a layer, name the layer's colour per classification in
        -Theme's KindColor map. Layer is not a fill channel the renderer knows;
        classification is, and a producer whose classifications partition its
        layers gets layer colour out of it exactly.
    .PARAMETER Theme
        Overrides merged over the backend's theme.psd1. Appearance only - a
        behaviour key here is a setting in the wrong file.
    .PARAMETER EditorLinkMap
        Node id -> absolute file path. Emitted as vscode://file/ links so a
        reader can open the source of a node. Supply it only when the producer
        actually knows the paths; a map with wrong paths is worse than none.
    .PARAMETER Title
        Page title.
    .OUTPUTS
        PSCustomObject accepted by ConvertTo-GraphRenderViewModel and
        Export-ProducerGraphHtml.
    .EXAMPLE
        New-GraphRenderOptions -Layout callflow -ZoomSpeed 2

        Opens in the call-flow view with faster wheel zoom.
    .EXAMPLE
        New-GraphRenderOptions -EditorLinkMap @{ 'repo:app/main.tf' = 'C:\src\app\main.tf' }

        Emits a vscode://file/ link for that node.
    .EXAMPLE
        New-GraphRenderOptions -ColorBy blastRadius

        Node fill becomes a heat ramp over blast radius. This is one of the
        four metric values v0.1.0 refused and the renderer has always drawn.
    .EXAMPLE
        $layers = @{
            rule       = '#6b5bd6'
            instrument = '#2f8f6b'
            plugin     = '#c98a1e'
            module     = '#3b7fc4'
            person     = '#b4536b'
        }

        New-GraphRenderOptions -ColorBy structure -Theme @{ KindColor = $layers }

        Colour by layer, for a producer whose classifications partition its
        layers. The renderer colours by classification and knows nothing about
        layers; the producer is what makes the two the same fact.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateSet('cytoscape', 'plain')]
        [string] $Backend = 'cytoscape',

        [Parameter()]
        [ValidateSet('foundation', 'testorder', 'callflow')]
        [string] $Layout = 'foundation',

        [Parameter()]
        [ValidateRange(0.25, 5.0)]
        [double] $ZoomSpeed = 1.25,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int] $FocusDepth = 2,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int] $NodeLimit = 400,

        [Parameter()]
        [ValidateRange(0.05, 1.0)]
        [double] $MinReadableZoom = 0.45,

        [Parameter()]
        [ArgumentCompleter({
                # No param() block, and $args[2] rather than a name: a
                # completer is handed five arguments and this one needs the
                # third. Declaring the two ahead of it in order to name it
                # leaves two parameters PSScriptAnalyzer is right to report as
                # unused, and silencing a rule to keep a name is the wrong
                # trade in the one file this release is about.
                @('structure', 'dependents', 'blastRadius', 'dependencies', 'reach') |
                    Where-Object { $_ -like "$($args[2])*" }
            })]
        [ValidateScript(
            { $_ -in @('structure', 'dependents', 'blastRadius', 'dependencies', 'reach') },
            ErrorMessage = "-ColorBy '{0}' is not a value the renderer accepts. PSGraphRenderToHtml accepts exactly what PSGraphRender's cytoscape settings schema accepts, and that set is: structure, dependents, blastRadius, dependencies, reach. Up to v0.1.0 this module also accepted 'scope' and 'type'; PSGraphRender never did, so passing either produced a warning from the renderer and a silent fall back to 'structure'. To colour by a layer, name a colour per classification in -Theme's KindColor map, which is the channel the renderer actually reads."
        )]
        [string] $ColorBy = 'structure',

        [Parameter()]
        [hashtable] $Theme = @{},

        [Parameter()]
        [hashtable] $EditorLinkMap = @{},

        [Parameter()]
        [string] $Title = 'Graph'
    )

    if ($Backend -eq 'plain' -and $PSBoundParameters.ContainsKey('Layout')) {
        Write-Warning "The 'plain' backend renders tables and has no layouts; -Layout $Layout will not affect it."
    }

    [pscustomobject]@{
        PSTypeName      = 'PSGraphRenderToHtml.RenderOptions'
        Backend         = $Backend
        Layout          = $Layout
        Title           = $Title
        ColorBy         = $ColorBy
        # Named for the renderer's own setting keys, so the overlay writer is a
        # copy rather than a translation table nobody maintains.
        Settings        = [ordered]@{
            DefaultFlow     = $Layout
            ColorBy         = $ColorBy
            ZoomSpeed       = $ZoomSpeed
            FocusDepth      = $FocusDepth
            NodeLimit       = $NodeLimit
            MinReadableZoom = $MinReadableZoom
        }
        Theme           = $Theme
        EditorLinkMap   = $EditorLinkMap
        ContractVersion = '0.1.0'
    }
}
