require_relative "../../support/dice_games"
require_relative "../../../games/liars_dice"
require_relative "../../../lib/saved_game_archive"
include DiceGamesSupport

class DiceMemoryArchive < GameRoomSavedGameArchive
  private
  def persist(_row); end
end

game = GameRoomGames::LiarsDice.new
players = %w[Alice Bob Carol]
repo = DiceGamesSupport::Repository.new(players)
session = dice_session(game,variant:'perudo',starting_dice:2).merge('__players'=>players)
scope = {round:1,players:players}
seeds = players.each_with_index.to_h { |player,i| [player,(i+1).to_s*32] }
nonce, server = 'f'*32, 'a'*32
events = players.map.with_index do |player,index|
  digest = HiddenSubmissions::Commitment.create(GameRoomLiarsDiceSecrets.payload(scope,player,seeds[player]),nonce:nonce).first
  dice_event(index+1,player,'commit','1:'+GameRoomLiarsDiceSecrets.encode(digest))
end
events += [dice_event(4,'Alice','deal','1:'+server),dice_event(5,'Alice','bid','1:0:6:6'),dice_event(6,'Bob','challenge','1:1')]
players.each { |player| events << dice_event(events.size+1,player,'reveal','1:'+GameRoomLiarsDiceSecrets.encode(seeds[player]+nonce)) }
before = game.replay(session,events,repo)
check(before.state[:phase] == :committing && before.state[:round] == 2,'Archive test must start at a safe round boundary')
archive = DiceMemoryArchive.new(nil,owner:'Owner')
row = archive.put(game:game,table:{'owner'=>'Owner','name'=>'Dice trial'},snapshot:Struct.new(:session,:events).new(session,events),repository:repo,now:100)
restored = archive.restored_data(row,game:game,table_id:987,now:200)
restored_session = session.merge('__id'=>987,'__players'=>restored[:players])
after = game.replay(restored_session,restored[:events],repo)
check(after.accepted_events.size == events.size && after.state[:counts] == before.state[:counts] && after.state[:round] == 2,'Historical private proofs failed after restoring to another session')

roster = %w[Alice Replacement Carol]
boundary = events.size+1
changed = session.merge('__initial_players'=>players,'__players'=>roster,'__seat_changes'=>[{'id'=>boundary,'players'=>roster}])
original = Marshal.dump(events)
replacement_repo = DiceGamesSupport::Repository.new(roster)
replaced = game.replay(changed,events,replacement_repo)
check(replaced.accepted_events == events && original == Marshal.dump(events),'Replacement changed the authenticated log')
check(replaced.state[:counts]['Replacement'] == before.state[:counts]['Bob'],'Replacement lost the inherited dice count')
check(replaced.history.map(&:text) == before.history.map(&:text),'Replacement rewrote historical announcements')
check(GameRoomParticipantDecisionEvents.for(replaced).any? { |event| event['actor'] == 'Replacement' },'Replacement decision projection retained the old actor')
puts "Liar's dice archives: authenticated completed rounds restore across sessions, safe replacement, immutable log and historical announcements passed"
