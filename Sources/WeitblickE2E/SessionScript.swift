import Foundation

/// `clip.ps1`, run inside the RDP session (Win+R) so it uses the session's clipboard. Each action
/// writes `<action>.done` into the shared directory when finished ("error: …" on failure).
enum SessionScript {
    /// Typed into the Run dialog. Short PowerShell switches keep the typing quick.
    static func command(_ action: String) -> String {
        #"powershell -nop -sta -w hidden -ep bypass -f C:\weitblick-e2e\clip.ps1 "# + action
    }

    // Test patterns, shared with the checks on the Mac side.
    static let imageSize = (width: 83, height: 57)
    static func imagePixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        (UInt8((x * 3) % 256), UInt8((y * 4) % 256), UInt8((x + y) % 256))
    }

    static let pngSize = (width: 64, height: 40)
    static func pngPixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        (UInt8((x * 4) % 256), UInt8((y * 6) % 256), 200, UInt8(55 + (x * 3) % 200))
    }

    static let rtf = #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0 Arial;}}\f0\fs24 \b Gr\'fc\'dfe\b0  aus RTF\par}"#
    static let htmlFragment = "<p><b>Grüße</b> aus <i>Windows</i> &amp; ✓</p>"
    static let htmlText = "Grüße aus Windows & ✓"

    /// UTF-8 with BOM: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
    static var data: Data { Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8) }

    private static let source = #"""
    param([string]$Action, [string]$Format)
    $ErrorActionPreference = 'Stop'
    $dir = 'C:\weitblick-e2e'
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    function Done([string]$text) { [IO.File]::WriteAllText("$dir\$Action.done", $text) }

    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Threading;
    public static class RawClipboard {
        [DllImport("user32.dll", SetLastError = true)] static extern bool OpenClipboard(IntPtr owner);
        [DllImport("user32.dll")] static extern bool CloseClipboard();
        [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
        [DllImport("user32.dll")] static extern uint EnumClipboardFormats(uint format);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClipboardFormatName(uint format, StringBuilder name, int size);
        [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr memory);
        [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);
        [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr memory);
        static void Open() {
            for (int i = 0; i < 40; i++) { if (OpenClipboard(IntPtr.Zero)) return; Thread.Sleep(50); }
            throw new Exception("OpenClipboard failed");
        }
        public static byte[] Get(string name) {
            uint format = RegisterClipboardFormat(name);
            Open();
            try {
                IntPtr handle = GetClipboardData(format);
                if (handle == IntPtr.Zero) return null;
                IntPtr pointer = GlobalLock(handle);
                byte[] bytes = new byte[(int)GlobalSize(handle)];
                Marshal.Copy(pointer, bytes, 0, bytes.Length);
                GlobalUnlock(handle);
                return bytes;
            } finally { CloseClipboard(); }
        }
        public static string Formats() {
            Open();
            try {
                var names = new StringBuilder();
                for (uint format = EnumClipboardFormats(0); format != 0; format = EnumClipboardFormats(format)) {
                    var name = new StringBuilder(256);
                    names.Append(GetClipboardFormatName(format, name, 256) > 0 ? name.ToString() : format.ToString()).Append(';');
                }
                return names.ToString();
            } finally { CloseClipboard(); }
        }
    }
    '@

    try {
      switch ($Action) {
        'save-image' {
          $image = [Windows.Forms.Clipboard]::GetImage()
          if ($image -eq $null) { Done ('none; formats: ' + [RawClipboard]::Formats()); break }
          $image.Save("$dir\image.png", [Drawing.Imaging.ImageFormat]::Png)
          Done ('{0}x{1}; formats: {2}' -f $image.Width, $image.Height, [RawClipboard]::Formats())
        }
        'set-image' {
          $bitmap = New-Object Drawing.Bitmap 83, 57, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)
          for ($x = 0; $x -lt 83; $x++) { for ($y = 0; $y -lt 57; $y++) {
            $bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb(($x * 3) % 256, ($y * 4) % 256, ($x + $y) % 256))
          } }
          [Windows.Forms.Clipboard]::SetImage($bitmap)
          Done ('ok; formats: ' + [RawClipboard]::Formats())
        }
        'set-png' {
          $bitmap = New-Object Drawing.Bitmap 64, 40, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
          for ($x = 0; $x -lt 64; $x++) { for ($y = 0; $y -lt 40; $y++) {
            $bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb(55 + ($x * 3) % 200, ($x * 4) % 256, ($y * 6) % 256, 200))
          } }
          $png = New-Object IO.MemoryStream
          $bitmap.Save($png, [Drawing.Imaging.ImageFormat]::Png)
          $data = New-Object Windows.Forms.DataObject
          $data.SetData('PNG', $false, $png)
          $data.SetImage($bitmap)
          [Windows.Forms.Clipboard]::SetDataObject($data, $true)
          Done ('ok; formats: ' + [RawClipboard]::Formats())
        }
        'set-rtf' {
          [Windows.Forms.Clipboard]::SetText('{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0 Arial;}}\f0\fs24 \b Gr\''fc\''dfe\b0  aus RTF\par}', [Windows.Forms.TextDataFormat]::Rtf)
          Done ('ok; formats: ' + [RawClipboard]::Formats())
        }
        'set-html' {
          $utf8 = New-Object Text.UTF8Encoding($false)
          $fragment = '<p><b>Grüße</b> aus <i>Windows</i> &amp; ✓</p>'
          $before = '<html><head><title>Weitblick Remote</title></head><body><!--StartFragment-->'
          $after = '<!--EndFragment--></body></html>'
          $template = "Version:0.9`r`nStartHTML:{0:D10}`r`nEndHTML:{1:D10}`r`nStartFragment:{2:D10}`r`nEndFragment:{3:D10}`r`n"
          $headerLength = $utf8.GetByteCount(($template -f 0, 0, 0, 0))
          $startFragment = $headerLength + $utf8.GetByteCount($before)
          $endFragment = $startFragment + $utf8.GetByteCount($fragment)
          $endHTML = $endFragment + $utf8.GetByteCount($after)
          $html = ($template -f $headerLength, $endHTML, $startFragment, $endFragment) + $before + $fragment + $after
          $data = New-Object Windows.Forms.DataObject
          [byte[]]$bytes = $utf8.GetBytes($html) + [byte]0
          $data.SetData('HTML Format', (New-Object IO.MemoryStream(, $bytes)))
          $data.SetData([Windows.Forms.DataFormats]::UnicodeText, 'Grüße aus Windows & ✓')
          [Windows.Forms.Clipboard]::SetDataObject($data, $true)
          Done ('ok; formats: ' + [RawClipboard]::Formats())
        }
        'dump' {
          $bytes = [RawClipboard]::Get($Format)
          if ($bytes -eq $null) { Done ('none; formats: ' + [RawClipboard]::Formats()); break }
          [IO.File]::WriteAllText("$dir\dump.b64", [Convert]::ToBase64String($bytes))
          Done ('{0} bytes; formats: {1}' -f $bytes.Length, [RawClipboard]::Formats())
        }
        default { Done "error: unknown action $Action" }
      }
    } catch {
      Done ('error: ' + $_)
    }
    """#
}
