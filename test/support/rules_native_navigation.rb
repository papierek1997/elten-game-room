require_relative "ui"
require_relative "host_source"

load EltenTestHost.file("src/eltenlink/__eltenlink.rb")
load EltenTestHost.file("src/ui/form.rb")
load EltenTestHost.file("src/ui/controls/form_field.rb")
load EltenTestHost.file("src/ui/controls/edit_box.rb")
Object.send(:remove_const, :EditBox)
EditBox = EltenAPI::Controls.const_get(:EditBox)

def p_(_context, text); text; end

module Configuration
  def self.linewrapping; false; end
end

require_relative "binary_rules_load"

class Form
  class << self
    attr_accessor :driver
  end

  def wait
    raise "Unexpected form" unless Form.driver
    Form.driver.call(self)
  end

  def focus; end
end

module NativeRuleInput
  attr_reader :opened_urls, :announcements

  def press(key, reverse: false)
    @pressed_key = key
    @shift = reverse
    @vindex = @index
    @announcements = []
    readupdate
    esay
  ensure
    @pressed_key = nil
    @shift = false
  end

  def key_pressed?(key); key == @pressed_key; end
  def raw_key_held?(key); key == :key_shift && @shift; end
  def modifier_held?(_modifier); false; end
  def getkeychar; ""; end
  def speech_stop; end
  def speak(text); (@announcements ||= []) << text; end
  def play_sound(_sound); end
  def loop_update; end
  def process_url(url); (@opened_urls ||= []) << url; end
end

$assertions = 0
$internal_jumps = 0

def assert(condition, message)
  $assertions += 1
  raise message unless condition
end

def elements(field, type)
  field.instance_variable_get(:@elements).select { |element| element.type == type }
end

def check_document(field, document, label)
  assert(field.is_a?(EltenAPI::Controls.const_get(:EditBox)), "#{label}: bypassed the real host EditBox")
  field.extend(NativeRuleInput)
  sections = document.sections
  body = sections.map { |section| "#{section.title}\n#{section.text.delete("\r")}" }.join("\n\n")
  expected = document.contents_title ? "#{document.contents_title}\n#{sections.map(&:title).join("\n")}\n\n#{body}" : body
  displayed_text = field.text_range(0, field.text_len - 1)
  assert(displayed_text == expected, "#{label}: displayed plain text changed")
  sections.each do |section|
    assert(displayed_text.include?(section.title), "#{label}: title changed: #{section.title}")
    section.paragraphs.each do |paragraph|
      assert(displayed_text.include?(paragraph.delete("\r")), "#{label}: paragraph changed: #{paragraph}")
    end
  end
  headings = elements(field, EditBox::Element::Header)
  links = elements(field, EditBox::Element::Link).select { |element| element.param[1].start_with?("#rule-section-") }
  assert(headings.length == sections.length + (document.contents_title ? 1 : 0), "#{label}: incorrect heading count")
  if document.contents_title
    assert(headings.first.from == 0 && headings.first.param == 1, "#{label}: missing Contents heading")
    assert(field.text_range(headings.first.from, headings.first.to) == document.contents_title, "#{label}: Contents text changed")
    assert(links.length == sections.length, "#{label}: incorrect contents link count")
    headings = headings.drop(1)
  else
    assert(links.empty?, "#{label}: single section gained contents")
  end
  sections.zip(headings).each do |section, heading|
    assert(heading.param == 2, "#{label}: section heading is not level 2")
    assert(field.text_range(heading.from, heading.to) == section.title, "#{label}: heading character offsets changed")
  end
  links.zip(headings, sections).each do |link, heading, section|
    assert(field.text_range(link.from, link.to) == section.title, "#{label}: link label changed")
    [link.from, link.to].uniq.each do |position|
      field.index = position
      field.press(:key_enter)
      assert(field.index == heading.from && field.check == heading.from, "#{label}: Enter did not move caret and selection to the heading")
      assert(field.announcements == [section.title], "#{label}: Enter did not speak only the heading")
      assert(field.opened_urls.to_a.empty?, "#{label}: internal link called process_url")
      $internal_jumps += 1
    end
  end
  flags = field.flags
  native_tips = EditBox.new("", type: EditBox::Flags::MarkDown).tips
  assert(!native_tips.empty? && field.tips == native_tips, "#{label}: missing native navigation hints")
  assert(field.flags == flags && (flags & EditBox::Flags::MarkDown).zero?, "#{label}: hints enabled Markdown parsing")
end
