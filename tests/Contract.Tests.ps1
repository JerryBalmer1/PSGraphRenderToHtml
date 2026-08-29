#Requires -Version 7.2

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToHtmlUnderTest
    $script:Sample = Join-Path $PSScriptRoot '../docs/samples/sample-graph.json'
}

Describe 'Test-ProducerGraph accepts a conforming graph' {

    It 'accepts the committed sample' {
        $result = Test-ProducerGraph -Path $script:Sample
        $detail = ($result.Violations | ForEach-Object { "$($_.Path): $($_.Message)" }) -join '; '
        $result.IsValid | Should-BeTrue -Because $detail
    }

    It 'counts what it validated' {
        # A validator that reports valid without saying what it looked at
        # passes an empty document identically.
        $result = Test-ProducerGraph -Path $script:Sample
        $result.NodeCount | Should-Be 15
        $result.EdgeCount | Should-Be 10
    }

    It 'never returns a bare boolean' {
        $result = Test-ProducerGraph -Path $script:Sample
        $result | Should-NotHaveType ([bool])
        $result.PSObject.Properties.Name | Should-ContainCollection 'Violations'
    }
}

Describe 'Test-ProducerGraph names every violation with a path' -ForEach @(
    @{ Case = 'missing-id'; Rule = 'schema' }
    @{ Case = 'duplicate-id'; Rule = 'unique-node-id' }
    @{ Case = 'dangling-edge'; Rule = 'edge-endpoint-resolves' }
    @{ Case = 'parent-cycle'; Rule = 'acyclic-parent-chain' }
    @{ Case = 'stored-depth'; Rule = 'schema' }
    @{ Case = 'unknown-key'; Rule = 'schema' }
    @{ Case = 'wrong-type'; Rule = 'schema' }
    @{ Case = 'empty-label'; Rule = 'schema' }
) {
    It 'rejects <Case> and names the rule <Rule>' {
        $graph = Get-ViolatingGraph -Case $Case
        $result = Test-ProducerGraph -Graph $graph

        $result.IsValid | Should-BeFalse -Because "$Case must not validate"
        @($result.Violations).Count | Should-BeGreaterThan 0
        @($result.Violations | ForEach-Object { $_.Rule }) | Should-ContainCollection $Rule

        # Every violation carries a location. "Invalid" without a path is a
        # result the producer author cannot act on.
        foreach ($violation in $result.Violations) {
            $violation.Path | Should-NotBeEmptyString
        }
    }
}

Describe 'Test-ProducerGraph -ThrowOnFailure' {
    It 'throws naming the count' {
        $graph = Get-ViolatingGraph -Case 'dangling-edge'
        { Test-ProducerGraph -Graph $graph -ThrowOnFailure } | Should-Throw -ExceptionMessage '*violation(s)*'
    }

    It 'does not throw on a good graph' {
        # Called directly rather than wrapped: an exception fails the test on
        # its own, and there is no Should-NotThrow.
        $result = Test-ProducerGraph -Path $script:Sample -ThrowOnFailure
        $result.IsValid | Should-BeTrue
    }
}

Describe 'The contract refuses a stored depth by shape, not by convention' {
    It 'has additionalProperties false on a node' {
        $schema = Get-Content (Join-Path $PSScriptRoot '../contract/producer-graph.schema.json') -Raw | ConvertFrom-Json
        $schema.properties.graph.properties.nodes.items.additionalProperties | Should-BeFalse
    }

    It 'is versioned 0.1.0' {
        $schema = Get-Content (Join-Path $PSScriptRoot '../contract/producer-graph.schema.json') -Raw | ConvertFrom-Json
        $schema.version | Should-Be '0.1.0'
    }
}
