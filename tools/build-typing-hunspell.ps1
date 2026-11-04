param([Parameter(Mandatory=$true)][string]$Source, [Parameter(Mandatory=$true)][string]$Output, [string[]]$CompilerFlags = @())
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path -LiteralPath $Source).Path
$header = Join-Path $Source 'src/hunspell/affixmgr.hxx'
$text = [IO.File]::ReadAllText($header)
if (!$text.Contains('friend class ManiaWordExporter;')) {
  if (!$text.Contains('class AffixMgr {')) { throw 'Unsupported Hunspell source' }
  $text = $text.Replace('class AffixMgr {', "class AffixMgr {`n  friend class ManiaWordExporter; // Local build-time enumeration access only.")
  [IO.File]::WriteAllText($header, $text, [Text.UTF8Encoding]::new($false))
}
[IO.File]::WriteAllText((Join-Path $Source 'src/hunspell/hunvisapi.h'), "#pragma once`n#define LIBHUNSPELL_DLL_EXPORTED`n")
$native = Get-ChildItem -LiteralPath (Join-Path $Source 'src/hunspell') -Filter '*.cxx' | ForEach-Object { $_.FullName }
& g++ -std=c++17 -O2 -DHUNSPELL_STATIC -static-libgcc -static-libstdc++ @CompilerFlags "-I$Source/src/hunspell" (Join-Path $PSScriptRoot 'support/typing_hunspell_export.cxx') @native -o $Output
if ($LASTEXITCODE -ne 0) { throw 'Hunspell exporter build failed' }
