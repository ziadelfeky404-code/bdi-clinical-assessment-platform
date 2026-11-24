param(
  [string]$Folder = 'D:\projects\التقويم والتشخيص\tests\_pages_all',
  [string]$Out = 'D:\projects\التقويم والتشخيص\tests\_ocr_fast'
)

Add-Type -AssemblyName System.Runtime.WindowsRuntime
. 'D:\projects\التقويم والتشخيص\tests\_winrt_await.ps1'
[Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType=WindowsRuntime] | Out-Null
[Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime] | Out-Null

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('ar-SA'))
if ($null -eq $engine) { throw 'Arabic OCR engine unavailable' }

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$files = Get-ChildItem -LiteralPath $Folder -Filter '*.png' | Sort-Object Name
foreach ($f in $files) {
  $dest = Join-Path $Out ($f.BaseName + '.txt')
  if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 3)) { continue }
  $stream = $null
  try {
    $file = [WinRTAwait]::Await([Windows.Storage.StorageFile]::GetFileFromPathAsync($f.FullName))
    $stream = [WinRTAwait]::Await($file.OpenAsync([Windows.Storage.FileAccessMode]::Read))
    $decoder = [WinRTAwait]::Await([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream))
    $bitmap = [WinRTAwait]::Await($decoder.GetSoftwareBitmapAsync())
    $result = [WinRTAwait]::Await($engine.RecognizeAsync($bitmap))
    [System.IO.File]::WriteAllText($dest, $result.Text, [System.Text.Encoding]::UTF8)
    Write-Output ("{0}: {1} chars" -f $f.Name, $result.Text.Length)
  } catch {
    Write-Output ("{0}: ERROR {1}" -f $f.Name, $_.Exception.Message)
  } finally {
    if ($null -ne $stream) { $stream.Dispose() }
  }
}
