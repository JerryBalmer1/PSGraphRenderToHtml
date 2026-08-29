# DEV LOADER. Not the build product.
#
# The build concatenates Private/** then Public/* into output/<Name>/<Name>.psm1
# and that generated file is what ships. This file exists so the manifest in
# src/ is importable directly, which is what lets a test - and the harness
# acceptance suite - import the module without building first.
#
# It dot-sources rather than concatenates, so $script:ModuleRoot means the same
# thing under both loaders and any asset resolved from it is found either way.
$script:ModuleRoot = $PSScriptRoot

foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -Recurse -File | Sort-Object FullName) +
    @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter *.ps1 -File | Sort-Object Name)) {
    . $file.FullName
}

Export-ModuleMember -Function 'ConvertTo-GraphRenderViewModel', 'Export-ProducerGraphHtml', 'New-GraphRenderOptions', 'Test-ProducerGraph'
