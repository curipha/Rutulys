#!/usr/bin/env ruby
#  ___      _        _
# | _ \_  _| |_ _  _| |_  _ ___
# |   / || |  _| || | | || (_-<
# |_|_\\_,_|\__|\_,_|_|\_, /__/
#                      |__/

require 'cgi/util'
require 'fileutils'
require 'optparse'
require 'pathname'
require 'thread'
require 'yaml'

require 'rubygems'
require 'redcarpet'
require 'rouge'
require 'rouge/plugins/redcarpet'

module Rutulys

  class Render < Redcarpet::Render::XHTML
    include Rouge::Plugins::Redcarpet
  end

  # Article class {{{
  class Article
    attr_reader :path, :name, :mtime, :cache
    attr_accessor :next, :prev

    def initialize(path)
      @path   = path                            # Full path of file (e.g. /home/jane/file.ext )
      @name   = path.basename('.*').to_s.strip  # Name of file      (e.g.            file     )
      @mtime  = path.mtime                      # Modified time of file (Time object)
      @cache  = CGI.escape(@name)               # URI encoded name

      @next, @prev = nil, nil
    end

    def <=>(obj)
      c = @mtime <=> obj.mtime
      return c unless c == 0
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

      @index = [] # Internal index for source file

      # HTML build cache
      @html_template = nil

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
      autognosis
      loadconfig

      indexer
      generator(@index)
      setasset

      msgb 'I did everything I could :)'
    end
    #}}}

    private

    # autognosis  : Check for primitive preferences {{{
    def autognosis
      err = []

      err << "Configuration file (#{configpath}) does not exist or is not readable." unless configpath.readable?
      err << "Template file (#{templatepath}) does not exist or is not readable."    unless templatepath.readable?

      err.each {|m| err(m) } unless err.empty?

      abort 'Misconfiguration!' unless err.empty?
    end
    #}}}
    # loadconfig  : Load configuration file {{{
    def loadconfig
      config = YAML.load(configpath.read(mode: 'rb:utf-8'))

      # Paths
      @deploypath = Pathname.new(config['deploypath'])  # Deploy directory

      # Settings
      @timeformat = config['timeformat']  # Used for strftime in generating HTML

      # Site customize
      @title    = config['title']
      @baseuri  = config['baseuri']  # Must be same location as @deploypath


      # Validation
      err = []

      err << "Parent directory of deploying point (#{@deploypath}) does not exist or is not writable." unless @deploypath.dirname.writable?

      err.each {|m| err(m) } unless err.empty?

      abort 'Misconfiguration!' unless err.empty?
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

      list.sort.each_cons(2) {|c, n|
        c.next = n
        n.prev = c
      }
      @index = list.sort
    end
    #}}}

    # generator   : Create cache files with parallel (wrap method of create_cache) {{{
    def generator(list)
      # Clear the deploy directory
      if @deploypath.exist?
        @deploypath.rmtree
        @deploypath.mkdir
      end

      # Prepare template cache
      @html_template = templatepath.read(mode: 'rb:utf-8').gsub(/(%[^\{])/, '%\1')

      # Generate caches
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
      (@deploypath + 'index.html').make_symlink(cachepath(@index.last.cache).relative_path_from(@deploypath))
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
      content = parser(entry.path.read(mode: 'rb:utf-8')).strip
      err "Empty cache file will be created for #{entry.path}" if content.empty?

      fputs(cachepath(entry.cache),
            sprintf(@html_template, {
              title:     htmlstr(entry.name),
              canonical: htmlstr(@baseuri + cachelink(entry.cache)),
              modified:  htmlstr(entry.mtime.strftime(@timeformat)),
              next:      entry.next.nil? ? '' : "<div id=\"next\">#{build_link(cachelink(entry.next.cache), entry.next.name)}</div>",
              prev:      entry.prev.nil? ? '' : "<div id=\"prev\">#{build_link(cachelink(entry.prev.cache), entry.prev.name)}</div>",
              content:   content
            })
           )

      msg "Created a cache file for #{entry.path}"
    end
    #}}}

    # parser      : Generate a parsed string {{{
    def parser(str)
      return @render.render(str)
    end
    #}}}
    # build_link  : Build a link {{{
    def build_link(uri, name)
      return "<a href=\"#{htmlstr(uri)}\">#{htmlstr(name)}</a>"
    end
    #}}}

    # cachelink   : Get link to a cache {{{
    def cachelink(cache)
      return "/archive/#{cache}"
    end
    #}}}

    # cachepath   : Get path to a cache file {{{
    def cachepath(cache)
      return @deploypath + "archive/#{cache}.html"
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

    # htmlstr     : Get HTML-escaped string {{{
    def htmlstr(str)
      return CGI.escapeHTML(str)
    end
    #}}}

    # fputs       : Write string to file {{{
    def fputs(path, str)
      path.dirname.mkpath unless path.dirname.exist?
      path.chmod(0644) if path.exist?
      path.open('w+b:utf-8') {|fp|
        fp.flock(File::LOCK_EX)
        fp.rewind
        fp.write(str)
        fp.flush
        fp.truncate(fp.pos)
      }
      path.chmod(0444)
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

end

r = Rutulys::Main.new

mode = :nop

OptionParser.new do |op|
  op.version = '0.0.1'

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

