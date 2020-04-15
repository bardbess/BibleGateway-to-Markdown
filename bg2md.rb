#!/usr/bin/ruby
#----------------------------------------------------------------------------------
# BibleGateway passage lookup and parser to Markdown
# (c) Jonathan Clark, v0.1, 13.4.2020
#----------------------------------------------------------------------------------
# Uses BibleGateway.com's passage lookup tool to find
# a passage and turn into Markdown usable in other ways.
#
# It passes 'reference' through to the BibleGateway parser to work out what range
# of verses should be included.
#
# The Markdown output includes:
# - passage reference
# - version abbreviation
# - passage text
# - copyright info
# Optionally also:
# - verse (and chapter) numbers
# - footnotes
# - sub-headings
#----------------------------------------------------------------------------------
# TODO:
# * [ ] Allow version option's input string
#----------------------------------------------------------------------------------
# Page structure:
# - lots of header guff until <body ...
# - then lots of menu, login, version and search options
# - then more options
# - finally nearly 1500 lines in ...
# - <h1 class="passage-display"> <span class="passage-display-bcv">John 3:1-3</span>  ...
#     <span class="passage-display-version">New English Translation (NET Bible)</span></h1> ...
#     <h3><span id="en-NET-26112" class="text John-3-1">Conversation with Nicodemus</span></h3> ...
#     <p class="chapter-1"><span class="text John-3-1"><span class="chapternum">3 </span> ...
#     <sup data-fn='...' class='footnote' ... >
#     Now a certain man, a Pharisee<sup data-fn='#fen-NET-26112a' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26112a&quot; title=&quot;See footnote a&quot;&gt;a&lt;/a&gt;]'>[<a href="#fen-NET-26112a" title="See footnote a">a</a>]</sup> named Nicodemus, who was a member of the Jewish ruling council,<sup data-fn='#fen-NET-26112b' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26112b&quot; title=&quot;See footnote b&quot;&gt;b&lt;/a&gt;]'>[<a href="#fen-NET-26112b" title="See footnote b">b</a>]</sup> </span> <span id="en-NET-26113" class="text John-3-2"><sup class="versenum">2 </sup>came to Jesus<sup data-fn='#fen-NET-26113c' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26113c&quot; title=&quot;See footnote c&quot;&gt;c&lt;/a&gt;]'>[<a href="#fen-NET-26113c" title="See footnote c">c</a>]</sup> at night<sup data-fn='#fen-NET-26113d' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26113d&quot; title=&quot;See footnote d&quot;&gt;d&lt;/a&gt;]'>[<a href="#fen-NET-26113d" title="See footnote d">d</a>]</sup> and said to him, “Rabbi, we know that you are a teacher who has come from God. For no one could perform the miraculous signs<sup data-fn='#fen-NET-26113e' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26113e&quot; title=&quot;See footnote e&quot;&gt;e&lt;/a&gt;]'>[<a href="#fen-NET-26113e" title="See footnote e">e</a>]</sup> that you do unless God is with him.” </span> <span id="en-NET-26114" class="text John-3-3"><sup class="versenum">3 </sup>Jesus replied,<sup data-fn='#fen-NET-26114f' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26114f&quot; title=&quot;See footnote f&quot;&gt;f&lt;/a&gt;]'>[<a href="#fen-NET-26114f" title="See footnote f">f</a>]</sup> “I tell you the solemn truth,<sup data-fn='#fen-NET-26114g' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26114g&quot; title=&quot;See footnote g&quot;&gt;g&lt;/a&gt;]'>[<a href="#fen-NET-26114g" title="See footnote g">g</a>]</sup> unless a person is born from above,<sup data-fn='#fen-NET-26114h' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26114h&quot; title=&quot;See footnote h&quot;&gt;h&lt;/a&gt;]'>[<a href="#fen-NET-26114h" title="See footnote h">h</a>]</sup> he cannot see the kingdom of God.”<sup data-fn='#fen-NET-26114i' class='footnote' data-link='[&lt;a href=&quot;#fen-NET-26114i&quot; title=&quot;See footnote i&quot;&gt;i&lt;/a&gt;]'>[<a href="#fen-NET-26114i" title="See footnote i">i</a>]</sup> </span> </p>
# - <h4>Footnotes:</h4>
#   - <li id="..."><a href="#id" title="Go to John 3:1">John 3:1</a> <span class='footnote-text'>..text....</span></li>
# - <div class="publisher-info-bottom with-single">...<a href="...">New English Translation</a> (NET)</strong> <p>NET Bible® copyright ©1996-2017 by Biblical Studies Press, L.L.C. http://netbible.com All rights reserved.</p></div></div>
#----------------------------------------------------------------------------------

require 'uri' # for dealing with URIs
require 'net/http' # for fetching page content
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html 'gem install OptionParser'
require 'colorize' # 'gem install colorize'
TextColour = :green
AltColour = :yellow

# Setting variables to tweak
TEST_FILE = 'JudeNIVUK.html'.freeze
BG_LOOKUP_URL = 'https://www.biblegateway.com/passage/?interface=print&version=%s&search=%s'.freeze
DEFAULT_VERSION = 'NET'.freeze

# Constants
START_READ_CONTENT_RE = '<div class="passage-text">'.freeze
END_READ_CONTENT_RE   = '<\/table>$'.freeze
REF_RE = '<span class="passage-display-bcv">.*?<\/span>'.freeze
MATCH_REF_RE = '<span class="passage-display-bcv">(.*?)<\/span>'.freeze
VERSION_RE = '<span class="passage-display-version">.*?<\/span>'.freeze
MATCH_VERSION_RE = '<span class="passage-display-version">(.*?)<\/span>'.freeze
PASSAGE_RE = '<h1 class="passage-display">.*(<\/p>\s*<\/div>|<\/p>\s*<div class="footnotes">)'.freeze
MATCH_PASSAGE_RE = '<h1 class="passage-display">(.*)(<\/p>\s*<\/div>|<\/p>\s*<div class="footnotes">)'.freeze
FOOTNOTE_RE = '<span class=\'footnote-text\'>.*?<\/span>'.freeze
MATCH_FOOTNOTE_RE = 'title=.*?>(.*?)<\/a>( )<span class=\'footnote-text\'>(.*)<\/span><\/li>'.freeze
COPYRIGHT_STRING_RE = '<div class="publisher-info'.freeze
MATCH_COPYRIGHT_STRING_RE = '<p>(.*)<\/p>'.freeze

#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
opts = {}
opt_parser = OptionParser.new do |o|
  o.banner = 'Usage: bg2md.rb [options] reference'
  o.separator ''
  opts[:copyright] = true
  o.on('-c', '--copyright', 'Exclude copyright notice') do
    opts[:copyright] = false
  end
  opts[:headers] = true
  o.on('-e', '--headers', 'Exclude editorial headers') do
    opts[:headers] = false
  end
  opts[:footnotes] = true
  o.on('-f', '--footnotes', 'Exclude footnotes') do
    opts[:footnotes] = false
  end
  o.on('-h', '--help', 'Show help') do
    puts o
    exit
  end
  opts[:verbose] = false
  o.on('-i', '--info', 'Show information as I work') do
    opts[:verbose] = true
  end
  opts[:numbering] = true
  o.on('-n', '--numbering', 'Exclude verse and chapter numbers') do
    opts[:numbering] = false
  end
  opts[:version] = DEFAULT_VERSION
  o.on('-v', '--version', 'Select version to lookup (default:' + DEFAULT_VERSION + ')') do
    opts[:version] = true
  end
end
opt_parser.parse! # parse out options, leaving file patterns to process
puts opts if opts[:verbose]

# Get reference given on command line
begin
  ref = ARGV.join
rescue StandardError
  puts 'Error: no reference passed. Stopping.'
end

# Form URL string to do passage lookup
uri = printf(BG_LOOKUP_URL, opts[:version], ref)
puts uri if opts[:verbose]
# by default & isn't escaped, so change that
# NB this library is deprecated, but can't get newer alternatives (e.g. CGI and WEBrick) to work
# uriEncoded = URI.escape(uri, ' &')
uriEncoded = 'https://www.biblegateway.com/passage/?interface=print&version=NET&search=jn+3.1-3'
puts uriEncoded if opts[:verbose]

# Read the full page contents, but only save the very small interesting part
begin
  # TESTING: read from local file if TEST_FILE set
  if TEST_FILE.nil?
    input_lines = Net::HTTP.get(URI.parse(uriEncoded))
    # @@@
  else
    f = File.open(TEST_FILE, 'r', encoding: 'utf-8')
    input_lines = []
    n = 0
    indent_spaces = ''
    in_interesting = false
    f.each_line do |line|
      # see if we've moved into or out of the interesting part
      if line =~ /#{START_READ_CONTENT_RE}/
        in_interesting = true
        line.scan(/^(\s*)/) { |m| indent_spaces = m.join }
      end
      in_interesting = false if line =~ /#{END_READ_CONTENT_RE}/
      next unless in_interesting

      # save this line, having chopped off the 'indent' amount of leading whitespace,
      # and checked it isn't empty
      updated_line = line.delete_prefix(indent_spaces).chomp
      next if updated_line.empty?

      input_lines[n] = updated_line
      n += 1
    end
    input_line_count = n
  end
rescue StandardError => e
  puts "  Error '#{e.exception.message}' trying to call #{uriEncoded}"
end

puts "Found #{input_line_count} interesting lines:" if opts[:verbose]

# Join adjacent lines together except where it starts with a <h1>, <ol>, <li ..>
working_lines = []
working_lines[0] = input_lines[0] # jump start this
w = 0
n = 1
while n < input_line_count
  line = input_lines[n]
  puts line.colorize(TextColour) if opts[:verbose]
  if line.lstrip =~ /(<h1>|<ol>|<li )/
    w += 1
    working_lines[w] = line
  else
    working_lines[w] = working_lines[w] + ' ' + line.lstrip
  end
  n += 1
end
working_line_count = w+1
puts "Now reduced to #{working_line_count} working lines." if opts[:verbose]

# Now read through the saved lines, saving out the various component parts
full_ref = ''
copyright = ''
passage = ''
version = ''
footnotes = []
number_footnotes = 0 # NB: counting from 0
n = 0 # NB: counting from 1
while n < working_line_count
  line = working_lines[n]
  # puts line.colorize(AltColour) if opts[:verbose]
  # Extract full reference
  line.scan(/#{MATCH_REF_RE}/) { |m| full_ref = m.join } if line =~ /#{REF_RE}/
  # Extract version title
  line.scan(/#{MATCH_VERSION_RE}/) { |m| version = m.join } if line =~ /#{VERSION_RE}/
  # Extract passage
  line.scan(/#{MATCH_PASSAGE_RE}/) { |m| passage = m.join } if line =~ /#{PASSAGE_RE}/
  # Extract copyright
  line.scan(/#{MATCH_COPYRIGHT_STRING_RE}/) { |m| copyright = m.join } if line =~ /#{COPYRIGHT_STRING_RE}/
  # Extract footnote
  if line =~ /#{FOOTNOTE_RE}/
    line.scan(/#{MATCH_FOOTNOTE_RE}/) do |m|
      footnotes[number_footnotes] = m.join
      number_footnotes += 1
    end
  end
  n += 1
end

# Only continue if we have found the passage
if passage.empty?
  puts "Error: cannot parse passage text, so stopping.".colorize(:red)  
end

# Now process the main passage text
# replace all <a class="bibleref" ...>ref</a> with [ref]
# ignore all <h2>book headings</h2>
passage.gsub!('<h2>.*?</h2>', '')
# take out all <span> and </span> elements
passage.gsub!('<span id.*?>', '') # @@@
passage.gsub!('</span>', '')
# replace &nbsp; elements with simpler spaces
passage.gsub!('&nbsp;', ' ')
# simplify verse numbers (or remove entirely if that option set)
if opts[:numbering]
  passage.gsub!('<sup class="versenum">', '')
  passage.gsub!('</sup>', '')
else
  passage.gsub!('<sup class="versenum">\d+ </sup>', '')
end

puts passage
# simplify footnotes (or remove if that option set)
if opts[:footnotes]
  passage.gsub!('<sup data-fn=\'.*? data-link=.*?\' class='footnote'', ' ')
else
  passage.gsub!('', ' ')
end
# replace <a>...</a> elements with simpler [...]
passage.gsub!('<a .*?>', '[')
passage.gsub!('</a>', ']')

# If we want footnotes, process each footnote item, simplifying
if number_footnotes > 0
  i = 0
  footnotes.each do |ff|
    # Change all <b>...</b> to *...* and <i>...</i> to _..._
    ff.gsub!('<b>', '*')
    ff.gsub!('</b>', '*')
    ff.gsub!('<i>', '_')
    ff.gsub!('</i>', '_')
    # replace all <a class="bibleref" ...>ref</a> with [ref]
    ff.gsub!('<a .*?>', '[')
    ff.gsub!('</a>', ']')
    # Remove all <span>s around other languages
    ff.gsub!('<span .*?>', '')
    ff.gsub!('</span>', '')
    footnotes[i] = ff
    i += 1
  end
end

# Finally write out text
puts "# Passage: #{full_ref} (#{version})"
puts
puts passage.to_s
puts
if number_footnotes > 0 && opts[:footnotes]
  i = 1
  footnotes.each do |ff|
    puts "[^#{i}]: #{ff}"
    i += 1
  end
end
puts
puts copyright.to_s if opts[:copyright]
