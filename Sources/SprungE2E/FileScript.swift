import Foundation

/// `files.ps1`, run inside the RDP session (Win+R) like `clip.ps1`: drive redirection, files over
/// the clipboard, audio and printers. Each action writes `<action>.done` ("ok …" or "error: …").
/// File lists are written as manifests, one "relative\path|size|sha256" line per file
/// ("relative\path|dir|" for folders).
enum FileScript {
    static let name = "files.ps1"
    static let shareName = "sprung-e2e"

    static func command(_ action: String) -> String {
        #"powershell -nop -sta -w hidden -ep bypass -f C:\sprung-e2e\files.ps1 "# + action
    }

    /// UTF-8 with BOM: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
    static var data: Data { Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8) }

    private static let source = #"""
    param([string]$Action, [string]$Arg1, [string]$Arg2)
    $ErrorActionPreference = 'Stop'
    $dir = 'C:\sprung-e2e'
    Add-Type -AssemblyName System.Windows.Forms
    $utf8 = New-Object Text.UTF8Encoding($false)
    function Done([string]$text) { [IO.File]::WriteAllText("$dir\$Action.done", $text, $utf8) }
    function Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
    function Sha([string]$path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() }
    function Manifest([string]$root) {
      $lines = foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -Force) {
        $relative = $item.FullName.Substring($root.Length + 1)
        if ($item.PSIsContainer) { "$relative|dir|" } else { "$relative|$($item.Length)|$(Sha $item.FullName)" }
      }
      $lines -join "`n"
    }
    function RandomFile([string]$path, [int]$megabytes) {
      $random = [Security.Cryptography.RandomNumberGenerator]::Create()
      $buffer = New-Object byte[] (1MB)
      $stream = [IO.File]::Create($path)
      try { for ($i = 0; $i -lt $megabytes; $i++) { $random.GetBytes($buffer); $stream.Write($buffer, 0, $buffer.Length) } }
      finally { $stream.Close() }
    }
    function Formats() { ([Windows.Forms.Clipboard]::GetDataObject().GetFormats() -join ';') }

    try {
      switch ($Action) {
        'drive' {
          $share = "\\tsclient\$Arg1"
          if (-not (Test-Path -LiteralPath $share)) { Done "error: $share not found"; break }
          $listing = (Get-ChildItem -LiteralPath $share -Force | ForEach-Object Name | Sort-Object) -join ';'
          $fromMac = [IO.File]::ReadAllText("$share\vom-Mac-Grüße.txt", $utf8)
          Utf8 "$share\von-Windows-Äß.txt" 'Hallo vom Windows ✓ Äß'
          New-Item -ItemType Directory -Force "$share\Ordner-Ü" | Out-Null
          Utf8 "$share\Ordner-Ü\innen.txt" 'innen'
          Rename-Item -LiteralPath "$share\umbenennen.txt" -NewName 'umbenannt-é.txt'
          Remove-Item -LiteralPath "$share\löschen.txt"
          $watch = [Diagnostics.Stopwatch]::StartNew()
          Copy-Item -LiteralPath "$share\groß-100MB.bin" "$dir\drive-copy.bin"
          $readSeconds = $watch.Elapsed.TotalSeconds
          $readHash = Sha "$dir\drive-copy.bin"
          $watch.Restart()
          Copy-Item -LiteralPath "$dir\drive-copy.bin" "$share\zurück-100MB.bin"
          $writeSeconds = $watch.Elapsed.TotalSeconds
          Remove-Item -Force "$dir\drive-copy.bin"
          Done ("ok`nlisting=$listing`nfromMac=$fromMac`nreadHash=$readHash`n" +
                "readSeconds=$readSeconds`nwriteSeconds=$writeSeconds")
        }
        'paste' {
          # Explorer's paste: the shell reads FileGroupDescriptorW and FileContents from the clipboard.
          $target = "$dir\paste"
          Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $target
          New-Item -ItemType Directory -Force $target | Out-Null
          $formats = Formats
          $watch = [Diagnostics.Stopwatch]::StartNew()
          (New-Object -ComObject Shell.Application).NameSpace($target).Self.InvokeVerb('paste')
          $deadline = (Get-Date).AddSeconds(240)
          do {
            Start-Sleep -Milliseconds 250
            $files = @(Get-ChildItem -LiteralPath $target -Recurse -Force -File)
            $bytes = [long]($files | Measure-Object Length -Sum).Sum
          } while (($files.Count -lt [int]$Arg1 -or $bytes -lt [long]$Arg2) -and (Get-Date) -lt $deadline)
          $seconds = $watch.Elapsed.TotalSeconds
          Start-Sleep -Seconds 1 # the copy engine closes the last file
          [IO.File]::WriteAllText("$dir\paste.manifest", (Manifest $target), $utf8)
          Done ("ok; {0} files, {1} bytes in {2:F1} s; formats: {3}" -f $files.Count, $bytes, $seconds, $formats)
        }
        'copy-files' {
          # Like copying in Explorer: CF_HDROP of files and a folder (rdpclip offers them as streams).
          $out = "$dir\out"
          Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $out
          New-Item -ItemType Directory -Force "$out\Windows-Ordner-ß\sub", "$out\Windows-Ordner-ß\leer" | Out-Null
          Utf8 "$out\Bericht-Ä.txt" 'Bericht vom Windows: Grüße ✓'
          Utf8 "$out\Windows-Ordner-ß\a.txt" 'a'
          RandomFile "$out\Windows-Ordner-ß\sub\b.bin" 1
          RandomFile "$out\groß-öü-50MB.bin" 50
          [IO.File]::WriteAllText("$dir\copy.manifest", (Manifest $out), $utf8)
          $list = New-Object Collections.Specialized.StringCollection
          foreach ($name in 'Bericht-Ä.txt', 'Windows-Ordner-ß', 'groß-öü-50MB.bin') { [void]$list.Add("$out\$name") }
          [Windows.Forms.Clipboard]::SetFileDropList($list)
          Done ('ok; formats: ' + (Formats))
        }
        'play-sound' {
          # Two seconds at amplitude 1 of 32767: audio data flows, nobody hears it.
          $rate = 44100; $samples = $rate * 2
          $wav = New-Object IO.MemoryStream
          $writer = New-Object IO.BinaryWriter($wav)
          $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int](36 + $samples * 4))
          $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([int]16); $writer.Write([int16]1)
          $writer.Write([int16]2); $writer.Write([int]$rate); $writer.Write([int]($rate * 4)); $writer.Write([int16]4)
          $writer.Write([int16]16); $writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([int]($samples * 4))
          $frame = [byte[]](1, 0, 1, 0, 255, 255, 255, 255)
          for ($i = 0; $i -lt $samples / 2; $i++) { $writer.Write($frame) }
          $writer.Flush(); $wav.Position = 0
          (New-Object Media.SoundPlayer $wav).PlaySync()
          Done 'ok'
        }
        'printers' {
          Done ('ok; ' + ((Get-Printer | ForEach-Object { '{0} [{1}]' -f $_.Name, $_.PortName }) -join ';'))
        }
        default { Done "error: unknown action $Action" }
      }
    } catch {
      Done ('error: ' + $_)
    }
    """#
}
