require_relative '../support/statistics_screen'
require_relative '../support/ui'
require_relative '../support/host_source'
require_relative '../../lib/game_content'

module EltenAPI
  module Controls
    module WaitForItem; end
    class SpeechSequence; end
    class FormField < FakeControl
      def text_utf8(value); GameRoomContent.utf8(value); end
      def on(event, &handler)
        @handlers ||= {}
        super
      end
    end
  end
end
class ListBox
  def item_states; @item_states ||= {}; end
  def clear_item_audio; end
end
load File.join(EltenTestHost.root, 'src/ui/controls/table_box.rb')
TableBox = EltenAPI::Controls.const_get(:TableBox)
require_relative '../../lib/game_statistics_screen'

class Form
  class << self; attr_accessor :clock_driver; end
  def wait; Form.clock_driver.call(self); end
end

module StatisticsClockRecoveryContract
  def self.assert(value, message)
    raise message unless value
    @checks = @checks.to_i + 1
  end

  GameRoomLocalization.boot(host_language: 'en', settings: {'interface_language' => 'en'})
  registry = Object.new
  registry.define_singleton_method(:ids) { ['quiz'] }
  registry.define_singleton_method(:name) { |_id| 'Quiz' }
  reads, years, ready = [], 0, false
  data = {'visitors' => 1, 'players' => 1, 'started' => 1, 'completed' => 0,
    'games' => [], 'first_day' => 20261018, 'partial' => false}
  Form.clock_driver = lambda do |form|
  settle_statistics(form)
    assert(reads.empty? && years.zero?, 'unavailable clock queried tables or fabricated a date')
    summary, period = form.fields.first(2)
    table = form.fields.find { |field| field.is_a?(TableBox) }
    assert(summary.text.include?('Statistics could not be loaded.'), 'missing explicit unavailable state')
    assert(period.options.empty? && table.rows.empty?, 'unconfirmed clock displayed plausible periods or zero counts')
    ready = true
    form.fields.find { |field| field.is_a?(Button) && field.label == 'Refresh' }.trigger(:press)
    settle_statistics(form)
    assert(reads.length == 1 && reads.last.from_day == 20261018 && reads.last.to_day == 20261018,
      'Refresh did not recover the confirmed date')
    assert(years == 1 && period.options.first == 'Today', 'recovery did not rebuild available periods')
    assert(summary.text.include?('Visitors: 1'), 'confirmed report was not displayed after recovery')
    period.index = 1
    period.trigger(:move)
    settle_statistics(form)
    assert(reads.last.key == 'last_7', 'last-seven-day selection failed')
    ready = false
    refresh = form.fields.find { |field| field.is_a?(Button) && field.label == 'Refresh' }
    before = [reads.length, years]
    refresh.trigger(:press)
    settle_statistics(form)
    assert([reads.length, years] == before && period.options.empty? && table.rows.empty?,
      'lost clock retained old counts or issued an undated read')
    period.trigger(:move)
    settle_statistics(form)
    assert([reads.length, years] == before, 'empty period selection attempted a read')
    ready = true
    refresh.trigger(:press)
    settle_statistics(form)
    assert(reads.last.key == 'last_7' && period.options[period.index].start_with?('Last 7'),
      'clock recovery lost the selected period identity')
    form.cancel_button.trigger(:press)
  end
  GameRoomStatisticsScreen.new(program: Object.new, registry: registry,
    today: -> { raise GameRoomNetworkErrors::ClockUnavailable, 'no server sample' unless ready; Date.new(2026, 10, 18) },
    reader: ->(period, _token) { reads << period; data }, years_reader: ->(_token) { years += 1; [2026] }).run
  puts "PASS statistics unavailable-clock recovery: #{@checks} assertions"
end
