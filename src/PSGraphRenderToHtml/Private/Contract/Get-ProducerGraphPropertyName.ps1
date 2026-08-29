function Get-ProducerGraphPropertyName {
    <#
    .SYNOPSIS
        The property names of a PSCustomObject or a hashtable, uniformly.
    .DESCRIPTION
        Same reason as Get-ProducerGraphProperty: a producer graph arrives
        either as ConvertFrom-Json output or as a hashtable built in memory,
        and enumerating their keys is two different expressions.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowNull()] [object] $InputObject)

    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [System.Collections.IDictionary]) { return @($InputObject.Keys) }
    return @($InputObject.PSObject.Properties.Name)
}
