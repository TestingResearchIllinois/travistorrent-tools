require 'colorize'
require "archive" #for reading GZ files with native parser

load 'lib/travis_fold.rb'


# Provides general language-independent analyzer for Travis logfiles. Dynamically mixes-in the most specific language
# analyzer from the languages packages. If no specific analyzer is found, it prrovides basic statistics about any build
# process on Travis.

class LogFileAnalyzer
  attr_reader :build_number, :job_id, :commit, :build_id

  attr_reader :logFile
  attr_reader :status, :primary_language
  attr_reader :tests_run
  attr_reader :num_tests_run, :num_tests_failed, :num_tests_ok, :num_tests_skipped
  attr_reader :test_duration
  attr_reader :setup_time_before_build

  @folds
  @test_lines
  @analyzer
  @frameworks

  @OUT_OF_FOLD

  def initialize(file, data = nil)
    @OUT_OF_FOLD = 'out_of_fold'
    @folds = Hash.new
    @test_lines = Array.new
    @frameworks = Array.new

    get_build_info(file)
    if data == nil
      @logFile = File.read(file)
    else
      @logFile = data;
    end

    encoding_options = {
        :invalid => :replace, # Replace invalid byte sequences
        :undef => :replace, # Replace anything not defined in ASCII
        :replace => '', # Use a blank for those replacements
        :universal_newline => true # Always break lines with \n
    }
    @logFile = @logFile.encode(Encoding.find('ASCII'), encoding_options)
    @logFileLines = @logFile.lines

    @primary_language = 'unknown'
    @analyzer = 'plain'
    @tests_run = false
    @tests_failed = Array.new
    @status = 'unknown'
    @did_tests_fail = ''
  end

  def mixin_specific_language_analyzer
    split
    analyze_primary_language
    lang = primary_language.downcase

    # Dynamically add mixins
    if lang == 'ruby'
      self.extend(RubyLogFileAnalyzer)
    elsif lang == 'java'
      self.extend(JavaLogFileAnalyzerDispatcher)
    end
  end

  # Template method pattern. Sub classes implement their own analyses in custom_analyze
  def analyze
    anaylze_status
    analyzeSetupTimeBeforeBuild
    custom_analyze
    pre_output
    sanitize_output
  end

  # Intentionally left empty. Mixins should define this method for their customized build process
  def custom_analyze
  end

  # Intentionally left empty. Mixins should define their initialization in this method.
  def init
  end

  def get_build_info(file)
    @build_number, @build_id, @commit, @job_id = File.basename(file, '.log').split('_')
  end

  # Analyze the buildlog exit status
  def anaylze_status
    unless (@folds[@OUT_OF_FOLD].content.last =~/^Done: Job Cancelled/).nil?
      @status = 'cancelled'
    end
    unless (@folds[@OUT_OF_FOLD].content.last =~/^Done. Your build exited with (\d*)\./).nil?
      @status = $1.to_i === 0 ? 'ok' : 'broken'
    end

  end

  # Analyze what the primary language of this build is
  def analyze_primary_language
    system_info = 'system_info'
    if !@folds[system_info].nil?
      @folds[system_info].content.each do |line|
        unless (line =~/^Build language: (.*)/).nil?
          @primary_language = $1
          return
        end
      end
    else
      # in case folding does not work, make educated guess at language
      if @logFile.scan(/java/m).size >= 3
        @primary_language = 'java'
      elsif @logFile.scan(/ruby/m).size >= 3
        @primary_language = 'ruby'
      end
    end
  end

  # Split buildlog into different Folds
  def split
    currentFold = @OUT_OF_FOLD
    @logFileLines.each do |line|
      line = line.uncolorize

      if !(line =~ /travis_fold:start:([\w\.]*)/).nil?
        currentFold = $1
        next
      end

      if !(line =~ /travis_fold:end:([\w\.]*)/).nil?
        currentFold = @OUT_OF_FOLD
        next
      end

      if @folds[currentFold].nil?
        @folds[currentFold] = TravisFold.new(currentFold)
      end

      if !(line =~ /travis_time:.*?,duration=(\d*)/).nil?
        @folds[currentFold].duration = ($1.to_f/1000/1000/1000).round # to convert to seconds
        next
      end

      @folds[currentFold].content << line
    end
  end

  def analyzeSetupTimeBeforeBuild
    @folds.each do |foldname, fold|
      if !(fold.fold =~ /(system_info|git.checkout|services|before.install)/).nil?
        @setup_time_before_build = 0 if @setup_time_before_build.nil? and !fold.duration.nil?
        @setup_time_before_build += fold.duration if !fold.duration.nil?
      end
    end
  end

  def add_framework framework
    @frameworks << framework unless @frameworks.include? framework
  end

  # pre-init values so we can sum-up in case of aggregated test sessions (always use calc_ok_tests when you use this)
  def init_tests
    unless @init_tests
      @test_duration = 0
      @num_tests_run = 0
      @num_tests_failed = 0
      @num_tests_ok = 0
      @num_tests_skipped = 0
      @init_tests = true
    end
  end

  # For non-aggregated reporting, at the end (always use this when you use init_tests)
  def uninit_ok_tests
    if (!@num_tests_run.nil? && !@num_tests_failed.nil?)
      @num_tests_ok += @num_tests_run - @num_tests_failed
    end
  end

  # Mixins should define this method for their customized build process
  def tests_failed?
    return nil
  end

  # Returns a HashMap of results from the analysis
  def output
    {
        # [doc] The build id of the travis build
        :tr_build_id => @build_id,
        # [doc] The job id of the build job under analysis
        :tr_job_id => @job_id,
        # [doc] The serial build number of the build under analysis for this project
        :tr_build_number => @build_number,
        # [doc] The SHA of the original Travis commit, unparsed and unchanged
        :tr_original_commit => @commit,
        # [doc] The primary programming language, extracted by build log analysis
        :tr_log_lan => @primary_language,
        # [doc] The overall return status of the build, extracted by build log analysis
        :tr_log_status => @status,
        # [doc] The setup time before the script phase (the actual build) starts, in seconds, extracted by build log analysis
        :tr_log_setup_time => @setup_time_before_build,
        # [doc] The build log analyzer that was invoked for analysis of this build
        :tr_log_analyzer => @analyzer,
        # [doc] The testing frameworks ran extracted by build log analysis
        :tr_log_frameworks => @frameworks.join('#'),
        # [doc] Whether tests were run, extracted by build log analysis
        :tr_log_bool_tests_ran => @tests_run,
        # [doc] Whether tests failed, extracted by build log analysis
        :tr_log_bool_tests_failed => @did_tests_fail,
        # [doc] Number of tests that succeeded, extracted by build log analysis
        :tr_log_num_tests_ok => @num_tests_ok,
        # [doc] Number of tests that failed, extracted by build log analysis
        :tr_log_num_tests_failed => @num_tests_failed,
        # [doc] Number of tests that ran in total, extracted by build log analysis
        :tr_log_num_tests_run => @num_tests_run,
        # [doc] Number of tests that were skipped, extracted by build log analysis
        :tr_log_num_tests_skipped => @num_tests_skipped,
        # [doc] Names of the tests that failed, extracted by build log analysis
        :tr_log_tests_failed => @tests_failed.join('#'),
        # [doc] Duration of the running the tests, in seconds, extracted by build log analysis
        :tr_log_testduration =>  @test_duration,
        # [doc] Duration of running the build command like maven or ant (if present, should be longer than :tr_log_testduration as it includes this phase), in seconds, extracted by build log analysis
        :tr_log_buildduration => @pure_build_duration
    }
  end

  # Assign function values to variables before outputting
  def pre_output
    @did_tests_fail = tests_failed?
  end

  # Perform last-second sanitaztion of variables. Can be used to guarantee invariants.
  # TODO (MMB) Implement some of the R checks here?
  def sanitize_output
    @did_tests_fail = nil if !@tests_run

    if !@pure_build_duration.nil? and !@test_duration.nil?

      if @pure_build_duration < @test_duration
        @pure_build_duration = nil
      end
    end
  end

end
