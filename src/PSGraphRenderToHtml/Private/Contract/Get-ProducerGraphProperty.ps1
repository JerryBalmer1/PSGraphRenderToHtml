function Get-ProducerGraphProperty {
    <#
    .SYNOPSIS
        Read a property that may be absent, from a PSCustomObject or a hashtable.
    .DESCRIPTION
        A producer graph arrives either as ConvertFrom-Json output
        (PSCustomObject) or as a hashtable a caller built in memory, and the two
        answer "is this property here" differently. Under Set-StrictMode reading
        an absent property of a PSCustomObject throws, so every optional field
        in this module goes through here.

        Absent and null are deliberately the same answer. The contract says an
        absent optional field means NOT STATED, and a caller that needs to tell
        the two apart is asking a question the contract does not answer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}
