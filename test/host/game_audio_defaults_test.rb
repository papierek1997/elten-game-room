require_relative '../support/invitation_fresh_endpoint'

factory=Module.new do
  attr_reader :sound_calls
  %i[create_sound_from_asset create_spatial_sound_from_asset play_sound_from_asset].each do |method|
    define_method(method) do |name,**options,&configure|
      sound=Object.new
      (@sound_calls ||= []) << [method,name,options]
      configure&.call(sound)
      sound
    end
  end
end
Program.include(factory)
Program.extend(factory)

[EltenGameRoom,EltenGameRoom.new].each do |program|
  %i[create_sound_from_asset create_spatial_sound_from_asset play_sound_from_asset].each do |method|
    [{},{effect_buffer:nil},{effect_buffer: :interactive},{effect_buffer_seconds:0.2},{sample:true}].each do |options|
      configured=nil
      sound=program.public_send(method,'test',**options) { |value| configured=value }
      assert(program.sound_calls.last[2]==options,'Power Games injected or changed native audio buffering')
      assert(configured.equal?(sound),'Native sound configuration callback was lost')
    end
  end
end
puts 'PASS class/instance sound factories: native default buffering, explicit options and configuration callbacks preserved'
