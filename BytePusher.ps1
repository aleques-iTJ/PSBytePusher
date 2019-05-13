# Implementation of the BytePusher virtual machine
# https://esolangs.org/wiki/BytePusher


# Effectively a hack to grab the HWND on the console window
$sig_GetForegroundWindow = @"
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
"@

Add-Type -MemberDefinition $sig_GetForegroundWindow -Name Win32 -Namespace Native
Add-Type -AssemblyName System.Drawing


# https://esolangs.org/wiki/BytePusher#Specifications
$memory      = [Byte[]]::new(0x01000000) # 16mib, 1024*1024*16
$pc          = 0                         # Program counter
$instruction = 0                         # Current instruction index, 65536 run per frame

# https://stackoverflow.com/questions/24701703/c-sharp-faster-alternatives-to-setpixel-and-getpixel-for-bitmaps-for-windows-f
$graphics    = [System.Drawing.Graphics]::FromHwnd([Native.Win32]::GetForegroundWindow())
$bufferData  = [UInt32[]]::new(256 * 256)
$pointer     = [System.Runtime.InteropServices.GCHandle]::Alloc($bufferData, [System.Runtime.InteropServices.GCHandleType]::Pinned)
$backbuffer  = [System.Drawing.Bitmap]::new(256, 256, 256 * 4, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb, $pointer.AddrOfPinnedObject())


# Load a rom
$rom = [Byte[]](Get-Content -Encoding Byte)
[Array]::Copy($rom, $memory, $rom.Length)

# Build the palette, a 6*6*6 cube of web-safe colors
# https://esolangs.org/wiki/BytePusher#Colors
$index   = 0
$palette = [UInt32[]]::new(256) # 216, 6*6*6 colors
for ($r = 0; $r -le 0xFF; $r += 0x33)
{
    for ($g = 0; $g -le 0xFF; $g += 0x33)
    {
        for ($b = 0; $b -le 0xFF; $b += 0x33)
        {
            # PowerShell seems dead set on treating 0xFF000000 
            # as a signed int no matter what you do, because reasons

            # ... so here we are, casting a string instead
            $color = [UInt32]"0xFF000000"

            $color = $color -bor ($r -shl 16)
            $color = $color -bor ($g -shl 8)
            $color = $color -bor  $b

            $palette[$index++] = $color
        }
    }
}

# Colors 216-255 are just black, but we need to set the alpha channel
for (;$index -le 0xFF; $index++)
{
    $palette[$index] = [UInt32]"0xFF000000"
}

# Step the CPU
# https://esolangs.org/wiki/BytePusher#Outer_loop
while ($true)
{
    # https://esolangs.org/wiki/BytePusher#Inner_loop

    # As for where the PC starts at, see the memory map
    # https://esolangs.org/wiki/BytePusher#Memory_map
    $instruction = 0
    $pc          = (([UInt32]$memory[2]) -shl 16) -bor (([UInt32]$memory[3]) -shl 8) -bor [UInt32]$memory[4]
    $pc          = (([UInt32]$memory[2]) -shl 16) -bor (([UInt32]$memory[3]) -shl 8) -bor [UInt32]$memory[4]

    do
    {
        # A, B, C are 3 sequential 24-bit addresses
        $a = (([UInt32]$memory[($pc + 0)]) -shl 16) -bor (([UInt32]$memory[($pc + 1)]) -shl 8) -bor ([UInt32]$memory[($pc + 2)])
        $b = (([UInt32]$memory[($pc + 3)]) -shl 16) -bor (([UInt32]$memory[($pc + 4)]) -shl 8) -bor ([UInt32]$memory[($pc + 5)])    
        $c = (([UInt32]$memory[($pc + 6)]) -shl 16) -bor (([UInt32]$memory[($pc + 7)]) -shl 8) -bor ([UInt32]$memory[($pc + 8)])

        # "Copy 1 byte from A to B, then jump to C."
        $memory[$b] = $memory[$a]
        $pc         = $c
    } while (++$instruction -le 65536)


    # Rendering
    # See the memory map for a bit more info
    $graphicsStart = ([UInt32]$memory[5]) -shl 16 # Points to where the graphics data starts
    $graphicsData  = [Byte[]]::new(256 * 256)     # 256x256 pixel array, 1 byte per pixel
    [Array]::Copy($memory, $graphicsStart, $graphicsData, 0, 256 * 256)    

    for ($i = 0; $i -lt $graphicsData.Length; $i++)
    {
        # Color wise, each pixel to draw is just an index into the palette
        $bufferData[$i] = $palette[$graphicsData[$i]]
    }

    # Blit
    $graphics.DrawImage($backbuffer, [System.Drawing.Point]::new(0, 0))
}
