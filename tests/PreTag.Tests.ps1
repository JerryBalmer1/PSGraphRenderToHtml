#Requires -Version 7.2
<#
    Seals on a FINISHED iteration. Tagged PreTag and excluded from the default
    run, so a half-done iteration still builds green while the tag cannot.

    Two of these reinstate guarantees PSGraphRender lost at v0.13.0 when its
    tests/Instructions.Tests.ps1 was deleted with the resident workflow: that
    documentation names only paths that exist, and that no document can cause a
    push by being followed. That pass recorded both as lost and unenforced. They
    are cheap to hold here, and a repository whose HANDOFF names a dozen paths
    needs the first one.
#>

BeforeAll {
    $script:Repo = Split-Path -Parent $PSScriptRoot
}

Describe 'The documentation points only at things that exist' -Tag 'PreTag' {

    It 'finds documents to check at all' {
        # A check that iterates an empty collection passes every assertion
        # below it, which is the failure mode of the whole file.
        $script:Documents = @(
            Get-ChildItem -LiteralPath $script:Repo -Filter '*.md' -File
            Get-ChildItem -LiteralPath (Join-Path $script:Repo 'docs') -Filter '*.md' -File -Recurse
        )
        @($script:Documents).Count | Should-BeGreaterThan 2
    }

    It 'names no repository path that is absent' {
        $documents = @(
            Get-ChildItem -LiteralPath $script:Repo -Filter '*.md' -File
            Get-ChildItem -LiteralPath (Join-Path $script:Repo 'docs') -Filter '*.md' -File -Recurse
        )

        $missing = foreach ($document in $documents) {
            $text = Get-Content -LiteralPath $document.FullName -Raw
            # Only paths with a directory component this repository actually
            # has. That is the form which is unambiguously a claim about THIS
            # tree's layout.
            #
            # A bare filename is deliberately NOT checked. The first run of
            # this gate flagged `graphrender.defaults.psd1`, which is a file a
            # PRODUCER creates in its own repository and which correctly does
            # not exist here - a false positive, and the kind that trains a
            # reader to ignore the gate. It also flagged `docs/vendoring.md`,
            # which was a real defect and is fixed.
            # NOT $matches: that is an automatic variable holding the captures
            # of the last -match, and this same test uses -match. The analyzer
            # caught it; the default build lints and the PreTag task does not,
            # so it went green here before it went red there.
            $candidates = [regex]::Matches($text, '`((?:src|tests|docs|contract|scripts)/[A-Za-z0-9._/*<>-]+)`')
            foreach ($match in $candidates) {
                $candidate = $match.Groups[1].Value
                # Placeholders are not claims about a path.
                if ($candidate -match '[<>*]') { continue }
                if (Test-Path -LiteralPath (Join-Path $script:Repo $candidate)) { continue }
                "$($document.Name): $candidate"
            }
        }

        ((@($missing) | Sort-Object -Unique) -join '; ') | Should-Be ''
    }
}

Describe 'What a document can make happen' -Tag 'PreTag' {

    It 'has no document that can publish by being followed' {
        # Publishing is the operator's. The blast radius of a push leaves the
        # machine and no local operation reverses it, so no document here may
        # cause one by being followed. CHANGELOG-style records are exempt
        # nowhere yet, because there is no record here that needs to quote a
        # push.
        $documents = @(
            Get-ChildItem -LiteralPath $script:Repo -Filter '*.md' -File
            Get-ChildItem -LiteralPath (Join-Path $script:Repo 'docs') -Filter '*.md' -File -Recurse
        )

        $offenders = foreach ($document in $documents) {
            $text = Get-Content -LiteralPath $document.FullName -Raw
            if ($text -match '(?m)^\s*(?:PS>\s*)?git\s+push\b') { $document.Name }
            if ($text -match '(?m)^\s*(?:PS>\s*)?Publish-Module\b') { $document.Name }
        }

        ((@($offenders) | Sort-Object -Unique) -join ', ') | Should-Be ''
    }
}

Describe 'The version this repository claims is one version' -Tag 'PreTag' {

    It 'agrees between the manifest, the contract and the documents' {
        # Three places state a version and they are one fact. The manifest is
        # the module's; the schema is the contract's; the documents quote both.
        # A tag whose manifest disagrees with it is how PSGraphRender shipped
        # v0.12.0 with a manifest reading 0.11.0.
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Repo 'src/PSGraphRenderToHtml/PSGraphRenderToHtml.psd1')
        $schema = Get-Content -LiteralPath (Join-Path $script:Repo 'contract/producer-graph.schema.json') -Raw | ConvertFrom-Json

        $manifest.ModuleVersion | Should-Be '0.1.1'
        $schema.version | Should-Be '0.1.0'

        # The worklog for the module version must exist, or the release has no
        # written reason.
        Test-Path -LiteralPath (Join-Path $script:Repo "docs/worklog/v$($manifest.ModuleVersion).md") |
            Should-BeTrue -Because "docs/worklog/v$($manifest.ModuleVersion).md is where a release says why"
    }

    It 'declares the renderer version it was written against' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Repo 'src/PSGraphRenderToHtml/PSGraphRenderToHtml.psd1')
        $required = @($manifest.RequiredModules | Where-Object { $_['ModuleName'] -eq 'PSGraphRender' })
        @($required).Count | Should-Be 1
        $required[0]['ModuleVersion'] | Should-Be '0.13.0'
    }
}

Describe 'The battery is runnable by a producer that has only this file' -Tag 'PreTag' {

    It 'takes a GraphPath and nothing else mandatory' {
        # The battery is the ecosystem's enforcement point and a producer
        # invokes it as a container. A second mandatory parameter would make
        # every producer's invocation different from the documented one.
        $battery = Join-Path $script:Repo 'tests/ProducerContract.Battery.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($battery, [ref]$null, [ref]$null)

        $mandatory = foreach ($parameter in $ast.ParamBlock.Parameters) {
            $isMandatory = $parameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] } |
                ForEach-Object { $_.NamedArguments } |
                Where-Object { $_ -and $_.ArgumentName -eq 'Mandatory' }
            if ($isMandatory) { $parameter.Name.VariablePath.UserPath }
        }

        (@($mandatory) -join ', ') | Should-Be 'GraphPath'
    }
}
