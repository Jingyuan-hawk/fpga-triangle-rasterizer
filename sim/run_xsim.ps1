param([string]$VivadoBin = 'D:\AMDDesignTools\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
foreach ($tool in @($xvlog,$xelab,$xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Tool not found: $tool" }
}
$common = @(
    (Join-Path $root 'rtl\rasterizer4.sv'),
    (Join-Path $root 'rtl\framebuffer_rgb565_4bank.sv'),
    (Join-Path $root 'rtl\raster_top.sv')
)
$tests = @(
    @{ Name='generic'; Top='tb_raster_top'; Extra=@(
        (Join-Path $root 'tb\tb_raster_top.sv'));
       Expected='PASS: clear, shared edge, clipping, winding, fractional vertices' },
    @{ Name='scene'; Top='tb_scene_frame'; Extra=@(
        (Join-Path $root 'tb\tb_scene_frame.sv'));
       Expected='PASS: full 320x240 scene matches the reference' },
    @{ Name='arty'; Top='tb_arty_a7_top'; Extra=@(
        (Join-Path $root 'board\uart_tx.sv'),
        (Join-Path $root 'board\arty_a7_top.sv'),
        (Join-Path $root 'tb\tb_arty_a7_top.sv'));
       Expected='PASS: Arty top drew frame and sent UART timing / first pixel' }
)
foreach ($test in $tests) {
    $directory = Join-Path $root ("build\xsim_one_" + $test.Name)
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    Push-Location $directory
    try {
        $files = $common + $test.Extra
        & $xvlog -sv @files
        if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $($test.Name)" }
        $snapshot = "tb_one_$($test.Name)"
        & $xelab $test.Top -s $snapshot
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $($test.Name)" }
        $result = & $xsim $snapshot -runall 2>&1
        $result | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0 -or (($result -join "`n") -notlike "*$($test.Expected)*")) {
            throw "Simulation failed: $($test.Name)"
        }
    } finally { Pop-Location }
}
