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

class MyRedcarpet < Redcarpet::Render::XHTML
  include Rouge::Plugins::Redcarpet
end

class Rutulys

  # Accessors {{{
  attr_accessor :verbose, :threads
  #}}}

  # initialize  : Constructor {{{
  def initialize
    # Internal variables
    @now = Time.now
    @mutex = Mutex.new  # Giant lock ;p

    @index = [] # Internal index for source file
    @nav = {}   # Internal index for building navigation

    # HTML build cache
    @html_template = nil

    # Internal settings
    @sourcepath = Pathname.pwd

    # Prepare markdown renderer
    @render = Redcarpet::Markdown.new(MyRedcarpet, {
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
    navindexer

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

      base  = path.basename('.*').to_s.strip
      mtime = path.mtime
      cache = CGI.escape(base)

      list << [@now - mtime, base, { # sort key (1. mtime desc, 2. base asc)
                path:  path,             # Full path of file (e.g. /home/jane/file.ext )
                name:  base,             # Name of file      (e.g.            file     )
                cache: cache,            # URI encoded name
                cpath: cachepath(cache), # Path to cache file
                mtime: mtime             # Modified time of file (Time object)
              }]
    }

    abort 'No source file is found.' if list.empty?

    @index = (list.sort.transpose)[2]
  end
  #}}}
  # navindexer  : Get an navigation index {{{
  def navindexer(list = @index)
    nav = {}

    n = nil
    list.each_cons(2) {|c, p|
      nav[c[:path]] = { next: n, prev: p }
      n = c
    }
    nav[list.last[:path]] = { next: n, prev: nil }

    @nav = nav
  end
  #}}}

  # generator   : Create cache files with parallel (wrap method of create_cache) {{{
  def generator(list)
    abort 'Navigation index has no entry.' if @nav.empty?

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
    (@deploypath + 'index.html').make_symlink(@index.first[:cpath].relative_path_from(@deploypath))
  end
  #}}}
  # setasset    : Copy asset files to deploying point {{{
  def setasset()
    return unless assetpath.directory?

    FileUtils.cp_r(assetpath.children, @deploypath)
  end
  #}}}

  # create_cache: Create cache file {{{
  def create_cache(entry)
    content = parser(entry[:path].read(mode: 'rb:utf-8')).strip
    err "Empty cache file will be created for #{entry[:path]}" if content.empty?

    fputs(entry[:cpath], build_page(entry, content))

    msg "Created a cache file for #{entry[:path]}"
  end
  #}}}

  # parser      : Generate a parsed string {{{
  def parser(str)
    return @render.render(str)
  end
  #}}}

  # build_page  : Build a HTML of cache {{{
  def build_page(entry, content)
    return sprintf(@html_template,
                    title:      htmlstr("#{entry[:name]}"),
                    canonical:  htmlstr("#{@baseuri}/#{entry[:cache]}"),
                    modified:   htmlstr(entry[:mtime].strftime(@timeformat)),
                    next:       @nav[entry[:path]][:next].nil? ? '' : "<div id=\"next\">#{build_link(@nav[entry[:path]][:next][:cache], @nav[entry[:path]][:next][:name])}</div>",
                    prev:       @nav[entry[:path]][:prev].nil? ? '' : "<div id=\"prev\">#{build_link(@nav[entry[:path]][:prev][:cache], @nav[entry[:path]][:prev][:name])}</div>",
                    content:    content
                  )
  end
  #}}}
  # build_nav   : Build a link {{{
  def build_link(uri, name)
    return "<a href=\"#{htmlstr(uri)}\">#{htmlstr(name)}</a>"
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

r = Rutulys.new

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

