#Requires -Version 7.2

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToHtmlUnderTest
    $script:Sample = Join-Path $PSScriptRoot '../docs/samples/sample-graph.json'
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('tohtml-export-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:Work -Force
}

AfterAll {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Export-ProducerGraphHtml renders through PSGraphRender' -Tag 'Integration' {

    It 'writes a document that is not empty' {
        $out = Join-Path $script:Work 'default.html'
        $written = Export-ProducerGraphHtml -Path $script:Sample -OutputPath $out
        Test-Path -LiteralPath $written | Should-BeTrue
        (Get-Item -LiteralPath $written).Length | Should-BeGreaterThan 10000
    }

    It 'carries the chosen layout into the document' -ForEach @(
        @{ Layout = 'foundation' }
        @{ Layout = 'testorder' }
        @{ Layout = 'callflow' }
    ) {
        $out = Join-Path $script:Work "$Layout.html"
        $null = Export-ProducerGraphHtml -Path $script:Sample -OutputPath $out `
            -Options (New-GraphRenderOptions -Layout $Layout)
        $html = Get-Content -LiteralPath $out -Raw
        # DefaultFlow is what the page reads to decide which view opens; the
        # data-layout attribute is set by script at runtime and is not in the
        # static document, so asserting on it would assert on nothing.
        $html | Should-MatchString "`"DefaultFlow`"\s*:\s*`"$Layout`""
    }

    It 'applies an interaction setting' {
        $out = Join-Path $script:Work 'zoom.html'
        $null = Export-ProducerGraphHtml -Path $script:Sample -OutputPath $out `
            -Options (New-GraphRenderOptions -ZoomSpeed 3)
        (Get-Content -LiteralPath $out -Raw) | Should-MatchString '"ZoomSpeed"\s*:\s*3'
    }

    It 'puts a vscode link in the document when a map is supplied' {
        $out = Join-Path $script:Work 'links.html'
        $null = Export-ProducerGraphHtml -Path $script:Sample -OutputPath $out `
            -Options (New-GraphRenderOptions -EditorLinkMap @{ 'services:api' = 'C:\estate\services\modules\api\main.tf' })
        (Get-Content -LiteralPath $out -Raw) | Should-MatchString 'vscode://file/C:/estate/services/modules/api/main.tf'
    }

    It 'renders through the plain backend too' {
        # The backend that vendors nothing. If the mapping only worked for
        # cytoscape, this module would have learned one backend's vocabulary.
        $out = Join-Path $script:Work 'plain.html'
        $null = Export-ProducerGraphHtml -Path $script:Sample -OutputPath $out `
            -Options (New-GraphRenderOptions -Backend plain)
        (Get-Item -LiteralPath $out).Length | Should-BeGreaterThan 1000
    }

    It 'refuses an invalid graph before rendering anything' {
        $bad = Join-Path $script:Work 'bad.json'
        Get-ViolatingGraph -Case 'dangling-edge' | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $bad
        $out = Join-Path $script:Work 'never.html'
        { Export-ProducerGraphHtml -Path $bad -OutputPath $out } | Should-Throw
        Test-Path -LiteralPath $out | Should-BeFalse -Because 'a refused render must not leave a partial document'
    }

    It 'leaves no overlay directory behind' {
        # The overlay is this module's temporary copy of a backend. One left
        # behind per render would fill a build agent quietly.
        $before = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'psgraphrendertohtml-*' -Directory -ErrorAction SilentlyContinue).Count
        $null = Export-ProducerGraphHtml -Path $script:Sample -OutputPath (Join-Path $script:Work 'tidy.html')
        $after = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'psgraphrendertohtml-*' -Directory -ErrorAction SilentlyContinue).Count
        $after | Should-Be $before
    }

    It 'honours graphrender.defaults.psd1 beside the graph' {
        $root = Join-Path $script:Work 'withdefaults'
        $null = New-Item -ItemType Directory -Path $root -Force
        Copy-Item -LiteralPath $script:Sample -Destination (Join-Path $root 'graph.json')
        Set-Content -LiteralPath (Join-Path $root 'graphrender.defaults.psd1') -Value "@{ Layout = 'testorder' }"

        $out = Join-Path $script:Work 'fromdefaults.html'
        $null = Export-ProducerGraphHtml -Path (Join-Path $root 'graph.json') -OutputPath $out
        (Get-Content -LiteralPath $out -Raw) | Should-MatchString '"DefaultFlow"\s*:\s*"testorder"'
    }
}

Describe 'A theme override reaches the backend, including a nested one' {

    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        Import-ToHtmlUnderTest
        $script:Work = Join-Path ([IO.Path]::GetTempPath()) ('tohtml-theme-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:Work -Force
        $script:GraphFile = Join-Path $script:Work 'graph.json'
        Get-ConformingGraph | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $script:GraphFile -Encoding utf8NoBOM
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:Work) {
            Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'renders with a nested theme value, which v0.1.1 could not do at all' {
        # THE WHOLE OF -Theme WAS UNUSABLE, and not only for nested values the
        # caller passes. The overlay writer emits the MERGED file, so
        # PSGraphRender's own theme.psd1 - KindColor, LinkColor and
        # EdgeResolutionStyle are all maps - had to survive the round trip
        # before any theme key could be applied. It threw on
        # EdgeResolutionStyle, a key no caller had mentioned.
        $options = New-GraphRenderOptions -Theme @{
            KindColor = @{ Function = '#A99BF2'; Class = '#79D9A8' }
        }
        $document = Export-ProducerGraphHtml -Path $script:GraphFile -Options $options
        $document | Should-MatchString 'A99BF2'
        $document | Should-MatchString '79D9A8'
    }

    It 'refuses a theme key the backend never declared, still' {
        { Export-ProducerGraphHtml -Path $script:GraphFile -Options (
                New-GraphRenderOptions -Theme @{ NotAThemeKey = 'x' }) } |
            Should-Throw -ExceptionMessage '*NotAThemeKey*'
    }

    It 'refuses a value it cannot write, naming the key path rather than the type alone' {
        # The refusal is the half of the writer that has to keep working. A
        # writer that silently emits something Import-PowerShellDataFile
        # rejects moves the failure three stages from its cause.
        InModuleScope PSGraphRenderToHtml {
            $file = Join-Path ([IO.Path]::GetTempPath()) ('writer-' + [guid]::NewGuid().ToString('N') + '.psd1')
            try {
                { Write-PowerShellDataFile -Path $file -Data @{
                        KindColor = @{ Enum = [scriptblock]::Create('1') }
                    } } | Should-Throw -ExceptionMessage '*KindColor.Enum*'
            }
            finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'colours a classification whose name is not a bare identifier' {
        # A KindColor map is keyed by the PRODUCER's classifications, and
        # 'cross-cutting' written bare parses as cross minus cutting. The whole
        # file then fails to parse, the renderer warns and falls back to its
        # built-in theme, and the page draws in the fallback grey - rendering
        # successfully, looking deliberate, and carrying nothing. Two of this
        # repository's own consumers have a hyphen in a node type.
        $graph = Get-ConformingGraph
        foreach ($node in $graph.graph.nodes) { $node.type = 'cross-cutting' }
        $file = Join-Path $script:Work 'hyphenated.json'
        $graph | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding utf8NoBOM

        $warnings = @()
        $document = Export-ProducerGraphHtml -Path $file -Options (
            New-GraphRenderOptions -Theme @{ KindColor = @{ 'cross-cutting' = '#F2C14E' } }
        ) -WarningVariable warnings -WarningAction SilentlyContinue

        @($warnings).Count | Should-Be 0 -Because 'a theme file that will not parse is reported as a warning and then ignored, which is the quietest failure available'
        $document | Should-MatchString 'F2C14E'
    }

    It 'round-trips maps, lists and scalars through Import-PowerShellDataFile' {
        InModuleScope PSGraphRenderToHtml {
            $file = Join-Path ([IO.Path]::GetTempPath()) ('writer-' + [guid]::NewGuid().ToString('N') + '.psd1')
            try {
                $data = @{
                    Flat   = 'a value with an '' apostrophe'
                    Number = 1.25
                    Yes    = $true
                    Ramp   = @('#111111', '#222222')
                    Nested = @{ Inner = @{ Deep = 3 }; Colour = '#A99BF2' }
                    Keys   = @{ 'cross-cutting' = 'x'; 'powershell-module' = 'y'; Plain = 'z' }
                    Empty  = @{}
                }
                Write-PowerShellDataFile -Path $file -Data $data
                $back = Import-PowerShellDataFile -LiteralPath $file

                $back.Flat | Should-Be "a value with an ' apostrophe"
                $back.Number | Should-Be 1.25
                $back.Yes | Should-BeTrue
                @($back.Ramp) | Should-BeCollection @('#111111', '#222222')
                $back.Nested.Colour | Should-Be '#A99BF2'
                $back.Nested.Inner.Deep | Should-Be 3
                $back.Keys['cross-cutting'] | Should-Be 'x'
                $back.Keys['powershell-module'] | Should-Be 'y'
                $back.Keys['Plain'] | Should-Be 'z'
                $back.Empty.Count | Should-Be 0
            }
            finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        }
    }
}
