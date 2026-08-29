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
