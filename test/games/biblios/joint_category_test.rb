require_relative '../../../lib/biblios_category_model'
m = GameRoomBibliosCategoryModel
args = {mine:[4,0],rivals:[[0,-9,1],[0,-9,1]],population:3}
p = m.win_probability([[5,0]],**args)
raise 'One strong card was simultaneously assigned to both rivals' unless (p-1.0/3).abs<1e-12
raise 'No hidden card can reverse a public loss' unless m.win_probability([],mine:[4,0],rivals:[[5,0,0]],population:0).zero?
raise 'Neutral impossible library sizes consumed nonexistent cards' unless m.win_probability([],**args.merge(population:0))==1
raise 'Partial budget result was treated as a posterior' unless m.win_probability([[5,0]],**args,limit:0).nil?
puts 'PASS Biblios exact joint category allocation, known loss, finite inventory and complete-or-fallback budget'
