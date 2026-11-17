require_relative '../../lib/axel_pong/mouse'
require_relative '../../lib/axel_pong/engine'

def assert(value, message); raise message unless value; end

class PongMouseApi
  attr_accessor :foreground, :modified, :point, :middle, :fail_warp, :broken, :left
  attr_reader :warps
  def initialize
    @foreground, @point, @middle, @warps = 123, [-1500, 200], [-1000, 400], []
  end
  def modified?; @modified; end
  def left_down?; @left == true; end
  def position; raise 'read failed' if @broken; @point.dup; end
  def centre(_hwnd); @middle.dup; end
  def warp(x, y)
    return false if @fail_warp
    @warps << [x, y]
    @point = [x, y]
    true
  end
end

class PongMouseBackend
  attr_accessor :delta, :supported
  attr_reader :samples, :suspends
  def initialize
    @delta, @supported, @samples, @suspends = [0, 0], true, 0, 0
  end
  def available?; @supported; end
  def sample; @samples += 1; @delta; end
  def suspend(**_options); @suspends += 1; end
end
