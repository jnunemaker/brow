require "test_helper"

class BrowResponseTest < Minitest::Test
  def test_status
    response = Brow::Response.new
    assert_equal 200, response.status
  end

  def test_error
    response = Brow::Response.new
    assert_nil response.error
  end

  def test_initialize
    response = Brow::Response.new(404, "what? where?")
    assert_equal 404, response.status
    assert_equal "what? where?", response.error
  end
end
