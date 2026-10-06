param([switch]$ChinaMirrors)
$ErrorActionPreference = "Stop"
$BuildArguments = @()
if ($ChinaMirrors) { $BuildArguments += "--cn-mirrors" }
python (Join-Path $PSScriptRoot "build_windows.py") @BuildArguments
exit $LASTEXITCODE
