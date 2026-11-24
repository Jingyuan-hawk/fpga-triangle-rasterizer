$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $projectDir 'sim\build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$out = Join-Path $buildDir 'tb_arty_a7_top.vvp'
& iverilog -g2012 -s tb_arty_a7_top -o $out `
    (Join-Path $projectDir 'rtl\rasterizer1.sv') `
    (Join-Path $projectDir 'rtl\framebuffer_rgb565.sv') `
    (Join-Path $projectDir 'rtl\raster_top.sv') `
    (Join-Path $projectDir 'board\uart_tx.sv') `
    (Join-Path $projectDir 'board\arty_a7_top.sv') `
    (Join-Path $projectDir 'tb\tb_arty_a7_top.sv')
if ($LASTEXITCODE -ne 0) { throw 'Icarus Verilog compile failed' }
& vvp $out
if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
