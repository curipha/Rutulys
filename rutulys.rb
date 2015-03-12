#!/usr/bin/env ruby
#  ___      _        _
# | _ \_  _| |_ _  _| |_  _ ___
# |   / || |  _| || | | || (_-<
# |_|_\\_,_|\__|\_,_|_|\_, /__/
#                      |__/

require 'cgi/util'
require 'fileutils'
require 'thread'
require 'yaml'

class Rutulys

  # Preferences {{{
  VERSION = '0.0.1'

  MODE = :release # Mode ( :debug or :release )
  MAX_THREAD = 4  # Max threads to create the cache
  #}}}

  # initialize  : Constructor {{{
  def initialize
    case ARGV[0]
    when 'build' then build
    else              help
    end
  end
  # }}}

  # help        : Display help message {{{
  def help
    abort <<HELP
Rutulys #{VERSION}

% ./#{File.basename(__FILE__)} [option]

\033[1mOption\033[0m
build : Create caches for ALL entries
HELP
  end
  #}}}
  # build       : Build mode {{{
  def build
    initiate
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

  # parser      : Generate a parsed string (override me) {{{
  def parser(str)
    return str
  end
  #}}}

  # initiate    : Initiate myself {{{
  def initiate
    # Internal variables
    @now = Time.now
    @mutex = Mutex.new  # Giant lock ;p

    @threads = MAX_THREAD

    @index = []      # Internal index for source file
    @navigation = {} # Internal index for building navigation

    # HTML build cache
    @html_template = nil

    # Internal settings
    @sourcepath = Dir.pwd # Source directory

    # Prepare mode-based environment
    case MODE
    when :release
      @@FileUtils = FileUtils
      #@@FileUtils = FileUtils::Verbose
    when :debug
      @threads = 1  # Force single thread
      @@FileUtils = FileUtils::DryRun
    end
  end
  #}}}
  # autognosis  : Check for primitive preferences {{{
  def autognosis
    msg, err = [], []

    msg << 'Running in debugging mode...' if MODE == :debug

    err << "MODE (#{MODE.inspect}) is unknown." if [:debug, :release].index(MODE).nil?

    err << "MAX_THREAD (#{MAX_THREAD.inspect}) should be an Integer."       unless MAX_THREAD.is_a?(Integer)
    err << "MAX_THREAD (#{MAX_THREAD.inspect}) should be between 1 and 20." unless MAX_THREAD.between?(1, 20)

    err << "Configuration file (#{configpath.inspect}) does not exist or is not readable." unless File.readable?(configpath)
    err << "Template file (#{templatepath.inspect}) does not exist or is not readable."    unless File.readable?(templatepath)

    msg.each {|m| msg(m) } unless msg.empty?
    err.each {|m| err(m) } unless err.empty?

    abort 'Misconfiguration!' unless err.empty?
  end
  #}}}
  # loadconfig  : Load configuration file {{{
  def loadconfig
    config = YAML.load(File.read(configpath, mode: 'rb:utf-8'))

    # Paths
    @deploypath = config['deploypath']  # Deploy directory

    # Settings
    @timeformat = config['timeformat']  # Used for strftime in generating HTML

    # Site customize
    @title    = config['title']
    @baseuri  = config['baseuri']  # Must be same location as @deploypath


    # Validation
    err = []

    err << "Parent directory of deploying point (#{@deploypath.inspect}) does not exist or is not writable." unless File.writable?(File.dirname(@deploypath))

    err.each {|m| err(m) } unless err.empty?

    abort 'Misconfiguration!' unless err.empty?
  end
  #}}}

  # indexer     : Get an index for source file(s) {{{
  def indexer
    list = []
    Dir.glob("#{@sourcepath}/library/*", File::FNM_DOTMATCH) {|f|
      next unless File.file?(f)
      next unless File.readable?(f)

      file  = f.encode(Encoding::UTF_8)
      path  = File.absolute_path(file, File.dirname(@sourcepath))
      base  = File.basename(path, '.*').strip
      mtime = File.mtime(path)
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

    @navigation = nav
  end
  #}}}

  # generator   : Create cache files with parallel (wrap method of create_cache) {{{
  def generator(list)
    abort 'Navigation index has no entry.' if @navigation.empty?

    # Clear the deploy directory
    if File.exist?(@deploypath)
      @@FileUtils.rm_rf(@deploypath)
      mkwdir(@deploypath)
    end

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
    @@FileUtils.ln_s(File.basename(@index.first[:cpath]), "#{@deploypath}/index.html")
  end
  #}}}
  # setasset    : Copy asset files to deploying point {{{
  def setasset(list)
    return unless File.directory?("#{@sourcepath}/asset")

    FileUtils.cp_r(Dir.glob(["#{@sourcepath}/asset/*", "#{@sourcepath}/asset/.[^.]*"]), "#{@deploypath}")
  end
  #}}}

  # create_cache: Create cache file {{{
  def create_cache(entry)
    content = parser(File.read(entry[:path], mode: 'rb:utf-8')).strip
    err "Empty cache file will be created for #{entry[:path]}" if content.empty?

    fputs(entry[:cpath], build_page(entry, content))

    msg "Created a cache file for #{entry[:path]}"
  end
  #}}}

  # build_page  : Build a HTML of cache {{{
  def build_page(entry, content)
    return sprintf(@html_template ||= File.read(templatepath, mode: 'rb:utf-8').gsub(/(%[^\{])/, '%\1'),
                    title:      htmlstr("#{entry[:name]}"),
                    canonical:  htmlstr("#{@baseuri}/#{entry[:cache]}"),
                    modified:   htmlstr(entry[:mtime].strftime(@timeformat)),
                    next:       build_nav(@navigation[entry[:path]][:next]),
                    prev:       build_nav(@navigation[entry[:path]][:prev]),
                    content:    content
                  )
  end
  #}}}
  # build_nav   : Build a navigation link {{{
  def build_nav(nav)
    return nav.nil? ? '<!-- n/a -->' : "<a href=\"#{htmlstr(nav[:cache])}\">#{htmlstr(nav[:name])}</a>"
  end
  #}}}

  # cachepath   : Get path to a cache file {{{
  def cachepath(cache)
    return "#{@deploypath}/archive/#{cache}.html"
  end
  #}}}
  # configpath  : Get path to the configuration file {{{
  def configpath
    return "#{@sourcepath}/config.yaml"
  end
  #}}}
  # templatepath: Get path to the template file {{{
  def templatepath
    return "#{@sourcepath}/template.html"
  end
  #}}}

  # htmlstr     : Get HTML-escaped string {{{
  def htmlstr(str)
    return CGI.escapeHTML(str)
  end
  #}}}

  # fputs       : Write string to file {{{
  def fputs(path, str)
    mkwdir(File.dirname(path))
    @@FileUtils.touch(path)       unless File.exist?(path)
    @@FileUtils.chmod(0644, path) unless File.writable?(path)

    if MODE == :debug
      puts "File.open('#{path}')"
    else
      # Never use "w" because it truncates the file *BEFORE* lock
      File.open(path, 'r+b:utf-8') {|fp|
        fp.flock(File::LOCK_EX)
        fp.rewind
        fp.write(str)
        fp.flush
        fp.truncate(fp.pos)
      }
    end

    @@FileUtils.chmod(0444, path)
  end
  #}}}
  # mkwdir      : Create writable directory {{{
  def mkwdir(path)
    @@FileUtils.mkdir_p(path, { mode: 0755 }) unless Dir.exist?(path)
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
    log(str)
  end
  #}}}
  # msgb        : Display bold message {{{
  def msgb(str)
    log("\033[1m#{str}\033[0m")
  end
  #}}}

end

Rutulys.new

