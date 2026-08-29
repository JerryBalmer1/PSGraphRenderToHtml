@{
    # ParseError is listed EXPLICITLY, and that is the whole point of this file.
    #
    # Invoke-ScriptAnalyzer -Settings filters diagnostics by severity, and
    # ParseError is its own severity outside Error. The idiom every example
    # shows - Severity = @('Error','Warning') - silently drops every parse
    # error, which turns the lint gate off for the one class of defect that
    # makes a module unloadable. Run 002 shipped a green Lint over a file that
    # could not be parsed at all; the build failed three stages later in Test,
    # naming the generated psm1 rather than the source.
    Severity     = @('ParseError', 'Error', 'Warning')

    ExcludeRules = @(
        # Export-ProducerGraphHtml writes a file only when given an explicit
        # -OutputPath, which is the caller's stated intent rather than a state
        # change it decided on. Stated here, next to the exclusion, because an
        # exclusion without a reason is one nobody can review.
        'PSUseShouldProcessForStateChangingFunctions'

        # 'Options' is a plural noun and the object genuinely is a set of
        # options; the singular reads as one option and would be wrong. The
        # name is also the one the ecosystem's acceptance test names, so
        # renaming it to satisfy a style rule would break the contract this
        # module exists to hold. Applies to New-GraphRenderOptions and its
        # private resolver.
        'PSUseSingularNouns'
    )

    Rules        = @{
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4 }
    }
}
