@{
    # The ONLY place build dependencies are pinned. Runtime dependencies belong
    # in the manifest's RequiredModules, which is a different thing: this file
    # says what is needed to build, that one says what is needed to run.
    InvokeBuild      = @{ MinimumVersion = '5.10.0' }
    Pester           = @{ RequiredVersion = '6.1.0' }
    PSScriptAnalyzer = @{ MinimumVersion = '1.21.0' }
}
