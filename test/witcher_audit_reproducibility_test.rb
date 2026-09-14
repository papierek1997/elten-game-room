require "rbconfig"

python = ENV.fetch("PYTHON", Gem.win_platform? ? "python" : "python3")
script = File.join(__dir__, "witcher_audit_reproducibility_test.py")
raise "Witcher audit mutation tests failed" if !system({ "RUBY" => RbConfig.ruby }, python, script)
