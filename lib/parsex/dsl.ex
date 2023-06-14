defmodule Parsex.DSL do
  @moduledoc """
  Documentation for `Parsex`.
  """

  import Parsex.Utils

  def parse_exp({:.., _, [lhs, rhs]}) do
    [:seq, parse_exp(lhs), parse_exp(rhs)]
  end
  def parse_exp({:|, _, [lhs, rhs]}) do
    [:alt, parse_exp(lhs), parse_exp(rhs)]
  end
  def parse_exp({:+, _, [inner]}) do
    [:add_closure, parse_exp(inner)]
  end
  def parse_exp({:{}, _, [inner]}) do
    [:kleen_closure, parse_exp(inner)]
  end
  def parse_exp([inner]) do
    [:optional, parse_exp(inner)]
  end

  def parse_exp({:^, _, [inner]}) do
    [:no_capture, parse_exp(inner)]
  end
  def parse_exp({:=, _, [inner, alias]}) do
    # Wrap the 3rd arg with tuple so any tree walker can't touch it
    [:alias, parse_exp(inner), {parse_exp(alias)}]
  end

  def parse_exp({:sigil_r, _, [{:<<>>, _, [pattern]}, _]}) do
    # I'm expanding Regex to CFG here so we can optimize together.
    # Note regex may generate something like {:not_chars, ["a", "b", "c"]}
    # since they need to deal with exclusive-charset
    # WARN: regex will be inserted with whitespace, we need to fix it
    # {:regex, pattern}

    {:alias, Parsex.NotRegex.expand_regex(pattern), ~m(regex)}
  end
  def parse_exp(nil) do 
    nil # Epsilon
  end
  def parse_exp({:@, _, [{macro, _, args}]}) when is_list(args) do
    [:macro, macro | Enum.map(args, &parse_exp/1)]
  end
  def parse_exp({:@, _, [{meta, _, _}]}) do
    {:meta, meta}
  end
  def parse_exp(str) when is_binary(str) do
    {:str, str}
  end

  def parse_rule({:<-, _, [lhs, rhs]}) do
    lhs_parsed = parse_exp(lhs)
    rhs_parsed = parse_exp(rhs)
    {lhs_parsed, rhs_parsed}
  end

  def parse_exp({:__aliases__, _, [nonterminal]}) do
    nonterminal
  end
  def parse_exp({nonterminal, _, _}) do
    nonterminal
  end


  defmacro create(do: block) do  
    {:__block__, [], rules} = block
    parsed_ruleset = 
      rules 
      |> Stream.map(&parse_rule/1)
      |> Enum.into(%{})
      |> Parsex.Builder.build()
      |> Macro.escape()
  end
end
