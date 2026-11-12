# encoding: UTF-8
require_relative "base"
require_relative "../lib/game_action_payload"
require_relative "../lib/hidden_submissions"
require "weakref"
require_relative "duck_racing_support/resources"
require_relative "duck_racing_support/session"
require_relative "duck_racing_support/wire_budget"
require_relative "duck_racing_support/bots"
require_relative "duck_racing_support/replay_cache"

GameRoomServerRandom.register_payload('duck_racing', %w[start race advance], integer_seed: true,
  inputs: {'input' => {'kind' => 'roll'}})

module GameRoomGames
  using GameRoomLocalization::Translations

  class DuckRacing < Base
    include PublicHistoryAnnouncements
    include GameRoomDuckRacing::Bots
    Logic = GameRoomDuckRacing

    def initialize(resources: nil, bot_cache: nil)
      @prepared_resources = resources
      @bot_cache = bot_cache || Logic::BotCache.new
    end

    def id; "duck_racing"; end
    def name; _("Duck Racing"); end
    def short_description; _("Race around the pond, play cards and win challenges to keep your feathers and overtake the other ducks."); end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def perfect_information?; false; end
    def precise_action_clock?; true; end
    def background_client?; true; end
    def replay_participant_transitions?; true; end
    def actions_during_bot_turn?; true; end

    def build_client(program, **services)
      require_relative "../lib/duck_racing/client"
      client = Logic::Client.new(program, self, transport: services[:transport], presentation_busy: services[:presentation_busy])
      @local_client = WeakRef.new(client)
      client
    end

    def challenge_surface_spec(replay, viewer)
      local_client&.surface_spec(replay, viewer) || info_surface(_("Preparing the challenge."))
    end

    def realtime_shortcuts(replay, viewer)
      local_client&.shortcuts(replay, viewer) || []
    end

    def reportable_question(replay)
      local_client&.reportable_question(replay)
    end

    def local_client
      @local_client&.__getobj__
    rescue WeakRef::RefError
      nil
    end

    def build_session_game
      # Share prepared questions and bounded, immutable bot plans.
      # Client input and presentation caches remain separate in every copy.
      self.class.new(resources: @prepared_resources, bot_cache: @bot_cache)
    end

    # The UI has already reduced the latest full log. Historical fragment
    # transitions need their own bounded prefix cache, not that future entry.
    def build_presentation_game; build_session_game; end

    def content_language_option_key; "question_language"; end

    def remembered_option_definitions(definitions, options: nil)
      super + definitions.select { |definition| definition.key == "question_language" }
    end

    def table_creation_options(values = {})
      source = values.dup
      # A remembered checklist belongs to its content language. Resolve that
      # language from the packs when the preference contains only set IDs.
      ids = option_source_value(source, "question_sets")
      if option_source_value(source, "question_language").to_s.empty? && ids.is_a?(Array) && !ids.empty?
        languages = Logic::QuestionSets.languages(registry: content_registry).select do |language|
          choices = Logic::QuestionSets.choices(language: language, registry: content_registry).map { |choice| choice[:value] }
          (ids - choices).empty?
        end
        source["question_language"] = languages.first if languages.length == 1
      end
      super(source)
    end

    def option_definitions
      languages = Logic::QuestionSets.languages(registry: content_registry)
      [OptionDefinition.new(key: "laps", label: _("Laps"), kind: :integer, default: 3),
        OptionDefinition.new(key: "question_language", label: _("Question language"), kind: :choice,
          default: languages.include?("pl-PL") ? "pl-PL" : "en", choices: languages.map { |lang|
            OptionChoice.new(value: lang, label: content_registry.language(lang).label) }),
        OptionDefinition.new(key: "challenges", label: _("Challenges"), kind: :multiple_values,
          default: Logic::Challenges::BY_ID.keys, choices: Logic::Challenges::TYPES.map { |type|
            OptionChoice.new(value: type.id, label: challenge_name(type.id), description: challenge_description(type.id)) })]
    end

    def effective_option_definitions(selected = {})
      definitions = super
      language = selected["question_language"] || selected[:question_language] || definitions.find { |item| item.key == "question_language" }.default
      choices = Logic::QuestionSets.choices(language: language, registry: content_registry)
      definition = OptionDefinition.new(key: "question_sets", label: _("Question sets"), kind: :multiple_values,
        default: Logic::QuestionSets.defaults(language, registry: content_registry),
        choices: choices.map { |choice| OptionChoice.new(value: choice[:value], label: choice[:label]) })
      definitions.insert(definitions.index { |item| item.key == "challenges" }, definition)
    end

    def normalize_options(values)
      options = super
      source = values.is_a?(Hash) ? values : {}
      unless source.key?("question_sets") || source.key?(:question_sets)
        options["question_sets"] = Logic::QuestionSets.defaults(options["question_language"], registry: content_registry)
      end
      options
    end

    def option_editor_changes(previous, current)
      return {} if previous["question_language"] == current["question_language"]
      {"question_sets" => Logic::QuestionSets.defaults(current["question_language"], registry: content_registry)}
    end

    def options_error(options, player_count: nil)
      return _("Choose from 1 to 10 laps.") unless options["laps"].is_a?(Integer) && options["laps"].between?(1, 10)
      count = player_count || 2
      return _("Duck Racing requires two to eight players.") unless count.between?(2, 8)
      if Logic::Challenges.eligible(player_count: count, enabled: options["challenges"]).empty? ||
          Logic::Challenges.eligible(player_count: 2, enabled: options["challenges"]).empty?
        return _("Select at least one challenge for the whole group and for a duel.")
      end
      resources_for(options)
      nil
    rescue Logic::QuestionSets::Unavailable
      _("The selected questions are unavailable. Choose an installed set.")
    end

    def notification_option_keys(_options); %w[laps question_language]; end
    def notification_variant(options); options_summary(options); end
    def options_summary(options)
      laps = n_("%{laps} lap", "%{laps} laps", options["laps"]) % {laps: options["laps"]} if options["laps"].is_a?(Integer)
      [laps, notification_choice(options, "question_language")].compact.join(", ")
    end

    def resources_for(options)
      return @prepared_resources if @prepared_resources
      Logic::Resources.prepare(options, registry: content_registry)
    end

    def replay(session, events, repository)
      input = prepared_duck_replay_input(session, events, repository)
      session, players = input.session, input.players
      options = options_from_json(session["options"])
      resources = resources_for(options)
      physical_id = session["__id"] || session["id"]
      @duck_replay_cache ||= Logic::ReplayCache.new
      reduced = @duck_replay_cache.reduce(input,
        context: [options, resources.fetch(:fingerprint)],
        identities: [resources, GameRoomLocalization.cache_token]) do |previous, prefix|
        model, history, accepted, transitions, seen, last_time, challenge_events = previous || [
          Logic::Session.initial(session_id: physical_id && physical_id.to_i,
            player_count: players.length, laps: options["laps"], enabled_challenges: options["challenges"],
            fingerprint: resources.fetch(:fingerprint)),
          [starting_history(players)], [], session.fetch("__replay_participant_transitions", []).dup, {}, 0, []]
        # A final incomplete payload may have started in the old prefix. No
        # valid action spans more than MAX_PARTS fragments. Revisit just that
        # overlap; never retry a complete, previously rejected action against
        # a newer state where it could incorrectly become legal.
        from = [0, prefix - GameRoomActionPayload::MAX_PARTS + 1].max
        GameRoomActionPayload.each(input.events.drop(from), id, input, session) do |data, actor, batch|
          next if input.index_of(batch.last) < prefix
          boundary = input.event_id(batch.first)
          while transitions.first && transitions.first["id"] < boundary
            change = transitions.shift
            if Logic::Session.participants_changed(model, seats: change["seats"], now_ms: last_time)
              append_notices(history, model[:notices], change["id"], players)
              challenge_events = []
            end
          end
          next if batch.any? { |event| seen[input.event_id(event)] }
          seat = players.index { |player| same_user?(actor, player) }
          next unless seat
          now_ms = data["at"]
          next unless now_ms.is_a?(Integer) && now_ms >= 0
          next unless data["session"].is_a?(Integer) && data["session"].positive?
          owner = batch.first["__authority_user"] || session["__table_owner"] || players.first
          author = batch.first["__insertion_user"] || actor
          # Archive events were already accepted before saving. Native imports
          # are authenticated as controller actions by the store/repository;
          # their old actor is not necessarily the new owner. Never trust a
          # moderator flag supplied inside the game's wire payload.
          imported = batch.first["__controller"] == true && batch.first["move_id"].to_s.start_with?("archive:")
          moderator = physical_id.nil? || imported || same_user?(author, owner)
          candidate = Logic::Session.copy(model)
          if data["action"] == "start"
            next unless data["fingerprint"].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(data["fingerprint"])
            candidate[:fingerprint] = data["fingerprint"]
          end
          next unless Logic::Session.apply(candidate, data, seat: seat, moderator: moderator,
            now_ms: now_ms, resources: resources)
          previous_challenge = model.dig(:round, :challenge, :id)
          model = candidate
          challenge_events = [] unless previous_challenge == model.dig(:round, :challenge, :id)
          if model.dig(:round, :engine) && %w[begin input advance].include?(data["action"])
            challenge_events << {action: data["action"], seat: seat,
              at: now_ms - model[:round][:started_at], input: Logic::Session.copy(data["input"]), seed: data['seed']}
          end
          last_time = [last_time, now_ms].max
          accepted.concat(batch)
          batch.each { |event| seen[input.event_id(event)] = true }
          append_notices(history, model[:notices], input.event_id(batch.last), players)
        end
        [model, history, accepted, transitions, seen, last_time, challenge_events]
      end
      model, history, accepted, transitions, _seen, last_time, challenge_events = reduced
      transitions.each do |change|
        if Logic::Session.participants_changed(model, seats: change["seats"], now_ms: last_time)
          append_notices(history, model[:notices], change["id"], players)
          challenge_events = []
        end
      end
      state = model.merge(players: players, options: options, owner: session["__table_owner"] || players.first,
        bot_controller_epoch: session["__control_epoch"], controllers: session.fetch("__controllers", {}).dup,
        duck_challenge_events: challenge_events)
      replay_from_state(state, session, accepted, history)
    end

    private def prepared_duck_replay_input(session, events, repository)
      # The native CAS changes on every write, not the meaning of the game.
      # Reuse only the shared cache's sealed authenticated prefix, with the
      # same bounded admission as other replay-cache consumers.
      input = Logic::ReplayCache::Input.new(session.reject { |key, _| key == '__game_revision' }, events, repository,
        previous: @duck_replay_input)
      @duck_replay_input = input.retention_bytes <= Logic::ReplayCache::MAX_BYTES ? input : nil
      input
    end

    def replay_from_state(state, session, accepted, history)
      GameRoomSessionClock.attach(state, session)
      players = state[:players]
      race = state[:race]
      winner = race && race[:winner] && players.fetch(race[:winner])
      current = race && state[:round].nil? && !winner ? players.fetch(race[:turn]) : nil
      Replay.new(board: nil, players: players, current_player: current, winner: winner, draw: false,
        accepted_events: accepted, history: history, state: state)
    end
    private :replay_from_state

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] unless context && context.session_id.to_i == replay.state[:session_id]
      seat = player_index(replay.players, actor)
      return [:not_your_turn, nil] unless seat
      raw = selection.to_h.transform_keys(&:to_s)
      raw = normalize_surface_action(raw)
      data = raw.slice("action", "input", "challenge", "fingerprint", "value", "page", "receipt", "reason", "trace", "answer")
      if raw["action"] == "submit_trace"
        return prepare_trace(raw, replay, actor, seat, context)
      end
      data["revision"] = replay.state[:revision]
      data["session"] = context.session_id.to_i
      data["at"] = (context.now.to_f * 1000).round
      random_action = GameRoomServerRandom.payload_required?(id, data)
      data['seed'] = 0 if context.server_random && random_action
      moderator = same_user?(context.table_owner, replay.state[:owner]) &&
        context.local_data.to_h["duck_host"] == true
      if data["action"] == "start"
        return [:invalid, nil] unless moderator && context.random_source
        data['seed'] = if context.server_random
          0 # Validate the ordinary transition before requesting server entropy.
        else
          context.random_source.roll(count:16,sides:256).values.reduce(0) { |seed,value| seed*256+value-1 }
        end
        data["fingerprint"] = resources_for(replay.state[:options]).fetch(:fingerprint)
        data['challenge_flow'] = 2
      elsif data["action"] == "point"
        return [:invalid, nil] unless data["receipt"] && data["receipt"] == context.local_data.to_h["duck_realtime_point"]
      end
      private_plan = duck_private_plan(data, replay, actor, context) if %w[commit reveal cancel attempt result].include?(data["action"])
      candidate = Logic::Session.copy(replay.state)
      return [:invalid, nil] unless Logic::Session.apply(candidate, data, seat: seat, moderator: moderator,
        now_ms: data["at"], resources: resources_for(replay.state[:options]))
      if random_action && context.server_random
        return [:ok, ActionPlan.new(events:[GameRoomServerRandom.payload_seed_command(action:id,data:data)])]
      end
      [:ok, private_plan || ActionPlan.new(events: GameRoomActionPayload.commands(id, data))]
    rescue Logic::PrivateRound::CapacityError
      return [:oversized_session_action, nil] if data["action"] == "cancel"
      action_for({"kind" => "duck", "action" => "cancel", "reason" => "technical",
        "challenge" => data["challenge"]}, replay, actor, context: context)
    end

    def prepare_trace(raw, replay, actor, seat, context)
      round = replay.state[:round]
      return [:invalid, nil] unless round && raw["challenge"] == round[:challenge][:id]
      if round[:results]
        return [:local_storage_unavailable, nil] unless context.hidden_submissions
        answer = Logic::LocalResult.prepare(replay.state, seat: seat, user: actor,
          answer: raw['trace'], vault: context.hidden_submissions)
        return action_for({'action' => 'result', 'challenge' => raw['challenge'], 'answer' => answer}, replay, actor, context: context)
      end
      if round[:attempts]
        return action_for({"action" => "attempt", "challenge" => raw["challenge"], "trace" => raw["trace"]},
          replay, actor, context: context)
      end
      return [:invalid, nil] unless round[:private] && context.hidden_submissions
      duck_cleanup_private(replay, actor, context)
      if round[:private][:compact]
        Logic::CompactAttempt.verify(round[:challenge], raw['trace'], seat: seat, resources: resources_for(replay.state[:options]))
      end
      prepared = Logic::PrivateRound.prepare(round[:private], seat: seat, user: actor,
        trace: raw["trace"], vault: context.hidden_submissions,
        page_builder: duck_page_builder(replay, actor, context))
      # The final wire framing, not a guessed trace length, must fit before
      # publishing a commitment. Long Simon traces remain multiple pages.
      action_for({"kind" => "duck", "action" => "commit", "challenge" => raw["challenge"],
        "value" => prepared.commit_value}, replay, actor, context: context)
    rescue HiddenSubmissions::StorageError
      [:local_storage_unavailable, nil]
    rescue Logic::PrivateRound::CapacityError
      action_for({"kind" => "duck", "action" => "cancel", "reason" => "technical",
        "challenge" => raw["challenge"]}, replay, actor, context: context)
    rescue Logic::PrivateRound::InvalidSubmission, Logic::TraceVerifier::InvalidTrace
      [:invalid, nil]
    end

    def duck_page_builder(replay, actor, context)
      lambda do |page|
        data = {"action" => "reveal", "challenge" => replay.state[:round][:challenge][:id], "page" => page,
          "revision" => replay.state[:revision], "session" => context.session_id.to_i,
          "at" => (context.now.to_f * 1000).round}
        Logic::WireBudget.plan(id, data, replay: replay, actor: actor,
          limit: context.local_data.to_h["duck_stack_entry_bytes"])
      end
    end

    def duck_private_plan(data, replay, actor, context)
      # The time/revision/epoch can change after preparation, even if this is
      # the same local answer. Shrink only the next unsent page; accepted
      # offsets and the complete committed payload remain unchanged.
      loop do
        begin
          return Logic::WireBudget.plan(id, data, replay: replay, actor: actor,
            limit: context.local_data.to_h["duck_stack_entry_bytes"])
        rescue ArgumentError => error
          page = data["page"] if data["action"] == "reveal"
          raise Logic::PrivateRound::CapacityError, error.message unless page.is_a?(Hash)
          data["page"] = Logic::PrivateRound.shrink_reveal_page(page)
        end
      end
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      same_user?(actor, table_owner) || !player_index(replay.players, actor).nil?
    end

    def automatic_actor(replay, viewer, table_owner:)
      if same_user?(viewer, table_owner) && (round = replay.state[:round])
        bots = round[:challenge][:participants].select do |seat|
          duck_bot_controlled?(replay.state, replay.players.fetch(seat))
        end
        pending = if round[:phase] == :preparing
          bots.find { |seat| !round[:ready][seat] }
        elsif round[:private]&.fetch(:phase) == :revealing
          bots.find { |seat| !round[:private][:reveals].key?(seat) }
        elsif round[:phase] == :playing && !Logic::ChallengeEngine::REALTIME.include?(round[:challenge][:kind])
          now = duck_automatic_now_ms(replay)
          bots.reject { |seat| round[:results]&.key?(seat) || round[:attempts]&.key?(seat) || round[:private]&.fetch(:reveals)&.key?(seat) }
            .select { |seat| now >= round[:last_seen].fetch(seat) + Logic::Session::PULSE_MS }
            .min_by { |seat| round[:last_seen].fetch(seat) }
        end
        return replay.players.fetch(pending) if pending
      end
      player_index(replay.players, viewer) ? viewer :
        (same_user?(viewer, table_owner) ? replay.players.first : viewer)
    end

    def duck_automatic_now_ms(replay)
      (GameRoomSessionClock.for_state(replay.state) * 1000).round
    end

    def automatic_action(replay, actor, context: nil)
      return if replay.finished? || !context
      state, local = replay.state, context.local_data.to_h
      host = local["duck_host"] == true
      seat = player_index(replay.players, actor)
      return unless seat
      duck_cleanup_private(replay, actor, context)
      if !state[:race]
        return {"kind" => "duck", "action" => "start"} if host
        return
      end
      round = state[:round]
      if round
        base = {"kind" => "duck", "challenge" => round[:challenge][:id]}
        participant = round[:challenge][:participants].include?(seat)
        if host && Logic::Session.idle?(round, (context.now.to_f * 1000).round)
          return base.merge("action" => "cancel")
        end
        if host && (receipt = local["duck_realtime_point"]) && receipt["id"] == base["challenge"]
          return base.merge("action" => "point", "receipt" => receipt)
        end
        if participant && round[:results] && !round[:results].key?(seat) && context.hidden_submissions &&
            (local['duck_seat'] == seat || host && duck_bot_controlled?(state, actor))
          recovery = duck_result_recovery(state)
          key = actor.to_s.downcase
          if recovery[key] != :empty
            begin
              answer = Logic::LocalResult.recover(state, seat: seat, user: actor, vault: context.hidden_submissions)
              return base.merge('action' => 'result', 'answer' => answer) if answer
              recovery[key] = :empty
            rescue HiddenSubmissions::StorageError, Logic::TraceVerifier::InvalidTrace
              return base.merge('action' => 'cancel', 'reason' => 'technical')
            end
          end
        end
        if participant && (request = local["duck_action"]) && request["challenge"] == base["challenge"] &&
            local["duck_seat"] == seat
          return request
        end
        protocol = round[:private]
        owns_answer = local["duck_seat"] == seat || host && duck_bot_controlled?(state, actor)
        if participant && owns_answer && context.hidden_submissions && duck_reveal_pending?(round, seat)
          begin
            page = Logic::PrivateRound.recover_next_reveal_page(protocol, seat: seat, user: actor, vault: context.hidden_submissions,
              page_builder: duck_page_builder(replay, actor, context))
          rescue Logic::PrivateRound::CapacityError, HiddenSubmissions::StorageError
            return base.merge("action" => "cancel", "reason" => "technical")
          end
          if page
            return base.merge("action" => "reveal", "page" => page)
          end
          return base.merge("action" => "cancel", "reason" => "technical")
        end
        if participant && round[:phase] == :preparing && !round[:ready][seat] &&
            (host && duck_bot_controlled?(state, actor) || local["duck_ready"] == true && local["duck_seat"] == seat)
          return base.merge("action" => "ready", "fingerprint" => state[:fingerprint])
        end
        if host && participant && duck_bot_controlled?(state, actor) && duck_pulse_due?(round, seat, context)
          return base.merge("action" => "alive")
        end
        if host && (action = Logic::Session.automatic(state, now_ms: (context.now.to_f * 1000).round))
          return base.merge("action" => action)
        end
      elsif host
        racer = state[:race][:racers].fetch(state[:race][:turn])
        if racer[:frozen_turns].positive? || racer[:skip_turns].positive?
          return {"kind" => "duck", "action" => "race", "input" => {"kind" => "skip"}}
        end
      end
      nil
    end

    def automatic_action_due?(replay, actor, context: nil)
      return false unless context && !replay.finished?
      state, local = replay.state, context.local_data.to_h
      round, seat = state[:round], player_index(replay.players, actor)
      return false unless seat
      return local["duck_host"] == true unless state[:race]
      return false unless round
      challenge = round[:challenge][:id]
      participant = round[:challenge][:participants].include?(seat)
      if participant
        bot = local["duck_host"] == true && duck_bot_controlled?(state, actor)
        if round[:results] && !round[:results].key?(seat) && (local['duck_seat'] == seat || bot) && context.hidden_submissions
          return true unless duck_result_recovery(state)[actor.to_s.downcase] == :empty
        end
        # Readiness is independent of a local key request. Keep scheduling
        # pending pages after the UI acknowledges and clears submit_trace;
        # recovering the envelope itself belongs to the executor, not here.
        return true if (local["duck_seat"] == seat || bot) && context.hidden_submissions && duck_reveal_pending?(round, seat)
        return true if round[:phase] == :preparing && !round[:ready][seat] &&
          (bot || local["duck_ready"] == true && local["duck_seat"] == seat)
        return true if bot && duck_pulse_due?(round, seat, context)
      end
      request = local["duck_action"]
      return true if local["duck_seat"] == seat && request && request["challenge"] == challenge
      return true if local["duck_host"] == true && (local.dig("duck_realtime_point", "id") == challenge ||
        Logic::Session.automatic(state, now_ms: (context.now.to_f * 1000).round))
      false
    end

    def concurrent_session_input?(before, after, selection)
      action = selection["action"]
      concurrent = %w[ready alive submit_trace commit reveal attempt result].include?(action) ||
        action == 'input' && before.state.dig(:round, :challenge, :kind) == 'sound_order'
      concurrent &&
        before.state[:session_id] == after.state[:session_id] &&
        before.state.dig(:round, :challenge, :id) == selection["challenge"] &&
        after.state.dig(:round, :challenge, :id) == selection["challenge"]
    end

    def controller_change_phase_error(_replay); nil; end

    def duck_bot_controlled?(state, actor)
      GameRoomParticipants.bot?(actor) || state.fetch(:controllers, {})[actor] == "bot"
    end

    def duck_pulse_due?(round, seat, context)
      (round[:phase] == :preparing || round[:phase] == :playing && !Logic::ChallengeEngine::REALTIME.include?(round[:challenge][:kind])) &&
        !round[:private]&.fetch(:reveals)&.key?(seat) &&
        !round[:attempts]&.key?(seat) &&
        !round[:results]&.key?(seat) &&
        (context.now.to_f * 1000).round >= round[:last_seen].fetch(seat) + Logic::Session::PULSE_MS
    end

    def duck_reveal_pending?(round, seat)
      protocol = round[:private]
      protocol && protocol[:phase] == :revealing && protocol[:commitments].key?(seat) &&
        !protocol[:reveals].key?(seat) && !protocol[:forfeits].key?(seat)
    end

    def duck_result_recovery(state)
      scope = [state[:session_id], state.dig(:round, :challenge, :id)]
      if @duck_result_recovery_scope != scope
        @duck_result_recovery_scope, @duck_result_recovery = scope, {}
      end
      @duck_result_recovery
    end

    def duck_cleanup_private(replay, actor, context)
      return unless context.hidden_submissions && context.session_id.to_i == replay.state[:session_id]
      cleanup_session_answers(replay, session_id: context.session_id.to_i,
        actors: [actor], hidden_submissions: context.hidden_submissions)
    end

    def cleanup_session_answers(replay, session_id:, actors:, hidden_submissions:)
      return unless hidden_submissions && session_id == replay.state[:session_id]
      receipts = replay.state.fetch(:private_closures, []).dup
      if (protocol = replay.state.dig(:round, :private)) && !protocol[:reveals].empty?
        receipts << {session_id: protocol[:session_id], round_id: protocol[:round_id],
          seats: protocol[:reveals].keys, commitments: protocol[:commitments], cancelled: false, compact: protocol[:compact]}
      end
      result_receipts = [replay.state.fetch(:result_closures, []),
        replay.state.dig(:round, :results)&.keys, replay.state.dig(:round, :challenge, :id)]
      return if receipts.empty? && result_receipts[0].empty? && result_receipts[1].to_a.empty?
      signature = [receipts, result_receipts]
      actors.each do |actor|
        key = [session_id, actor.to_s.downcase]
        checked = (@duck_cleanup_checked ||= {})[key]
        next if checked && checked[0].equal?(hidden_submissions) && checked[1] == signature
        begin
          result_cleaned = Logic::LocalResult.cleanup(replay.state, user: actor, vault: hidden_submissions)
        rescue HiddenSubmissions::StorageError
          next
        end
        if Logic::PrivateRound.cleanup_confirmed(session_id: session_id, user: actor,
            receipts: receipts, vault: hidden_submissions) && result_cleaned
          @duck_cleanup_checked[key] = [hidden_submissions, Logic::Session.copy(signature)]
        end
      end
    end

    def save_game_error(replay)
      return super if replay.finished?
      race = replay.state[:race]
      _("Finish the current turn or challenge before saving the race.") unless race &&
        replay.state[:round].nil? && race[:pending].empty? && !race[:card_played] && !race[:rolled]
    end

    def participant_scores(replay)
      return unless replay.state[:race]
      replay.players.each_with_index.to_h { |name, seat| [name, replay.state[:race][:racers].fetch(seat)[:progress]] }
    end

    def required_decision_key(replay, viewer)
      return unless replay
      return if skipped_race_turn?(replay)
      round = replay.state[:round]
      return super unless round
      seat = player_index(replay.players, viewer)
      return unless round[:phase] == :playing && round[:challenge][:participants].include?(seat)
      return if round[:private] && round[:private][:commitments].key?(seat)
      return if round[:attempts]&.key?(seat)
      return if round[:results]&.key?(seat)
      if Logic::ChallengeEngine::SEQUENTIAL.include?(round[:challenge][:kind])
        engine = round[:engine]
        return unless engine && !Logic::ChallengeEngine.finished?(engine)
        model = engine[:model]
        turn, started = if Logic::NumericChallenges::TURN_TYPES.include?(round[:challenge][:kind])
          [model[:participants][model[:turn_index]], model[:turn_started_at_ms]]
        else
          [model[:public][:turn], model[:public][:turn_started_ms]]
        end
        return unless turn == seat
        # Further draws/rolls belong to the same attempt. Renewing its
        # input deadline must not announce another "your turn" decision.
        return [round[:challenge][:id], seat] if Logic::NumericChallenges::ATTEMPT_TURN_TYPES.include?(round[:challenge][:kind])

        return [round[:challenge][:id], seat, started]
      end
      [round[:challenge][:id], seat]
    end
  end
end

require_relative "duck_racing_support/presentation"
require_relative "duck_racing_support/sounds"
require_relative "generated/rulebooks/duck_racing"
