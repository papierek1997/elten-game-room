module GameRoomTestSuites
  NAMES = %w[models transport ui native tooling integration tournaments].freeze
  ROOT = File.expand_path('../..', __dir__)
  ROOT_TESTS = %w[code_quality_test.rb game_imports_test.rb model_contract_test.rb].freeze
  # Exhaustive searches and full tournament lifecycles can exceed the ordinary
  # three-minute runner limit. Give these scenarios measured, bounded budgets
  # without dropping their coverage or full-history assertions.
  SLOW_TIMEOUTS = {
    # All 5,478 reachable boards and 4,520 production-strategy decisions:
    # about 105 s locally, but repeated shared CI runs exceed 180 s.
    # Keep the complete exhaustive check and a bounded six-minute CI budget.
    'exhaustive_strategy_test.rb' => 360,
    'individual_quiz_finish_test.rb' => 5400,
    'generic_team_knockout_lifecycle_test.rb' => 1800,
    'team_knockout_lifecycle_test.rb' => 5400,
    'ft2_c08_eight_records_test.rb' => 900,
    'fixed_team_cleanup_regression_test.rb' => 600,
    # These complete in about 160–175 seconds on the local Windows runner.
    # Keep headroom for CI without dropping their full-history assertions.
    'fixed_team_cleanup_boundaries_test.rb' => 300,
    'fixed_team_dispatch_test.rb' => 300,
    'fixed_team_result_test.rb' => 300,
    'individual_multi_seat_dispatch_test.rb' => 420,
    'individual_quiz_private_test.rb' => 600,
    'knockout_replay_execution_test.rb' => 600,
    # Three complete games (win, draw, win) and immutable series ancestry:
    # measured 220 s on Windows; retain every match and result assertion.
    'knockout_win_series_execution_test.rb' => 360,
    # Nine legally produced local phases/results and a cold reopen: measured
    # 442 s on Windows alongside direct dependencies. Preserve the complete
    # producer/history proof with a bounded fifteen-minute CI budget.
    'local_phase_record_capacity_test.rb' => 900,
    'generic_team_replay_execution_test.rb' => 600,
    'realtime_team_multi_table_test.rb' => 600,
    'automatic_phase_lifecycle_test.rb' => 600,
    'fixed_team_budget_nodes_test.rb' => 600,
    'team_group_tiebreak_test.rb' => 600,
    'biblios_private_cards_test.rb' => 300,
    # Complete two- and three-player private Rummy, including cold return and
    # host transfer: measured 229 s on Windows with all history checks intact.
    'rummy_private_cards_test.rb' => 600,
    # 372 authenticated events, full replay on all three accounts after each
    # action: measured 198 s on Windows (one late projection about 110 ms).
    'biblios_private_three_players_test.rb' => 360
  }.freeze

  def self.timeout_for(path, fallback:)
    name = File.basename(path)
    return 600 if name.match?(/\Aexecution_.*_suite_test\.rb\z/)
    SLOW_TIMEOUTS.fetch(name, fallback)
  end
  FOLDER_SUITES = {
    'models' => 'models', 'transport' => 'transport', 'realtime' => 'transport',
    'session' => 'transport', 'ui' => 'ui', 'host' => 'native',
    'tooling' => 'tooling', 'localization' => 'tooling',
    'room' => 'integration', 'persistence' => 'integration',
    'statistics' => 'integration', 'integration' => 'integration',
    'quiz_contributions' => 'integration',
    'tournaments' => 'tournaments'
  }.freeze

  # These families are executed by maintained execution_*_suite entry points.
  # Historical versions remain available only by explicit file path.
  PARAMETERIZED_PATTERNS = %w[
    ft2b1_
    ft2_runtime_cold_
    ft2_compatibility_boundary_
    ft2_compatibility_error_
    ft2_compatibility_legacy_
  ].freeze

  PARAMETERIZED_FILES = %w[
    fixed_team_cold_test.rb fixed_team_execution_cold_test.rb fixed_team_execution_cold_read_test.rb
    fixed_team_execution_parallel_prepare_test.rb fixed_team_execution_parallel_test.rb
    local_readiness_refusal_test.rb
  ].freeze
  # These are forensic readers of archives from the contributor's earlier
  # private experiments, not self-contained scenarios. They remain callable
  # by exact path with those inputs; current cold/recovery suites create their
  # own fixtures. Missing historical evidence must never be reported as PASS.
  HISTORICAL_INPUT_FILES = %w[
    fixed_team_compatibility_test.rb ft2_c08_eight_resume_test.rb
    ft2_c08_legacy_missing_test.rb ft2_c08_legacy_read_test.rb
    small_score_archive_projection_test.rb small_score_order_ui_test.rb
  ].freeze

  def self.automatic_path?(path)
    parts = path.tr('\\', '/').split('/')
    !parts[0...-1].any? { |part| %w[support fixtures].include?(part) } &&
      !PARAMETERIZED_PATTERNS.any? { |pattern| File.basename(path).start_with?(pattern) } &&
      !(PARAMETERIZED_FILES + HISTORICAL_INPUT_FILES).include?(File.basename(path))
  end

  def self.paths(root: ROOT)
    Dir.glob('test/**/*_test.rb', base: root).sort.select { |path| automatic_path?(path) }
  end

  # The filesystem records ownership; CI suites record the execution layer.
  # Native host contracts take precedence within every owner's directory.
  def self.classify(path, root: ROOT)
    text = File.read(File.join(root, path), encoding: 'UTF-8')
    return 'native' if text.match?(/EltenTestHost|support\/(?:host_source|binary_suite|native_host)/)
    folder = path.split('/')[1]
    return FOLDER_SUITES.fetch(folder) if FOLDER_SUITES.key?(folder)
    name = File.basename(path)
    return 'tooling' if name == 'code_quality_test.rb'
    return 'models' if name == 'model_contract_test.rb'
    if folder == 'games'
      return 'tooling' if text.match?(%r{require_relative ["'](?:\.\./)+tools/}) || name.match?(/translation|dictionary|export|generator|pack_builder/)
      return 'ui' if name.match?(/screen|surface|encoding|keyboard|shortcut|cursor|focus|navigation|presentation/)
      return 'models'
    end
    'integration'
  end

  def self.select(name, root: ROOT)
    raise ArgumentError, "Unknown suite #{name.inspect}; choose #{NAMES.join(', ')}" unless NAMES.include?(name)
    paths(root: root).select { |path| classify(path, root: root) == name }
  end
end
