require 'open3'
require 'rbconfig'

root = File.expand_path('../..', __dir__)
code = <<~'RUBY'
  require_relative 'lib/game_history_navigation'
  require_relative 'lib/game_shortcut_bindings'
  require_relative 'lib/game_layout'
  raise 'Input data modules loaded native Form' if defined?(Form)
  raise 'Missing shared press-time helper' unless GameRoomUI.respond_to?(:modifiers_when_pressed)
  puts 'Headless input definitions loaded without controls'
RUBY
output, status = Open3.capture2e(RbConfig.ruby, '-e', code, chdir: root)
raise output unless status.success? && output.include?('Headless input definitions loaded without controls')
puts 'PASS shared input/history definitions keep the headless executor independent of native Forms'
