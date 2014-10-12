#!/usr/bin/env ruby

require '../rutulys.rb'

require 'rubygems'
require 'redcarpet'
require 'pygments.rb'

class MyRedcarpet < Redcarpet::Render::XHTML
  def header(text, level)
    h_offset = 2
    level = level < ( 6 - h_offset ) ? level + h_offset : 6

    return "<h#{level}>#{text}</h#{level}>"
  end

  def block_code(code, language)
    return Pygments.highlight(code, lexer: language)
  end
end

class MyRutulys < Rutulys
  # Add a logic to initialize the markdown parser
  def initialize
    super

    @rc = Redcarpet::Markdown.new(MyRedcarpet,
                                  {
                                    no_intra_emphasis: true,
                                    tables: true,
                                    fenced_code_blocks: true,
                                    disable_indented_code_blocks: true,
                                    space_after_headers: true,
                                    superscript: true
                                  })
  end

  # Implement markdown parser
  def parser(str)
    return @rc.render(str)
  end
end


mr = MyRutulys.new

case ARGV[0]
when 'add'     then mr.add
when 'rebuild' then mr.rebuild
else                mr.help
end

