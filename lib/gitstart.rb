require 'fileutils'

module Gitstart
  
  def self.ui
    @ui ||= ::Gitstart::UI.new(STDOUT)
  end

  def self.ui=(io)
    @ui = ::Gitstart::UI.new(io)
  end
  
  class UI
    def initialize(io = nil, verbose = false)
      @io = io
      @verbose = verbose
      @indent_string = "\t"
      @indent_level = 0
    end
    
    def indent
      @indent_level += 1
    end
    
    def unindent
      if @indent_level > 0
        @indent_level -= 1
      end
    end
    
    def puts(*args)
      return unless @io

      if args.empty?
        @io.puts ""
      else
        args.each { |msg| @io.puts("#{@indent_string * @indent_level}#{msg}") }
      end

      @io.flush
      nil
    end

    def abort(msg)
      @io && Kernel.abort("gitstart: #{msg}")
    end

    def vputs(*args)
      puts(*args) if @verbose
    end
  end
  
  module Help
    # def show_help(command, commands = commands)
    #   subcommand = command.to_s.empty? ? nil : "#{command} "
    #   ui.puts "Usage: rip #{subcommand}COMMAND [options]", ""
    #   ui.puts "Commands available:"
    # 
    #   show_command_table begin
    #     commands.zip begin
    #       commands.map { |c| @help[c].first unless @help[c].nil? }
    #     end
    #   end
    # end

  private
    def ui
      ::Gitstart.ui
    end
  end
  
  module Sh
    module Svn
      extend self
      
      def get_externals(repo, recursive=true)
        args = ''
        if recursive
          args << '-R'
        end
          
        `svn propget svn:externals #{args} #{repo}`
      end
      
      def log(repo, limit=nil)
        args = ''
        if limit
          args << "--limit #{limit}"
        end
        `svn log #{args} #{repo}`
      end
    end
    
    module Git
      extend self

      def checkout(branch_name)
        `git checkout -b #{branch_name} 2>/dev/null`
      end
    end
    
    module GitSvn
      extend self
      
      def clone(repo, target, revision=nil)
        args = ''
        if revision
          args << "-r #{revision}"
        end
        
        `git svn clone #{args} #{repo} #{target} 2>&1`
      end
      
      def show_ignore
        `git svn show-ignore`
      end
    end
  end
  
  module Application
    extend self
    extend Help
    
    BRANCH = "working"
    
    
    
    def run(args)
      unless args.size == 2
        ui.puts "Usage: gitstart <svn-repository> <target-dir>"
        exit 1
      end
      
      repo, target = args
      fullpath = File.expand_path(target)
      
      check_for_local_dir(fullpath)
      clone_repository(repo, fullpath)
      clone_externals(repo, fullpath)
      create_working_branch(fullpath)
    end
    
    def check_for_local_dir(target)
      if File.exist?(target)
        ui.puts "Error: target #{target} already exists - please move it!"
        exit 1
      end
    end
    
    def clone_repository(repo, target)
      ui.puts "finding latest revision of #{repo}"
      revision = get_latest_revision(repo)
      
      ui.puts "creating git repository in #{target}"
      ui.indent
      
      results = Sh::GitSvn.clone(repo, target, revision)
      empty_dirs = results.split("\n").collect {|line| line =~ /^W: \+empty_dir: (.*)$/; $1}.compact
      empty_dirs.each do |dir|
        ui.puts "making empty directory: #{dir}"
        FileUtils.mkdir_p( File.join(target, dir) )
      end

      Dir.chdir(target) do 
        ignore_generated_files
      end
      
      ui.unindent
    end
    
    def parse_external_repos(repos_str)
      results = repos_str.chomp.split("\n").reject{|line| line.nil? or line.empty?}
      
      repos = results.collect do |line|
        line.split(' ', 2)
      end
      
      repos
    end
    
    def get_externals(repo)
      results = Sh::Svn.get_externals(repo)
      results = results.chomp.split("\n\n").reject{|line| line.nil? or line.empty?}
      
      externals = results.collect do |line|
        dir, repos = line.split(' - ', 2)
        dir = File.basename(dir.gsub(repo, ''))
        repos = parse_external_repos(repos)
        [dir, repos]
      end
      
      externals
    end
    
    def clone_externals(repo, target)
      ui.puts "checking for svn:externals to install from #{repo}"
      ui.indent
      
      externals = get_externals(repo)
      
      Dir.chdir(target) do
        externals_dir=".externals"
        FileUtils.mkdir_p(externals_dir)
        
        File.open('.git/info/exclude', 'a') { |f| f.puts externals_dir }
        
        externals.each do |dir, repos|
          repos.each do |ext_dir, ext_repo|
            unless File.exist?(File.join(externals_dir, ext_dir))
              clone_repository(ext_repo, File.join(externals_dir, ext_dir))
            end
              
            ui.puts "symlinking #{ext_dir} into #{target}/#{dir}"
            Dir.chdir(dir) do
              FileUtils.symlink(File.join(target, externals_dir, ext_dir), ext_dir, :force => true)
            end
            File.open('.git/info/exclude', 'a') { |f| f.puts File.join(dir, ext_dir) }
          end
        end
      end
      
      ui.unindent
    end
    
    def create_working_branch(target)
      ui.puts "creating '#{BRANCH}' branch on #{target}"
      Dir.chdir( target ) do
        result = Sh::Git.checkout(BRANCH)
      end
    end
    
    def get_latest_revision(repo)
      results = Sh::Svn.log(repo, 1).chomp.split("\n")
      rev = results[1].split()[0].gsub(/^r/, '')
      rev
    end
    
    def ignore_generated_files
      ui.puts "setting ignored files from subversion (this can take a while)"
      
      File.open('.git/info/exclude', 'a') do |f|
        f.puts Sh::GitSvn.show_ignore
        f.puts
        f.puts "# Git files"
        f.puts ".gitignore"
      end
    end
    
  end
end