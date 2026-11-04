class TournamentNoticeTestWorker
  attr_reader :starts
  def initialize; @starts=0; end
  def start(&work); return false if busy?; @work=work; @starts+=1; true; end
  def busy?; !!@work; end
  def take
    return unless @work
    work,@work=@work,nil
    begin; [work.call,nil]; rescue StandardError=>error; [nil,error]; end
  end
  def close; @work=nil; end
end
