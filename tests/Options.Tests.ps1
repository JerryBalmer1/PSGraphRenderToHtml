#Requires -Version 7.2

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToHtmlUnderTest
    $script:Repo = Split-Path -Parent $PSScriptRoot
}

Describe 'New-GraphRenderOptions' {

    It 'defaults to the renderer own defaults' {
        # Read from PSGraphRender v0.13.0 Config/settings.psd1, not chosen.
        $options = New-GraphRenderOptions
        $options.Backend | Should-Be 'cytoscape'
        $options.Layout | Should-Be 'foundation'
        $options.Settings.ZoomSpeed | Should-Be 1.25
        $options.Settings.FocusDepth | Should-Be 2
        $options.Settings.NodeLimit | Should-Be 400
        $options.Settings.MinReadableZoom | Should-Be 0.45
    }

    It 'offers exactly the layouts the cytoscape backend implements' {
        # FLOW_LAYOUT in PSGraphRender scripts/render.js has three entries. A
        # list written from memory silently stops matching the renderer, so
        # this asserts the set rather than a count.
        $parameter = (Get-Command New-GraphRenderOptions).Parameters['Layout']
        $validate = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        @($validate.ValidValues) | Should-BeCollection @('foundation', 'testorder', 'callflow') -Because 'these are FLOW_LAYOUT keys'
    }

    It 'carries the layout into DefaultFlow, which is what the page reads' {
        $options = New-GraphRenderOptions -Layout callflow
        $options.Settings.DefaultFlow | Should-Be 'callflow'
    }

    It 'refuses a zoom speed outside the renderer own bounds' {
        # ZoomSpeedMin 0.25, ZoomSpeedMax 5. Emitting a value the page will
        # clamp silently is worse than refusing it here.
        { New-GraphRenderOptions -ZoomSpeed 9 } | Should-Throw
        { New-GraphRenderOptions -ZoomSpeed 0.1 } | Should-Throw
    }

    It 'refuses a layout that does not exist' {
        { New-GraphRenderOptions -Layout hierarchical } | Should-Throw
    }

    It 'takes an editor link map' {
        $options = New-GraphRenderOptions -EditorLinkMap @{ 'a' = 'C:\x\a.tf' }
        $options.EditorLinkMap['a'] | Should-Be 'C:\x\a.tf'
    }
}

Describe 'Option precedence: explicit beats file beats built-in' {

    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ('tohtml-prec-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:Root -Force
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Root) {
            Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'uses built-ins when there is no file and no options' {
        $effective = Invoke-ResolveOptions -DefaultsRoot $script:Root
        $effective.Layout | Should-Be 'foundation'
        $effective.Settings.ZoomSpeed | Should-Be 1.25
    }

    It 'lets a defaults file beat the built-ins' {
        Set-Content -LiteralPath (Join-Path $script:Root 'graphrender.defaults.psd1') `
            -Value "@{ Layout = 'testorder'; ZoomSpeed = 3.0 }"
        $effective = Invoke-ResolveOptions -DefaultsRoot $script:Root
        $effective.Layout | Should-Be 'testorder'
        $effective.Settings.ZoomSpeed | Should-Be 3.0
    }

    It 'merges per key, leaving unmentioned values at their built-in' {
        # The property that makes a defaults file usable: setting one thing
        # must not blank everything else.
        Set-Content -LiteralPath (Join-Path $script:Root 'graphrender.defaults.psd1') `
            -Value "@{ ZoomSpeed = 3.0 }"
        $effective = Invoke-ResolveOptions -DefaultsRoot $script:Root
        $effective.Settings.ZoomSpeed | Should-Be 3.0
        $effective.Layout | Should-Be 'foundation'
        $effective.Settings.NodeLimit | Should-Be 400
    }

    It 'lets an explicit option beat the file' {
        Set-Content -LiteralPath (Join-Path $script:Root 'graphrender.defaults.psd1') `
            -Value "@{ Layout = 'testorder' }"
        $explicit = New-GraphRenderOptions -Layout callflow
        $effective = Invoke-ResolveOptions -Options $explicit -DefaultsRoot $script:Root
        $effective.Layout | Should-Be 'callflow' -Because 'a caller who named a value meant it'
    }

    It 'refuses an unknown key in the file, by name' {
        # Silently ignoring one means a typo reads as "the setting did
        # nothing" and costs somebody an afternoon.
        Set-Content -LiteralPath (Join-Path $script:Root 'graphrender.defaults.psd1') `
            -Value "@{ Zoomspeeed = 3.0 }"
        { Invoke-ResolveOptions -DefaultsRoot $script:Root } | Should-Throw -ExceptionMessage '*Zoomspeeed*'
    }
}
