defmodule DSLTest do
  use ExUnit.Case
  doctest Parsex

  test "DSL" do
    require Parsex.DSL
    alias Parsex.DSL
    
    parser = DSL.create do
      @root <- {class} .. {function}
      class 
        <- "class" .. ID .. "{" .. "capability" .. {capability} .. {field} .. {method} .. "}" 
        |  "class" .. ID .. "<" .. T .. ">" .. "{" .. "capability" .. {capability} .. {field} .. {method} .. "}" 
           = generic_class
      capability <- "capability" .. +(mode .. ID) .. ";" 
      mode <- "linear" | "subordinate" | "thread" | "read" | "locked"
      field <- modifier .. type .. ID .. ":" .. +ID .. ";"
      param <- type .. ["{" .. +ID .. "}"] .. ID

      # TODO: Implement macro expansion  
      # @list(elem, sep) <- nil | elem .. {^sep .. elem}

      # @ignore <- {INLINE_COMMENT | MULTILINE_COMMENT | WHITESPACE}
      # INLINE_COMMENT <- ~r{//[^\n]+}
      # MULTILINE_COMMENT <- "/*" .. ({~r{[^*/]|\*[^/]|/[^*]}} | MULTILINE_COMMENT) .. "*/"
      # WHITESPACE <- ~r{\s}
    end
    IO.puts "#{inspect parser}"
  end
end
