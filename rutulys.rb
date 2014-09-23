#!/usr/bin/ruby -Ku
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

  MODE = :release   # Mode ( :debug or :release )
  MAX_THREAD = 4  # Max threads to create the cache

  IGNORED_PATTERN = /^#[0-9a-zA-Z]+#/u  # File name pattern of source to be ignored
  #}}}

  # initialize  : Constructor {{{
  def initialize
    # Internal variables
    @now = Time.now
    @mutex = Mutex.new  # Giant lock ;p

    @threads = MAX_THREAD

    @index = []      # Internal index for source file
    @navigation = {} # Internal index for building navigation

    # HTML build cache
    @html_template, @html_author, @html_generator, @html_css, @html_base = nil, nil, nil, nil, nil


    # Internal settings
    @bak_suffix = ".#{@now.strftime('%Y%m%d_%H%M%S_%08N')}"

    @ignore_out = [File.basename(__FILE__), 'index.html', 'style.css']       # Ignore files in @outputpath
    @ignore_src = [File.basename(__FILE__), 'config.yaml', 'template.html']  # Ignore files in @sourcepath

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

    # Prepare a bit of this and that
    autognosis
    loadconfig
    indexer
  end
  # }}}

  # help        : Display help message {{{
  def help
print <<'TITLE'
 ___      _        _
| _ \_  _| |_ _  _| |_  _ ___
|   / || |  _| || | | || (_-<
|_|_\\_,_|\__|\_,_|_|\_, /__/
                     |__/
TITLE
    print <<HELP
 #{VERSION}

% ./#{__FILE__} [option]

\033[1mOption\033[0m
add     : Add new entry to cache
rebuild : Create caches for ALL entries
            * for when rename, remove, change older entry
HELP

    abort
  end
  #}}}
  # rebuild     : Rebuild mode {{{
  #  - create ALL caches for ALL sources
  def rebuild
    navindexer
    generator(@index)
    clean

    msgb 'I did everything I could :)'
  end
  #}}}
  # add         : Add mode {{{
  #  - Create cache for new entry
  #  - Do NOT use this method for creating cache after renaming, removing and/or updating older entry
  def add
    # Build a queue to create cache(s) which is already invalidated or does not exist.
    queue = []
    current_newest = 0
    @index.each_with_index {|i, n|
      queue << i

      if File.exist?(i[:cpath])
        current_newest = n
        break
      end
    }

    if queue.empty?
      err 'There is no file to generate any caches.'
    else
      navindexer(@index[0..(current_newest + 1)])
      generator(queue)
    end

    msgb 'I did everything I could :)'
  end
  #}}}

  private

  # parser      : Generate a parsed string (override me) {{{
  def parser(str)
    return str
  end
  #}}}

  # autognosis  : Check for primitive preferences {{{
  def autognosis
    msg, err = [], []

    msg << 'Running in debugging mode...' if MODE == :debug

    err << "MODE (#{MODE.inspect}) is unknown." if [:debug, :release].index(MODE).nil?

    err << "MAX_THREAD (#{MAX_THREAD.inspect}) should be an Integer."       unless MAX_THREAD.is_a?(Integer)
    err << "MAX_THREAD (#{MAX_THREAD.inspect}) should be between 1 and 20." unless MAX_THREAD.between?(1, 20)

    err << "IGNORED_PATTERN (#{IGNORED_PATTERN.inspect}) should be a Regexp." unless IGNORED_PATTERN.is_a?(Regexp)

    err << "Configuration file (#{configpath.inspect}) does not exist."     unless File.exist?(configpath)
    err << "Configuration file (#{configpath.inspect}) should be readable." unless File.readable?(configpath)
    err << "Template file (#{templatepath.inspect}) does not exist."        unless File.exist?(templatepath)
    err << "Template file (#{templatepath.inspect}) should be readable."    unless File.readable?(templatepath)

    err << "@ignore_out (#{@ignore_out.inspect}) should be an Array." unless @ignore_out.is_a?(Array)
    err << "@ignore_src (#{@ignore_src.inspect}) should be an Array." unless @ignore_src.is_a?(Array)

    msg.each {|m| msg(m) } unless msg.empty?
    err.each {|m| err(m) } unless err.empty?

    abort 'Misconfiguration!' unless err.empty?
  end
  #}}}
  # loadconfig  : Load configuration file {{{
  def loadconfig
    config = YAML.load(File.read(configpath, mode: 'rb:utf-8'))

    # Paths
    @outputpath = config['outputpath']  # Cache output directory
    @backuppath = config['backuppath']  # Backup directly to store older cache file

    # Settings
    @ignore_ext = config['ignore_ext']  # Extension not to interpret as a part of the title
    @cache_ext  = config['cache_ext']   # Extension to add the output file
    @timeformat = config['timeformat']  # Used for strftime in generating HTML
    @generator  = config['generator']   # Suffix of generator

    # Site customize
    @title    = config['title']
    @author   = config['author']
    @baseuri  = config['baseuri']  # Must be same location as @outputpath


    # Validation
    err = []

    err << "Output directory (#{@outputpath.inspect}) does not exist."     unless Dir.exist?(@outputpath)
    err << "Output directory (#{@outputpath.inspect}) should be writable." unless File.writable?(@outputpath)
    err << "Backup directory (#{@backuppath.inspect}) does not exist."     unless Dir.exist?(@backuppath)
    err << "Backup directory (#{@backuppath.inspect}) should be writable." unless File.writable?(@backuppath)

    err << "Style sheet file (#{stylepath.inspect}) does not exist."        unless File.exist?(stylepath)
    err << "Style sheet file (#{stylepath.inspect}) should be readable."    unless File.readable?(stylepath)

    err.each {|m| err(m) } unless err.empty?

    abort 'Misconfiguration!' unless err.empty?
  end
  #}}}

  # indexer     : Get an index for source file(s) {{{
  def indexer
    list = []
    Dir.glob("#{@sourcepath}/*") {|f|
      next unless File.file?(f)
      next unless @ignore_src.index(File.basename(f)).nil?

      file = f.encode(Encoding::UTF_8)
      path = File.absolute_path(file, File.dirname(@sourcepath))
      base = File.basename(path, @ignore_ext).strip

      if base =~ IGNORED_PATTERN
        msg "Found source file which treated as ignored. (#{file})"
        next
      end

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

  # generator   : Create cache files with parallel (wrap method of create_cache/backup_file) {{{
  def generator(list)
    abort 'Navigation index has no entry.' if @navigation.empty?

    queue = Queue.new
    list.each {|l| queue.push(l) }

    threads = []
    @threads.times {
      queue.push(nil) # Thread kill signal

      threads << Thread.new {
        while wu = queue.pop
          backup_file(wu[:cpath], backuppath(wu[:cache]))
          create_cache(wu)
        end
      }
    }

    threads.each {|t| t.join }

    # Create symbolic link to newest cache
    @@FileUtils.rm_f("#{@outputpath}/index.html")
    @@FileUtils.ln_s(File.basename(@index.first[:cpath]), "#{@outputpath}/index.html")
  end
  #}}}
  # clean       : Remove all cache(s)  which is not listed in index {{{
  def clean
    # Get a list of all cache file
    in_cache = []
    Dir.glob("#{@outputpath}/*") {|f|
      in_cache << File.basename(f) if File.file?(f)
    }

    # Clear cache files which is not listed in the index
    remove = in_cache - @index.map {|i| File.basename(i[:cpath]) } - @ignore_out
    remove.each {|c|
      msg "Clean up cache #{c}"
      backup_file(cachepath(c), backuppath(c))
      @@FileUtils.rm_f(cachepath(c))
    }
  end
  #}}}

  # create_cache: Create cache file {{{
  def create_cache(entry)
    content = parser(File.read(entry[:path], mode: 'rb:utf-8')).strip
    err "Empty cache file will be created for #{entry[:path]}" if content.empty?

    fputs(entry[:cpath], build_page(entry, content))
    File.utime(entry[:mtime], entry[:mtime], entry[:cpath]) if MODE == :release

    msg "Created a cache file for #{entry[:path]}"
  end
  #}}}
  # backup_file : Create backup file {{{
  def backup_file(src, dst)
    return unless File.exist?(src)

    mkwdir(File.dirname(dst))
    @@FileUtils.copy_file(src, dst, true, true)
  end
  #}}}

  # build_page  : Build a HTML of cache {{{
  def build_page(entry, content)
    return sprintf(@html_template ||= File.read(templatepath, mode: 'rb:utf-8').gsub(/(%[^\{])/, '%\1'),
                    title:      CGI.escapeHTML("#{entry[:name]}"),
                    generator:  @html_generator ||= CGI.escapeHTML("Rutulys/#{VERSION} (UTF-8) #{@generator}".strip),
                    baseuri:    @html_base      ||= CGI.escapeHTML(@baseuri),
                    stylesheet: @html_css       ||= CGI.escapeHTML("style.css?#{File.mtime(stylepath).tv_sec.to_s}"),
                    canonical:  CGI.escapeHTML("#{@baseuri}/#{entry[:cache]}"),
                    modified:   CGI.escapeHTML(entry[:mtime].strftime(@timeformat)),
                    next:       build_nav(@navigation[entry[:path]][:next]),
                    prev:       build_nav(@navigation[entry[:path]][:prev]),
                    content:    content
                  )
  end
  #}}}
  # build_nav   : Build a navigation link {{{
  def build_nav(nav)
    return nav.nil? ? '<!-- n/a -->' : "<a href=\"#{CGI.escapeHTML(nav[:cache])}\">#{CGI.escapeHTML(nav[:name])}</a>"
  end
  #}}}

  # cachepath   : Get path to a cache file {{{
  def cachepath(cache)
    return "#{@outputpath}/#{cache}#{@cache_ext}"
  end
  #}}}
  # backuppath  : Get path to a cache backup file {{{
  def backuppath(cache)
    return "#{@backuppath}/#{cache}/#{cache}#{@bak_suffix}"
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
  # stylepath   : Get path to the style sheet {{{
  def stylepath
    return "#{@outputpath}/style.css"
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


rc = Rutulys.new

case ARGV[0]
when 'add'     then rc.add
when 'rebuild' then rc.rebuild
else                rc.help
end

