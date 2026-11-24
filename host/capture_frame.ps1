param(
    [Parameter(Mandatory=$true)][string]$Port,
    [int]$Baud = 921600,
    [string]$Output = 'frame.ppm'
)
$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new(
    $Port, $Baud, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One)
$serial.ReadTimeout = 60000
$serial.Open()
try {
    $serial.DiscardInBuffer()
    Write-Host 'Serial port open. Press BTN0 on the Arty A7 to send the frame.'
    $magic = @(82, 65, 83, 84) # RAST
    $matched = 0
    while ($matched -lt 4) {
        $value = $serial.ReadByte()
        if ($value -eq $magic[$matched]) { $matched++ }
        elseif ($value -eq $magic[0]) { $matched = 1 }
        else { $matched = 0 }
    }
    $width = $serial.ReadByte() -bor ($serial.ReadByte() -shl 8)
    $height = $serial.ReadByte() -bor ($serial.ReadByte() -shl 8)
    if ($width -ne 320 -or $height -ne 240) {
        throw "Unexpected frame size: $width x $height"
    }
    $raw = [byte[]]::new($width * $height * 2)
    $offset = 0
    $serial.ReadTimeout = 10000
    while ($offset -lt $raw.Length) {
        $count = $serial.Read($raw, $offset, $raw.Length - $offset)
        if ($count -le 0) { throw 'Serial stream stopped early' }
        $offset += $count
    }

    $rgb = [byte[]]::new($width * $height * 3)
    for ($pixel = 0; $pixel -lt $width * $height; $pixel++) {
        $rgb565 = [int]$raw[2*$pixel] -bor ([int]$raw[2*$pixel+1] -shl 8)
        $rgb[3*$pixel]   = [byte][math]::Floor((($rgb565 -shr 11) -band 31) * 255 / 31)
        $rgb[3*$pixel+1] = [byte][math]::Floor((($rgb565 -shr 5) -band 63) * 255 / 63)
        $rgb[3*$pixel+2] = [byte][math]::Floor(($rgb565 -band 31) * 255 / 31)
    }
    $path = [System.IO.Path]::GetFullPath($Output)
    $stream = [System.IO.File]::Create($path)
    try {
        $header = [System.Text.Encoding]::ASCII.GetBytes("P6`n$width $height`n255`n")
        $stream.Write($header, 0, $header.Length)
        $stream.Write($rgb, 0, $rgb.Length)
    } finally { $stream.Dispose() }
    Write-Host "Saved $path"
} finally { $serial.Close() }
