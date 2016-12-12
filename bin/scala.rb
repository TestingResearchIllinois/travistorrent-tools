#
# (c) 2012 -- 2015 Georgios Gousios <gousiosg@gmail.com>
#

require_relative 'comment_stripper'

module ScalaData

  include CommentStripper

  def src_file_filter
    lambda { |f|
      path = if f.class == Hash then f[:path] else f end
      not path.include?('/test/') and
          (path.end_with?('.java') or path.end_with?('.scala'))
    }
  end

  def test_file_filter
    lambda { |f|
      path = if f.class == Hash then f[:path] else f end
      path.include?('/test/') and
        (path.end_with?('.java') or path.end_with?('.scala'))
    }
  end

  def test_case_filter
    lambda{|l|
      not l.match(/@Test/).nil? or           # JUnit
          not l.match(/ in\s*{/).nil? or     # specs2
          not l.match(/ it[\s({]+"/).nil? or # scalatest bdd tests
          not l.match(/ test[\s({]+"/).nil?  # scalatest unit tests
    }
  end

  def assertion_filter
    lambda{ |l|
      not l.match(/[.\s]assert[\s({]+/).nil? or          # JUnit, scalatest
          not l.match(/[.\s]must[\s({]+/).nil? or        # scalatest
          not l.match(/[.\s]should[\s({]+/).nil? or      # scalatest, specs2
          not l.match(/[.\s]shouldBe[\s({]+/).nil?       # scalacheck
    }
  end

  def strip_comments(buff)
    strip_c_style_comments(buff)
  end

end
