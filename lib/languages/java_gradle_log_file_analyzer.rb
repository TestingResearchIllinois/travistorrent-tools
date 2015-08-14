require 'json'

class JavaGradleLogFileAnalyzer < LogFileAnalyzer
  attr_reader :tests_failed, :test_duration, :reactor_lines, :pure_build_duration

  @test_failed_lines

  @test_failed

  def initialize(file)
    super(file)
    @tests_failed_lines = Array.new
    @tests_failed = Array.new
    @num_tests_failed = 0

    @test_failed = false
  end

  def analyze
    super

    extract_tests
    analyze_tests
    getOffendingTests
  end

  def print_tests_failed
    tests_failed.join(';')
  end

  def output
    keys = ['broke_build', 'ok', 'failed', 'run', 'skipped', 'tests', 'testduration', 'purebuildduration']
    values = [tests_broke_build?, @num_tests_ok, @num_tests_failed, @num_tests_run, @num_tests_skipped,
              print_tests_failed, @test_duration, @pure_build_duration]
    flattened_values = keys.zip(values).flat_map {|k,v| "#{k}:#{v}"}.join(',')
    super + ',' + flattened_values
  end

  def extract_tests
    test_section_started = false
    line_marker = 0
    current_section = ''

    @folds[OUT_OF_FOLD].content.each do |line|
      if !(line =~ /\A:(test|integrationTest)/).nil?
        line_marker = 1
        test_section_started = true
        @tests_run = true
      elsif !(line =~ /\A:(\w*)/).nil? && line_marker == 1
        line_marker = 0
        test_section_started = false
      end

      if test_section_started
        @test_lines << line
      end
    end
  end

  def convert_maven_time_to_seconds(string)
    if !(string =~ /(\d+)(\.\d*)? s/).nil?
      return $1.to_i
    elsif !(string =~ /(\d+):(\d+) min/).nil?
      return $1.to_i * 60 + $2.to_i
    end
  end

  def extractTestNameAndMethod(string)
    string.split(' > ').map { |t| t.split }
  end

  def analyze_tests
    failed_tests_started = false

    @test_lines.each do |line|
      if !(line =~ /.* > .* FAILED/).nil?
        @tests_failed_lines << line
        @test_failed = true
      end

      if !(line =~ /(\d*) tests completed, (\d*) failed, (\d*) skipped/).nil?
        @tests_run = true
        @num_tests_run = $1.to_i
        @num_tests_failed = $2.to_i
        @num_tests_ok = @num_tests_run.to_i - @num_tests_failed.to_i
        @num_tests_skipped = $3.to_i
      end
    end
  end

  def getOffendingTests
    @tests_failed_lines.each { |l| @tests_failed << extractTestNameAndMethod(l)[0] }
  end

  def tests_broke_build?
    return @num_tests_failed > 0 || !@tests_failed.empty? || @test_failed
  end
end