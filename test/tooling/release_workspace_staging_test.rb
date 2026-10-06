require 'tmpdir'
require 'rbconfig'
require_relative '../support/assertions'
require_relative '../../tools/stage-release'
include GameRoomTest::Assertions

def workspace_source(source)
  GameRoomReleaseFiles::REQUIRED_FILES.each do |relative|
    path = File.join(source, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, relative == 'manifest.json' ? '{}' : "\n")
  end
  source
end

def workspace_git(source, *arguments)
  output, status = Open3.capture2e('git', '-C', source, *arguments)
  assert(status.success?, "Git fixture failed: #{output}")
end

def workspace_link(target, link)
  if File::ALT_SEPARATOR == '\\'
    output, status = Open3.capture2e({'GR_LINK_TARGET' => target, 'GR_LINK_PATH' => link},
      'powershell.exe', '-NoProfile', '-NonInteractive', '-Command',
      'New-Item -ItemType Junction -Path $env:GR_LINK_PATH -Target $env:GR_LINK_TARGET -ErrorAction Stop | Out-Null')
    assert(status.success?, "Cannot create junction fixture: #{output}")
  else
    File.symlink(target, link)
  end
  yield
ensure
  File.unlink(link) if File.symlink?(link)
end

Dir.mktmpdir('gw') do |root|
  source = workspace_source(File.join(root, 's'))
  workspace = File.join(source, 'Workspace')
  Dir.mkdir(workspace)
  original = GameRoomReleaseFiles.snapshot(source)
  %w[Workspace/lib/helper.rb Workspace/locale/PL.mo Workspace/README.md
     Workspace/content/HELPER_NOTICE.md Workspace/Audio/helper.opus].each do |relative|
    path = File.join(source, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, 'private helper, not runtime')
    assert(!GameRoomReleaseFiles.allowed?(relative), "Workspace helper admitted: #{relative}")
  end
  assert_equal(original, GameRoomReleaseFiles.snapshot(source))
  destination = File.join(workspace, 'out')
  assert_raises(RuntimeError) { GameRoomReleaseFiles.stage(source, destination) }
  assert(!File.exist?(destination), 'default staging wrote inside source')

  inventory = File.join(workspace, 'inventory.json')
  assert_equal(original, GameRoomReleaseStage.run(source: source, destination: destination,
    manifest: inventory, workspace_staging: true))
  assert_equal(original, GameRoomReleaseStage.run(source: destination, manifest: inventory, check: true))
  assert_equal(original, GameRoomReleaseFiles.snapshot(source), 'staging changed source inventory')
  assert(!File.exist?(File.join(destination, 'Workspace')), 'helper files entered staging')
  assert_raises(RuntimeError) { GameRoomReleaseFiles.stage(source, destination, workspace_staging: true) }
  assert_equal(original, GameRoomReleaseFiles.snapshot(destination), 'existing stage changed')

  %w[trash Forme Workspace-other].each { |directory| Dir.mkdir(File.join(source, directory)) }
  rejected = [source, workspace, File.join(workspace, 'inventory.json'), File.join(source, 'out'),
    File.join(root, 'out'), File.join(source, 'trash/out'), File.join(source, 'Forme/out'),
    File.join(source, 'lib/out'), File.join(source, 'content/out'), File.join(source, 'Workspace-other/out'),
    File.join(workspace, '../lib/out'), File.join(workspace, '../../out'), File.join(workspace, 'lib/out')]
  rejected.each do |path|
    existed = File.exist?(path)
    error = assert_raises(StandardError) { GameRoomReleaseFiles.stage(source, path, workspace_staging: true) }
    assert(error.is_a?(RuntimeError) || error.is_a?(ArgumentError), "Unexpected rejection: #{error}")
    assert_equal(existed, File.exist?(path), "Rejected destination was created: #{path}")
  end
  assert_raises(Errno::ENOENT) do
    GameRoomReleaseFiles.stage(source, File.join(workspace, 'missing/out'), workspace_staging: true)
  end
  assert(!File.exist?(File.join(workspace, 'missing')), 'missing parent was created')
  assert_raises(ArgumentError) { GameRoomReleaseStage.run(source: source, workspace_staging: true) }
  assert_raises(ArgumentError) do
    GameRoomReleaseStage.run(source: source, manifest: inventory, check: true, workspace_staging: true)
  end
  sidecar_destination = File.join(workspace, 'side')
  assert_raises(ArgumentError) do
    GameRoomReleaseStage.run(source: source, destination: sidecar_destination,
      manifest: File.join(sidecar_destination, 'inventory.json'), workspace_staging: true)
  end
  assert(!File.exist?(sidecar_destination), 'invalid sidecar left a Workspace staging tree')

  command = File.expand_path('../../tools/stage-release.rb', __dir__)
  cli_destination = File.join(workspace, 'cli')
  output, status = Open3.capture2e(RbConfig.ruby, command, '--source', source, '--destination', cli_destination)
  assert(!status.success? && output.include?('outside the source tree'), 'CLI default admitted Workspace')
  output, status = Open3.capture2e(RbConfig.ruby, command, '--source', source,
    '--destination', cli_destination, '--workspace-staging')
  assert(status.success?, output)
  assert_equal(original.fetch(:sha256), JSON.parse(output).fetch('sha256'))
  assert_equal(original, GameRoomReleaseFiles.snapshot(source), 'repeat staging included earlier staging')
  output, status = Open3.capture2e(RbConfig.ruby, command, '--source', source,
    '--destination', File.join(source, 'lib/cli'), '--workspace-staging')
  assert(!status.success? && output.include?('direct subdirectory'), 'CLI admitted a code destination')
  assert(!File.exist?(File.join(source, 'lib/cli')), 'CLI wrote into code')
  output, status = Open3.capture2e(RbConfig.ruby, command, '--source', source, '--workspace-staging')
  assert(!status.success? && output.include?('needs a destination'), 'CLI ignored a misplaced opt-in')

  workspace_git(source, 'init', '--quiet')
  git_destination = File.join(workspace, 'git')
  assert_raises(RuntimeError) { GameRoomReleaseFiles.stage(source, git_destination, workspace_staging: true) }
  assert(!File.exist?(git_destination), 'unignored Workspace was staged')
  ignore = File.join(source, '.gitignore')
  assert(!File.exist?(ignore), 'staging created .gitignore')
  assert_equal(original.fetch(:files).map { |row| row.fetch(:path) },
    GameRoomReleaseFiles.stage(source, File.join(root, 'default')))
  ["/Workspace/git/\n", "/Workspace/\n!/Workspace/\n"].each do |rules|
    File.write(ignore, rules)
    assert_raises(RuntimeError) { GameRoomReleaseFiles.stage(source, git_destination, workspace_staging: true) }
    assert_equal(rules, File.read(ignore), 'staging rewrote ignore rules')
    assert(!File.exist?(git_destination), 'insufficient ignore rules allowed staging')
  end
  File.write(ignore, "/Workspace/\n")
  assert_equal(original, GameRoomReleaseStage.run(source: source, destination: git_destination, workspace_staging: true))
  assert_equal("/Workspace/\n", File.read(ignore))
  assert_equal(original, GameRoomReleaseFiles.snapshot(source))

  linked_source = workspace_source(File.join(root, 'l'))
  linked_workspace = File.join(linked_source, 'Workspace')
  assert_raises(Errno::ENOENT) do
    GameRoomReleaseFiles.stage(linked_source, File.join(linked_workspace, 'out'), workspace_staging: true)
  end
  assert(!File.exist?(linked_workspace), 'staging created the Workspace root')
  [File.join(linked_source, 'lib'), root].each do |target|
    workspace_link(target, linked_workspace) do
      assert_raises(ArgumentError) do
        GameRoomReleaseFiles.stage(linked_source, File.join(linked_workspace, 'escape'), workspace_staging: true)
      end
      assert(!File.exist?(File.join(target, 'escape')), 'redirected Workspace was staged')
    end
  end
  workspace_link(File.join(source, 'lib'), File.join(workspace, 'link')) do
    assert_raises(ArgumentError) do
      GameRoomReleaseFiles.stage(source, File.join(workspace, 'link/escape'), workspace_staging: true)
    end
    assert(!File.exist?(File.join(source, 'lib/escape')), 'junction escaped Workspace')
  end
  workspace_link(workspace, File.join(root, 'alias')) do
    assert_raises(RuntimeError) { GameRoomReleaseFiles.stage(source, File.join(root, 'alias/escape')) }
    assert_raises(ArgumentError) do
      GameRoomReleaseFiles.stage(source, File.join(root, 'alias/escape'), workspace_staging: true)
    end
    assert(!File.exist?(File.join(workspace, 'escape')), 'default staging followed a link into source')
  end
  workspace_link(workspace, File.join(source, 'lib/alias')) do
    assert_raises(ArgumentError) do
      GameRoomReleaseFiles.stage(source, File.join(source, 'lib/alias/escape'), workspace_staging: true)
    end
    assert(!File.exist?(File.join(workspace, 'escape')), 'code alias was accepted as a Workspace destination')
  end

  if File::ALT_SEPARATOR == '\\'
    long_destination = File.join(workspace, 'long' * 21)
    error = assert_raises(RuntimeError) do
      GameRoomReleaseStage.run(source: source, destination: long_destination, workspace_staging: true)
    end
    assert(error.message.include?('at most 80 characters'), 'Windows staging length limit was bypassed')
    assert(!File.exist?(long_destination), 'overlong destination was created')
    case_destination = File.join(source.upcase, 'WORKSPACE', 'case')
    assert_equal(original, GameRoomReleaseStage.run(source: source, destination: case_destination, workspace_staging: true))
    assert_raises(ArgumentError) do
      GameRoomReleaseFiles.stage(source, File.join(source.upcase, 'LIB', 'escape'), workspace_staging: true)
    end
  else
    Dir.mkdir(File.join(source, 'workspace'))
    assert_raises(ArgumentError) do
      GameRoomReleaseFiles.stage(source, File.join(source, 'workspace/escape'), workspace_staging: true)
    end
  end

  workspace_git(root, 'init', '--quiet')
  Dir.mkdir(linked_workspace)
  nested_destination = File.join(linked_workspace, 'out')
  assert_raises(RuntimeError) { GameRoomReleaseFiles.stage(linked_source, nested_destination, workspace_staging: true) }
  File.write(File.join(root, '.gitignore'), "/l/Workspace/\n")
  assert_equal(GameRoomReleaseFiles.files(linked_source),
    GameRoomReleaseFiles.stage(linked_source, nested_destination, workspace_staging: true))
end
puts 'PASS explicit Workspace staging: canonical boundaries, Git ignore, CLI and unchanged runtime inventory'
