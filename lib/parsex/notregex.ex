defmodule Parsex.NotRegex do
  @moduledoc """
  This is a basic implementation of regex
  """

  import Parsex.Utils

  def check_escaped_reverse(ele, {escaped, result}) do
    case {escaped, ele} do
      {true, _} -> {false, [{:esc, ele} | result]}
      {false, "\\"} -> { true, result }
      {false, _} -> { false, [ele | result] }
    end
  end

  def check_escape(c) do
    case c do
      "n" -> "\n"
      any -> any
    end
  end

  # Everything is built reversed, for efficiency, we need to manually reverse this after 
  def build_regex_reverse(ele, {stack, charset?, chars, negate_charset}) do
    case {charset?, ele} do 
      {:out, "["} ->
        {stack, :in, [], false}
      {:in, {:esc, c}} -> 
        {stack, :in, [check_escape(c) | chars], negate_charset}
      {:in, "^"} -> 
        {stack, :in, chars, true}
      {:in, "]"} -> 
        stack = 
          if negate_charset do
            [{:not_chars, chars} | stack]
          else
            [[:alt | chars] | stack]
          end
        {stack, :out, [], false}
      {:in, "-"} -> 
        {stack, :range, chars, negate_charset}
      {:in, c} -> 
        {stack, :in, [c | chars], negate_charset}
      {:range, c} -> 
        c =  check_escape(c) 
        {[<<from, "">> | _], <<to, "">>} = {chars, c}
        chars = Enum.map(from+1..to, &<<&1>>) ++ chars
        {stack, :in, chars, negate_charset}
      {:out, {:esc, "s"}} -> 
        spaces = [" ", "\n", "\r", "\t", "\f"]
        stack = [[:alt | spaces] | stack]
        {stack, :out, [], false}
      {:out, {:esc, "S"}} -> 
        spaces = [" ", "\n", "\r", "\t", "\f"]
        stack = [{:not_chars, spaces} | stack]
        {stack, :out, [], false}
      {:out, {:esc, c}} -> 
        c = check_escape(c)
        case stack do
          [s | rest] when is_binary(s) ->
            {[c <> s | rest], :out, [], false}
          _ -> 
            {[c | stack], :out, [], false}
        end
      {:out, "."} -> 
        stack = [{:not_chars, ["\n"]} | stack]
        {stack, :out, [], false}
      {:out, "*"} -> 
        [top | rest] = stack
        stack = [[:kleen_closure, top] | rest]
        {stack, :out, [], false}
      {:out, "+"} ->
        [top | rest] = stack
        stack = [[:add_closure, top] | rest]
        {stack, :out, [], false}
      {:out, "?"} ->
        [top | rest] = stack
        stack = [[:optional, top] | rest]
        {stack, :out, [], false}
      {:out, "|"} ->
        {branch, stack} = 
          stack 
          |> Enum.split_while(fn ele -> ele != :lparen and ele != :alt end)
        stack = [:alt, [:seq | branch] | stack]
        {stack, :out, [], false}
      {:out, "("} ->
        {[:lparen | stack], :out, [], false}
      {:out, ")"} ->
        # First emulate a "|"
        {branch, stack} = 
          stack 
          |> Enum.split_while(fn ele -> ele != :lparen and ele != :alt end)
        stack = [:alt, [:seq | branch] | stack]
        {stack, :out, [], false}
        # Then merge all branch into seq
        {to_merge, [:lparen | stack]} = 
          stack
          |> Enum.split_while(fn e -> e != :lparen end)
        to_merge = 
          to_merge
          |> Enum.drop_every(2) 
        stack = [[:alt | to_merge] | stack]
        {stack, :out, [], false}
      {:out, c} -> 
        case stack do
          [s | rest] when is_binary(s) ->
            {[c <> s | rest], :out, [], false}
          _ -> 
            {[c | stack], :out, [], false}
        end
    end
  end

  def flip_node(node) do
    ret = case node do  
      [op | rest] -> [op | Enum.reverse(rest)]
      str when is_binary(str) -> String.reverse(str)
      any -> any
    end
    ret
  end

  # We didn't tag every string in the build phase, do it in a separate phase
  # so it's easier
  def tag_str(node) do
    ret = if is_binary(node) do 
      {:str, node}
    else
      node
    end
  end

  def expand_regex(regex) do
    regex 
    |> String.codepoints()
    |> Enum.reduce({false, []}, &check_escaped_reverse/2)
    |> then(fn {false, unescaped_chars} -> unescaped_chars end)
    |> Enum.reverse()
    |> then(&["(" | &1 ++ [")"]]) # Wrap input with braces so it's easier to parse
    |> Enum.reduce({[], :out, [], false}, &build_regex_reverse/2)
    |> then(fn {[built], :out, [], false} -> built end)
    |> then(fn built -> tree_map(built, (&tag_str/1) <~> (&flip_node/1)) end)
  end
end
