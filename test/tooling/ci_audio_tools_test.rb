require 'json'
require 'open3'
require 'tempfile'
require 'yaml'
require_relative '../support/assertions'
include GameRoomTest::Assertions

root = File.expand_path('../..', __dir__)
workflow = YAML.safe_load(File.read(File.join(root, '.github/workflows/tests.yml')))
steps = workflow.fetch('jobs').fetch('test').fetch('steps')
step = steps.find { |item| item['name'] == 'Install audio validation tools' }
assert_equal("matrix.suite == 'tooling'", step.fetch('if'))
assert(steps.index(step) < steps.index { |item| item['name'] == 'Run tests' })
assert(!step.fetch('run').include?('choco install'), 'Audio setup still depends on the failing package feed')
assert(step.fetch('run').include?("$audioVersion = '9.0.2'"), 'Audio setup must pin a release')
assert(step.fetch('run').include?('Get-FileHash'), 'Audio setup must verify the pinned checksum before extraction')
artifact = steps.find { |item| item['name'] == 'Preserve scenario results' }
assert_equal("always() && hashFiles('test-results.json') != ''", artifact.fetch('if'),
  'An installation failure must not cause a second missing-report failure')

# Execute the actual CI step in isolated PowerShell processes. The doubles
# never install software, sleep, modify PATH or access the network.
prefix = <<~'POWERSHELL'
  param([string]$Mode)
  $ErrorActionPreference = 'Stop'
  $WarningPreference = 'SilentlyContinue'
  $global:ciAudioMode = $Mode
  $global:ciAudioAvailable = $Mode -in @('installed', 'broken')
  $global:ciAudioAttempts = 0
  $global:ciAudioSleeps = @()
  $global:ciAudioProbes = @()
  $global:ciAudioExtractions = 0
  $global:ciAudioPublished = @()
  $env:RUNNER_TEMP = 'C:/isolated-ci-audio'
  $env:GITHUB_PATH = 'C:/isolated-ci-audio/github-path.txt'
  function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    if ($global:ciAudioAvailable) { [pscustomobject]@{Name=$Name} }
  }
  function New-Item { param($ItemType, [switch]$Force, $Path) }
  function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec)
    $global:ciAudioAttempts++
    if ($Uri -ne 'https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.2-essentials_build.zip') { throw 'Unexpected archive publisher or version' }
    if ($global:ciAudioMode -eq 'unavailable' -or ($global:ciAudioMode -eq 'retry' -and $global:ciAudioAttempts -eq 1)) {
      throw 'Simulated HTTP 503'
    }
  }
  function Get-FileHash {
    param($LiteralPath, $Algorithm)
    $hash = '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba'
    if ($global:ciAudioMode -eq 'checksum' -or ($global:ciAudioMode -eq 'checksum_once' -and $global:ciAudioAttempts -eq 1)) {
      $hash = '0' * 64
    }
    [pscustomobject]@{Hash=$hash}
  }
  function Expand-Archive {
    param($LiteralPath, $DestinationPath, [switch]$Force)
    $global:ciAudioExtractions++
    $global:ciAudioAvailable = $global:ciAudioMode -ne 'empty_success' -or $global:ciAudioAttempts -ge 2
  }
  function Test-Path {
    param($LiteralPath, $PathType)
    return $global:ciAudioAvailable -and -not ($global:ciAudioMode -eq 'missing_probe' -and $LiteralPath.EndsWith('ffprobe.exe'))
  }
  function Add-Content {
    param($LiteralPath, $Value, $Encoding)
    if ($LiteralPath -ne $env:GITHUB_PATH -or $Encoding -ne 'utf8') { throw 'Unexpected PATH publication' }
    $global:ciAudioPublished += $Value
  }
  function Start-Sleep { param($Seconds); $global:ciAudioSleeps += $Seconds }
  function ffmpeg { $global:ciAudioProbes += 'ffmpeg'; $global:LASTEXITCODE = 0 }
  function ffprobe {
    $global:ciAudioProbes += 'ffprobe'
    $global:LASTEXITCODE = if ($global:ciAudioMode -in @('broken', 'broken_download')) { 1 } else { 0 }
  }
  $failed = $false
  try {
POWERSHELL
suffix = <<~'POWERSHELL'
  } catch { $failed = $true }
  @{attempts=$global:ciAudioAttempts; sleeps=@($global:ciAudioSleeps);
    extractions=$global:ciAudioExtractions; published=@($global:ciAudioPublished);
    probes=@($global:ciAudioProbes); failed=$failed} | ConvertTo-Json -Compress
POWERSHELL

cases = {
  'installed' => [0, 0, 0, [], false],
  'download' => [1, 1, 1, [], false],
  'retry' => [2, 1, 1, [10], false],
  'empty_success' => [2, 2, 1, [10], false],
  'unavailable' => [3, 0, 0, [10, 20], true],
  'checksum' => [3, 0, 0, [10, 20], true],
  'checksum_once' => [2, 1, 1, [10], false],
  'missing_probe' => [3, 3, 0, [10, 20], true],
  'broken' => [0, 0, 0, [], true],
  'broken_download' => [1, 1, 1, [], true]
}
Tempfile.create(['ci-audio-', '.ps1']) do |file|
  file.write(prefix + step.fetch('run') + "\n" + suffix)
  file.close
  cases.each do |mode, (attempts, extractions, published, sleeps, failed)|
    output, error, status = Open3.capture3('pwsh', '-NoProfile', '-NonInteractive', '-File', file.path, mode)
    assert(status.success?, "PowerShell fixture failed: #{error}")
    result = JSON.parse(output)
    assert_equal(attempts, result.fetch('attempts'), mode)
    assert_equal(extractions, result.fetch('extractions'), mode)
    assert_equal(published, result.fetch('published').size, mode)
    assert(result.fetch('published').all? { |path| path.tr('\\', '/').end_with?('ffmpeg-9.0.2-essentials_build/bin') }, mode)
    assert_equal(sleeps, result.fetch('sleeps'), mode)
    assert_equal(failed, result.fetch('failed'), mode)
    assert_equal(%w[unavailable checksum missing_probe].include?(mode) ? [] : %w[ffmpeg ffprobe], result.fetch('probes'), mode)
  end
end
puts 'PASS CI audio tools: pinned publisher/hash, installed tools, verified download, HTTP retry, checksum rejection before extraction, missing tools, PATH publication, broken binaries and missing-report handling'
