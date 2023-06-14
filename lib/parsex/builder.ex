defmodule Parsex.Builder do

  def build(ruleset) do
    Parsex.RulesetBuilder.build(ruleset)
    |> Parsex.StateBuilder.build()
  end

end
