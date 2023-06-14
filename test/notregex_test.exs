defmodule NotRegexTest do
  use ExUnit.Case
  doctest Parsex.NotRegex

  test "Expand Regex" do 
    alias Parsex.NotRegex
    regex_expanded = NotRegex.expand_regex(~s/[a-z]+..(ni|u?bi)*/)
    IO.puts "#{inspect(regex_expanded)}"
    assert true
  end
end
