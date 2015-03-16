#!/usr/bin/env ruby
#  ___      _        _
# | _ \_  _| |_ _  _| |_  _ ___
# |   / || |  _| || | | || (_-<
# |_|_\\_,_|\__|\_,_|_|\_, /__/
#                      |__/

require 'fileutils'
require 'optparse'
require 'pathname'
require 'thread'

require 'rubygems'
require 'redcarpet'
require 'rouge'
require 'rouge/plugins/redcarpet'
require 'safe_yaml'

module Rutulys

  class Render < Redcarpet::Render::XHTML
    include Rouge::Plugins::Redcarpet
  end

  class Page
    attr_reader   :path, :name, :title, :mtime, :category
    attr_accessor :next, :prev

    def initialize(*args)
      @category = []
    end
  end

  # Article class {{{
  class Article < Page
    YAML_FRONT_MATTER = /\A---\n.*?\n?^---$/mu
    CATEGORY_PATTERN  = /\A[0-9A-Za-z-]+\z/u

    attr_reader :yaml

    def initialize(path)
      super

      @path  = path                            # Full path of file (e.g. /home/jane/file.ext )
      @name  = path.basename('.*').to_s.strip  # Name of file      (e.g.            file     )
      @mtime = path.mtime                      # Modified time of file (Time object)

      load_yamlheader

      @title = @name if @title.nil?            # Title
    end

    def cache
      return "archive/#{@name}.html"          # Local file (destination)
    end
    def link
      return "/archive/#{Util::urlencode(@name)}" # Link path
    end
    def content
      raw = @path.read(mode: 'rb:utf-8')
      raw = raw.sub(YAML_FRONT_MATTER, '') if @yaml
      return raw
    end

    def <=>(obj)
      c = obj.mtime <=> @mtime  # descending
      return c unless c == 0
      return @title <=> obj.title
    end

    private

    def load_yamlheader
      @yaml = false

      if @path.read(mode: 'rb:utf-8') =~ YAML_FRONT_MATTER
        front = YAML.load($&, safe: true)

        unless front.nil?
          @yaml = true

          @title = front['title'].strip unless front['title'].to_s.empty?

          unless front['category'].nil?
            @category = front['category'].to_s.split(' ').uniq.inject([]) {|result, category|
              (category =~ CATEGORY_PATTERN) ? result << Rutulys::Category.new(category) : result
            }
          end
        end
      end
    end
  end
  #}}}
  # Category class {{{
  class Category < Page
    def initialize(title)
      super

      @name  = title
      @title = "Category: #{title}"

      @articles = []
    end

    def add(article)
      @articles << article
    end
    def count
      return @articles.length
    end

    def cache
      return "category/#{@name}.html"
    end
    def link
      return "/category/#{Util::urlencode(@name)}"
    end
    def content
      return @articles.sort.inject([]) {|result, entry| result << yield(entry) }.join("\n")
    end

    def <=>(obj)
      return @name <=> obj.name
    end
  end
  #}}}

  class Main
    # Accessors {{{
    attr_accessor :verbose, :threads
    #}}}

    # initialize  : Constructor {{{
    def initialize
      # Internal variables
      @now = Time.now
      @mutex = Mutex.new  # Giant lock ;p

      @index    = [] # Internal index for source file
      @category = [] # Internal index for category

      # HTML build cache
      @html_template = nil
      @category_list = nil

      # Internal settings
      @sourcepath = Pathname.pwd

      # Prepare markdown renderer
      @render = Redcarpet::Markdown.new(Rutulys::Render, {
        no_intra_emphasis: true,
        tables: true,
        fenced_code_blocks: true,
        disable_indented_code_blocks: true,
        space_after_headers: true,
        superscript: true
      })

      # Configurable variables
      @verbose = false
      @threads = 4
    end
    # }}}

    # build       : Build mode {{{
    def build
      loadconfig

      indexer
      generator(@index + @category)
      setasset

      msgb 'I did everything I could :)'
    end
    #}}}

    private

    # loadconfig  : Load configuration file {{{
    def loadconfig
      abort "Configuration file (#{configpath}) does not exist or is not readable." unless configpath.readable?

      config = YAML.load_file(configpath, safe: true)

      # Paths
      @deploypath = Pathname.new(config['deploypath'])  # Deploy directory

      # Settings
      @baseuri    = config['baseuri']  # Must be same location as @deploypath
      @timeformat = config['timeformat']  # Used for strftime in generating HTML

      @categ_timeformat = config['category']['timeformat']  # Used for strftime in generating HTML


      # Validation
      err = []

      err << "Template file (#{templatepath}) does not exist or is not readable." unless templatepath.readable?
      err << "Parent directory of deploying point (#{@deploypath}) does not exist or is not writable." unless @deploypath.dirname.writable?

      unless err.empty?
        err.each {|m| err(m) }
        abort
      end
    end
    #}}}

    # indexer     : Get an index for source file(s) {{{
    def indexer
      list = []
      librarypath.each_child {|path|
        next unless path.file?
        next unless path.readable?

        list << Rutulys::Article.new(path)
      }

      abort 'No source file is found.' if list.empty?

      list.sort.each_cons(2) {|current, previous|
        current.prev  = previous
        previous.next = current
      }
      @index = list.sort

      categories = []
      list.each {|article|
        article.category.each {|entry_category|
          categobj = categories.find {|category| category.name == entry_category.name }
          if categobj.nil?
            categobj = Rutulys::Category.new(entry_category.name)
            categories << categobj
          end

          categobj.add(article)
        }
      }
      @category = categories.sort
    end
    #}}}

    # generator   : Create cache files in parallel {{{
    def generator(list)
      # Clear the deploy directory
      if @deploypath.exist?
        @deploypath.rmtree
        @deploypath.mkdir
      end

      # Prepare template cache
      @html_template ||= templatepath.read(mode: 'rb:utf-8').gsub(/(%[^\{])/, '%\1')

      if @category_list.nil?
        @category_list = @category.inject([]) {|result, category|
          result << "<li>#{Util::build_link(category.link, category.name)} <small>#{category.count}</small></li>"
        }.join("\n")
      end

      # Generate page caches
      queue = Queue.new
      list.each {|l| queue.push(l) }

      threads = []
      @threads.times {
        queue.push(nil) # Thread kill signal

        threads << Thread.new {
          while wu = queue.pop
            create_cache(wu)
          end
        }
      }

      threads.each {|t| t.join }

      # Create symbolic link to newest cache
      (@deploypath + 'index.html').make_symlink(cachepath(@index.first.cache).relative_path_from(@deploypath))
    end
    #}}}
    # setasset    : Copy asset files to deploying point {{{
    def setasset
      return unless assetpath.directory?

      FileUtils.cp_r(assetpath.children, @deploypath)
    end
    #}}}

    # create_cache: Create cache file {{{
    def create_cache(entry)
      case
      when entry.is_a?(Rutulys::Article)
        raw = entry.content
      when entry.is_a?(Rutulys::Category)
        raw = entry.content {|localentry|
          "- #{Util::build_link(localentry.link, localentry.title)} (#{localentry.mtime.strftime(@categ_timeformat)})"
        }
      else
        err "Process skipped since entry type unknown (#{entry})"
        return
      end
      content = parser(raw).strip
      err "Empty cache file will be created for #{entry.path}" if content.empty?

      Util::write(cachepath(entry.cache),
            sprintf(@html_template, {
              title:     Util::htmlescape(entry.title),
              category:  entry.category.sort.inject([]) {|result, cat| result << Util::build_link(cat.link, cat.name)}.join("\n"),
              canonical: Util::htmlescape(@baseuri + entry.link),
              modified:  entry.mtime.nil? ? '' : Util::htmlescape(entry.mtime.strftime(@timeformat)),
              next:      entry.next.nil?  ? '' : "<div id=\"next\">#{Util::build_link(entry.next.link, entry.next.title)}</div>",
              prev:      entry.prev.nil?  ? '' : "<div id=\"prev\">#{Util::build_link(entry.prev.link, entry.prev.title)}</div>",
              content:   content,
              categlist: @category_list
            })
      )

      msg "Create a cache file for: #{entry.path.nil? ? '-' : entry.path} (#{entry.title})"
    end
    #}}}
    # parser      : Generate a parsed string {{{
    def parser(str)
      return @render.render(str)
    end
    #}}}

    # cachepath   : Get path to a cache file {{{
    def cachepath(cache)
      return @deploypath + cache
    end
    #}}}
    # configpath  : Get path to the configuration file {{{
    def configpath
      return @sourcepath + 'config.yaml'
    end
    #}}}
    # templatepath: Get path to the template file {{{
    def templatepath
      return @sourcepath + 'template.html'
    end
    #}}}
    # librarypath : Get path to the library directory {{{
    def librarypath
      return @sourcepath + 'library'
    end
    #}}}
    # assetpath   : Get path to the asset directory {{{
    def assetpath
      return @sourcepath + 'asset'
    end
    #}}}

    # log         : Display log message (Never to call directly. Use `err` or `msg`) {{{
    def log(str)
      @mutex.synchronize {
        warn "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%04N")}] #{str}"
      }
    end
    #}}}
    # err         : Display continuable error message {{{
    def err(str)
      log("\033[1;31m#{str}\033[0m")
    end
    #}}}
    # msg         : Display message {{{
    def msg(str)
      log(str) if @verbose
    end
    #}}}
    # msgb        : Display bold message {{{
    def msgb(str)
      log("\033[1m#{str}\033[0m")
    end
    #}}}
  end

  module Util
    extend self

    # urlencode   : Get URL-encoded string {{{
    def urlencode(str)
      return str.to_s.b.gsub(/[^0-9A-Za-z_.-]/n) {|c| sprintf('%%%02X', c.unpack('C').first) }
    end
    #}}}
    # htmlescape  : Get HTML-escaped string {{{
    def htmlescape(str)
      return str.gsub(/['"&<>]/, { "'" => '&#39;', '"' => '&quot;', '&' => '&amp;', '<' => '&lt;', '>' => '&gt;' })
    end
    #}}}
    # build_link  : Build a link {{{
    def build_link(uri, name)
      return "<a href=\"#{htmlescape(uri)}\">#{htmlescape(name)}</a>"
    end
    #}}}

    # write       : Write string to file {{{
    def write(path, str)
      path.dirname.mkpath unless path.dirname.exist?
      path.chmod(0644) if path.exist?
      path.write(str, nil, mode: 'w+b:utf-8')
      path.chmod(0444)
    end
    #}}}
  end
end

r = Rutulys::Main.new

mode = :nop

OptionParser.new do |op|
  op.version = '0.1.0'

  op.on('--verbose', 'Verbose mode') {|flag|
    r.verbose = flag
  }
  op.on('-t THREAD', '--thread=THREAD', "Set a number of thread to build a page (Default = #{r.threads})") {|value|
    thread = value.to_i

    abort "THREAD (#{value.inspect}) should be between 1 and 20." unless thread.between?(1, 20)

    r.threads = thread
  }

  op.on('-b', '--build', 'Create caches for ALL entries') {|flag|
    mode = :build
  }

  op.parse(ARGV)
end

case mode
when :build
  r.build
else
  abort 'You have to specify -b (or --build) option to build your page.'
end

