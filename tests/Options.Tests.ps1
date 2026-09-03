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

Describe 'ColorBy is the RENDERER''s set, and the two are checked against each other' {

    BeforeAll {
        # Where PSGraphRender is, resolved the way the build and TestHelpers
        # resolve it. The schema file lives beside the manifest in both the
        # source layout and the built one.
        $script:ColorBySchema = $null
        $renderModule = Get-Module -Name PSGraphRender
        if ($renderModule) {
            $candidate = Join-Path (Split-Path -Parent $renderModule.Path) `
                'TemplateSets/cytoscape/Config/settings.schema.psd1'
            if (Test-Path -LiteralPath $candidate) { $script:ColorBySchema = $candidate }
        }
    }

    It 'accepts every member of the renderer schema set, and carries it through' {
        # BEHAVIOURAL, not a read of ValidValues. The defect this replaces was
        # a set that read correctly and was not the consumer's, so the check
        # that matters is that each value survives the round trip into the
        # Settings hashtable the overlay writer copies.
        foreach ($value in 'structure', 'dependents', 'blastRadius', 'dependencies', 'reach') {
            $options = New-GraphRenderOptions -ColorBy $value
            $options.ColorBy | Should-Be $value
            $options.Settings.ColorBy | Should-Be $value
        }
    }

    It 'is exactly the set PSGraphRender''s cytoscape settings schema declares' {
        # THE TEST LEDGER 50 ASKED FOR: a cross-module ValidateSet needs a test
        # that runs every member of it through the real consumer. Reading the
        # consumer's own schema is the closest this module can get without
        # rendering, and it is what would have caught the drift.
        $script:ColorBySchema | Should-NotBeNull -Because 'PSGraphRender is a RequiredModule, so its cytoscape settings schema is on disk wherever this test can run at all'
        $schema = Import-PowerShellDataFile -LiteralPath $script:ColorBySchema
        # Index syntax, not dot syntax: `.Values` on a hashtable is the
        # hashtable's OWN Values collection, so $entry.Values silently returns
        # every field of the entry rather than the enum it declares. It fails
        # as a null rather than as a wrong answer, which is the only luck in it.
        $declared = @($schema['Entries']['ColorBy']['Values'])
        @($declared).Count | Should-BeGreaterThan 1 -Because 'an Enum entry that declares no values means the schema moved and this test is reading the wrong thing'

        $accepted = foreach ($value in $declared) {
            try { (New-GraphRenderOptions -ColorBy $value).ColorBy } catch { "REFUSED: $value" }
        }
        @($accepted) | Should-BeCollection @($declared) -Because 'every value the renderer accepts must reach it'
    }

    It 'refuses a value the renderer never accepted, naming both sides' {
        # 'scope' and 'type' were this module's up to v0.1.0. The message has
        # to name the renderer, because a caller reading it is looking at the
        # wrong repository's documentation.
        foreach ($value in 'scope', 'type') {
            { New-GraphRenderOptions -ColorBy $value } |
                Should-Throw -ExceptionMessage '*PSGraphRender*'
            { New-GraphRenderOptions -ColorBy $value } |
                Should-Throw -ExceptionMessage '*blastRadius*'
        }
    }

    It 'offers the same set to tab completion as it accepts' {
        # Two literal lists live in the parameter's attributes. This is what
        # stops them drifting apart, and it compares behaviour rather than
        # text.
        $parameter = (Get-Command New-GraphRenderOptions).Parameters['ColorBy']
        $completer = @($parameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] })
        @($completer).Count | Should-Be 1
        $offered = @(& $completer[0].ScriptBlock 'New-GraphRenderOptions' 'ColorBy' '' $null @{})
        @([string[]]$offered) |
            Should-BeCollection @('structure', 'dependents', 'blastRadius', 'dependencies', 'reach')
    }

    It 'defaults to structure, which is the renderer''s default too' {
        (New-GraphRenderOptions).Settings.ColorBy | Should-Be 'structure'
    }
}
