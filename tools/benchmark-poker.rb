# frozen_string_literal: true
require 'json'
require 'open3'
require 'optparse'
require_relative '../games/poker'
require_relative '../lib/game_simulation'

# Completed single hands, not truncated matches. Deal entropy is separate from
# policy tie-breaking, so each comparison has exactly the same cards and seat.
module PokerBenchmark
  module_function

  def baseline(ref)
    root = File.expand_path('..', __dir__)
    git = ['git', '-c', "safe.directory=#{root}"]
    commit, status = Open3.capture2e(*git, 'rev-parse', '--verify', '--end-of-options', "#{ref}^{commit}", chdir:root)
    raise commit unless status.success?
    commit = commit.strip
    source, status = Open3.capture2e(*git, 'show', "#{commit}:lib/poker_opponents.rb", chdir:root)
    raise source unless status.success?
    raise 'Unsupported baseline opponent module' unless source.include?('module GameRoomPokerOpponents')
    Object.module_eval(source.sub('module GameRoomPokerOpponents', 'module PokerBenchmarkOpponents'), 'baseline-poker-opponents.rb')
    source, status = Open3.capture2e(*git, 'show', "#{commit}:games/poker.rb", chdir:root)
    raise source unless status.success?
    body = source[/^module GameRoomGames\n.*?(?=\nrequire_relative 'poker_private')/m]
    raise 'Unsupported baseline poker source' unless body && body.include?('class Poker < CardGame')
    body = body.sub('class Poker < CardGame', 'class BaselinePoker < Poker').gsub('GameRoomPokerOpponents', 'PokerBenchmarkOpponents')
    Object.module_eval(body, File.join(root, 'games/poker.rb'))
    [commit, GameRoomGames::BaselinePoker]
  end

  def append(game, replay, session, repository, events, actor, selection, context)
    status, plan = game.action_for(selection, replay, actor, context:context)
    raise "Refused #{selection.inspect}: #{status}" unless status == :ok && plan.events.any?
    plan.events.each do |event|
      events << {'id'=>events.length + 1, 'actor'=>actor, 'action'=>event.action, 'value'=>event.value}
    end
    following = game.replay(session, events, repository)
    raise 'Reducer rejected a selected action' unless following.accepted_events.length == events.length
    following
  end

  def hand(seed, seat, candidate, rival, options, count)
    game = GameRoomGames::Poker.new
    players = count.times.map { |index| "Seat#{index}" }
    repository = GameRoomSimulation::Repository.new(players)
    session = {'options'=>JSON.generate(game.normalize_options(options))}
    events = []
    replay = game.replay(session, events, repository)
    deal_random = GameRoomRandom::SeededSource.new(seed)
    context = GameRoomGames::ActionContext.new(random_source:deal_random, now:1_800_000_000)
    replay = append(game, replay, session, repository, events, players.first,
      game.automatic_action(replay, players.first, context:context), context)
    signature = [replay.state[:hands], replay.state[:deck], replay.state[:dealer_index]]
    signature = Digest::SHA256.hexdigest(Marshal.dump(signature))
    policies = players.each_with_index.to_h { |actor,index| [actor, (index == seat ? candidate : rival).new] }
    choices = players.to_h { |actor| [actor, GameRoomRandom::SeededSource.new(seed + players.index(actor) * 1_000_003)] }
    timings, actions = [], 0
    until [:hand_complete, :finished].include?(replay.state[:phase])
      raise 'Unfinished hand: action bound' if actions >= 512
      actor = replay.current_player
      legal = game.legal_actions(replay, actor, context:context)
      raise 'Unfinished hand: no legal actions' if legal.empty?
      policy = policies.fetch(actor)
      before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      move = policy.bot_strategy.choose(actions:legal, actor:actor, game:policy, replay:replay,
        random_source:choices.fetch(actor), context:context)
      timings << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - before) * 1000 if actor == players[seat]
      raise 'Strategy returned an unavailable move' unless legal.include?(move)
      replay = append(game, replay, session, repository, events, actor, move, context)
      actions += 1
    end
    raise 'Chip conservation failed' unless replay.state[:stacks].values.sum == options.fetch('starting_chips') * count
    {net:replay.state[:stacks].fetch(players[seat]) - options.fetch('starting_chips'),
      signature:signature, actions:actions, timings:timings}
  end

  def run(old, seed:, boards:)
    rows, timings = [], {old:[], new:[]}
    boards.times do |index|
      count = index % 3 == 2 ? 3 : 2
      blind = [10, 50, 200][index % 3]
      options = {'variant'=>index % 8 == 7 ? 'draw' : 'holdem', 'deck'=>'full',
        'starting_chips'=>1000, 'small_blind'=>blind / 2, 'big_blind'=>blind,
        'blind_interval'=>'never', 'betting'=>index.even? ? 'no_limit' : 'pot_limit'}
      count.times do |seat|
        before = hand(seed + index, seat, old, old, options, count)
        after = hand(seed + index, seat, GameRoomGames::Poker, old, options, count)
        raise 'Paired deals diverged' unless before[:signature] == after[:signature]
        timings[:old].concat(before[:timings])
        timings[:new].concat(after[:timings])
        rows << {board:seed + index, seat:seat, players:count, variant:options['variant'],
          big_blind:blind, old:before[:net], new:after[:net], gain_bb:(after[:net] - before[:net]).fdiv(blind)}
      end
      warn "#{index + 1}/#{boards} paired deals" if (index + 1) % 16 == 0
    end
    groups = rows.group_by { |row| row[:board] }.values.map { |group| group.sum { |row| row[:gain_bb] } / group.size }
    mean = groups.sum / groups.size
    variance = groups.size > 1 ? groups.sum { |value| (value - mean)**2 } / (groups.size - 1) : 0
    {seed:seed, boards:boards, comparisons:rows.length, completed_hands:rows.length * 2,
      mean_gain_bb:mean, board_cluster_se:Math.sqrt(variance / groups.size),
      old_net:rows.sum { |row| row[:old] }, new_net:rows.sum { |row| row[:new] },
      timing:timings.transform_values { |values| sorted = values.sort; {decisions:values.length,
        median_ms:sorted[sorted.length / 2], p95_ms:sorted[(sorted.length * 0.95).floor], max_ms:sorted.last} },
      rows:rows}
  end
end

if $PROGRAM_NAME == __FILE__
  options = {seed:20261118, boards:32}
  parser = OptionParser.new do |cli|
    cli.on('--seed N', Integer) { |n| options[:seed] = n }
    cli.on('--boards N', Integer) { |n| options[:boards] = n }
    cli.on('--output PATH') { |path| options[:output] = path }
  end
  parser.parse!
  raise 'Use one trusted local baseline revision' unless ARGV.length == 1 && options[:boards].positive?
  path = options.delete(:output)
  raise 'Output already exists' if path && File.exist?(path)
  commit, old = PokerBenchmark.baseline(ARGV.first)
  result = PokerBenchmark.run(old, **options).merge(baseline:commit)
  json = JSON.pretty_generate(result) + "\n"
  path ? File.write(path, json, mode:'wx') : puts(json)
  puts JSON.generate(result.reject { |key,_| key == :rows }) if path
end
