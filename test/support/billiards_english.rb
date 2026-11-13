require_relative 'billiards_rules'

module BilliardsEnglishFixture
  B = GameRoomBilliards
  R = B::Rules
  module_function

  def state(discipline = 'english', **options)
    value = BilliardsRulesFixture.state('eight')
    value[:options].merge!('discipline'=>discipline, 'point_target'=>100, 'equalizing'=>true,
      'english_limit'=>'points', 'time_limit_minutes'=>1)
    value[:options].merge!(options.transform_keys(&:to_s))
    R.setup(value)
    value
  end

  def apply(state, events, shot: {}, positions: {}, preserve_before: false)
    before = if preserve_before
      state.merge(balls: state[:balls].map(&:dup), scores: state[:scores].dup,
        fouls: state[:fouls].dup, groups: state[:groups]&.dup)
    else
      Marshal.load(Marshal.dump(state))
    end
    snapshot = Marshal.dump(before) if preserve_before
    events = events.each_with_index.map { |event, i| {t: i / 10.0, order: i}.merge(event) }
    balls = state[:balls].map(&:dup)
    events.select { |event| [:pocket, :off].include?(event[:kind]) }.each do |event|
      balls.find { |ball| ball.id == event[:a] }.status = :potted
    end
    positions.each do |id, (x, y)|
      ball = balls.find { |item| item.id == id }
      ball.x, ball.y = x, y
    end
    state[:balls] = balls
    result = B::ShotResult.new(balls: balls.map(&:dup), events: events, duration: 1, steps: 1)
    data = {'call'=>0, 'mode'=>0, 'pocket'=>0, 'cue'=>R.cue_id(before),
      'shot'=>{'angle'=>0, 'power'=>200, 'top'=>0, 'side'=>0}.merge(shot.transform_keys(&:to_s))}
    R.resolve_shot(state, before, result, data)
    raise 'Shot resolution mutated its shallow before snapshot' if preserve_before && Marshal.dump(before) != snapshot
    state
  end

  def hit(a, b, **extra); {kind: :ball, a: a, b: b}.merge(extra); end
  def rail(a, name = :top, **extra); {kind: :rail, a: a, rail: name}.merge(extra); end
  def pot(a); {kind: :pocket, a: a, pocket: 0}; end
end
