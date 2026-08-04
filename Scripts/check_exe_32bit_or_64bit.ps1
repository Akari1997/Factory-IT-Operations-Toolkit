$exe = "C:\Program Files\HBW\LEGO_HBW.exe"
$fs = [System.IO.File]::OpenRead($exe)
$br = New-Object System.IO.BinaryReader($fs)
$fs.Position = 0x3C
$peOffset = $br.ReadInt32()
$fs.Position = $peOffset + 4
$machine = $br.ReadUInt16()
$br.Close(); $fs.Close()
switch ($machine) {
  0x14c  {"32-bit (x86)"}
  0x8664 {"64-bit (x64)"}
  default {"Unknown: 0x{0:X}" -f $machine}
}