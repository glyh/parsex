defmodule Parsex.RulesetBuilder do

  import Parsex.Utils


  @doc"""
  Given a nestesd structure, flatten out the homogenious part.
  For example, [:seq, :a, [:seq, :b, [:alt, [:seq, :g], :h]], [:seq, :d, :e]] 
  will be flatten to [:seq, :a, :b, [:alt, :g, :h], :d, :e]
  `what`
  """
  def flatten_what(what) do
    collect = fn exp -> 
      case exp do 
        [^what | rest] -> rest
        any -> [any]
      end
    end
    fn node -> 
      case node do 
        [^what | whats] -> 
          new_whats = whats |> Enum.flat_map(collect)
          case new_whats do 
            [only] -> only
            _ -> [what | new_whats]
          end
        any -> any
      end
    end
  end

  def desugar_rhs([:add_closure, inner], {counter, ruleset, is_token, root_lhs}) do
    lhs = {:generated, counter, is_token}
    rhs = [:alt, inner, [:seq, inner, lhs]]
    ruleset = Map.put(ruleset, lhs, rhs)
    # node to replace, new state
    {lhs,              {counter + 1, ruleset, is_token, root_lhs}}
  end

  def desugar_rhs([:kleen_closure, inner], {counter, ruleset, is_token, root_lhs}) do
    lhs = {:generated, counter, is_token}
    rhs = [:alt, nil, [:seq, inner, lhs]]
    ruleset = Map.put(ruleset, lhs, rhs)
    {lhs, {counter + 1, ruleset, is_token, root_lhs}}
  end

  def desugar_rhs([:optional, inner], {counter, ruleset, is_token, root_lhs}) do
    lhs = {:generated, counter, is_token}
    rhs = [:alt, nil, inner]
    ruleset = Map.put(ruleset, lhs, rhs)
    {lhs, {counter + 1, ruleset, is_token, root_lhs}}
  end

  def desugar_rhs([:alias, inner, {name}], {counter, ruleset, is_token, root_lhs}) do
    # the 4th param is used to mark if the alias is a root alias
    # if it's nil it means the alias is not a root alias
    # o.w. it means it's an alias of some rule :gamma if lhs = {:alias, _, _, :gamma}
    # We temporarily specify it to be a root alias, we may delete it in the next walk
    lhs = {:alias, name, is_token, root_lhs}
    rhs = inner
    ruleset = Map.put(ruleset, lhs, rhs)
    {lhs, {counter, ruleset, is_token, root_lhs}}
  end

  def desugar_rhs([:alias, inner, {:meta, "regex"}], {counter, ruleset, is_token, root_lhs}) do
    # This is the special case for regex, because we don't want any whitespaces to be inserted into the regex.
    lhs = {:alias, counter, true, ~m(regex)}
    rhs = inner
    ruleset = Map.put(ruleset, lhs, rhs)
    {lhs, {counter + 1, ruleset, is_token, root_lhs}}
  end


  def desugar_rhs([:alt | alts], {counter, ruleset, is_token, root_lhs}) do
    lhs = {:generated, counter, is_token}
    rhs = [:alt | alts]
    ruleset = Map.put(ruleset, lhs, rhs)
    {lhs, {counter + 1, ruleset, is_token, root_lhs}}
  end

  def desugar_rhs(any, state) do
    {any, state} 
  end

  def desugar({lhs, rhs}, {counter, ruleset}) do
    generated_tag = if is_token(lhs) do :token else :non_token end
    {rhs, {counter, ruleset, generated_tag, ^lhs}} = 
      tree_map_reduce(rhs, &desugar_rhs/2, {counter, ruleset, generated_tag, lhs})
    ruleset = Map.put(ruleset, lhs, rhs)
    {counter, ruleset}
  end

  def is_token(nonterminal) do
    case nonterminal do
      {:generated, counter, :token} -> true
      a when is_atom(a) ->
        s = Atom.to_string(a)
        s == String.upcase(s)
      _ -> false
    end
  end

  def apply_ignore({lhs, rhs}) do
    downcase? = fn str ->
    end
    if lhs == ~m(root) or not is_token(lhs) do
      intersperse_with_around = fn l, sep -> 
        [ sep | l |> Enum.intersperse(sep)] ++ [sep]
      end
      m_root = ~m(root)
      intersperser = case lhs do
          ^m_root -> intersperse_with_around
          _ -> &Enum.intersperse/2
      end
      add_ignore_to_seq = fn seq ->
        case seq do 
          [:seq | rest] -> [:seq | intersperser.(rest, ~m(ignore))]
          any -> any
        end
      end
      rhs = case rhs do
        [:alt | alts] -> [:alt | alts |> Enum.map(add_ignore_to_seq)]
        any -> add_ignore_to_seq.(any)
      end
      {lhs, rhs}
    else
      {lhs, rhs}
    end
  end
  
  def clear_redundant_rules({lhs, rhs}, {generated, non_generated}) do
    case rhs do
      {:generated, _, _} -> 
        {new_rhs, generated} = Map.pop!(generated, rhs)
        clear_redundant_rules({lhs, new_rhs}, {generated, non_generated})
      _ -> 
        non_generated = Map.put(non_generated, lhs, rhs)
        {generated, non_generated}
    end
  end

  # # is it a root alias for a rule?
  # def is_root_alias({:alias, name, :non_token, _}, ruleset) do 
  # end
  # def is_root_alias({:alias, _, _, _}, _) do 
  #   false 
  # end

  # lhs = {:alias, name, is_token, root_lhs}
  def mark_aliases_type({lhs, rhs}, ruleset) do
    alias_relation = fn (alias_lhs, root_rhs) ->
      {:alias, name, _, _} = alias_lhs
      case root_rhs do
        [:alt | alts] ->  
          if Enum.member?(alts, alias_lhs) do
            :alt
          else
            :none
          end
        {:alias, ^name, _, _} -> :alt
        _ -> :none
      end
    end
    case lhs do
      {:alias, name, token?, root_lhs} -> 
        root_rhs = 
          if root_lhs == ~m(regex) do 
            nil
          else
            Map.fetch!(ruleset, root_lhs)
          end
        case alias_relation.(lhs, root_rhs) do
          :alt -> ruleset
          :none -> 
            {^rhs, ruleset} = Map.pop!(lhs)
            Map.put({:alias, name, token?, nil}, rhs)
        end
      _ -> ruleset
    end
  end

  def ensure_wrapped_with_seq({term, rule}) do
    rule = case rule do
      [:alt, _] -> rule
      _ -> [:alt, rule]
    end
    {term, rule}
  end

  def build(ruleset) do
    flatten_alt = flatten_what(:alt)
    flatten_seq = flatten_what(:seq)
    flatten = &tree_map(&1, flatten_alt <~> flatten_seq) 

    {_, ruleset} = 
      ruleset 
      |> Stream.map(fn {lhs, rhs} -> 
          {lhs, flatten.(rhs)} 
        end) 
      # |> Enum.into(%{}) |> dump("FLATTENED:")
      |> Enum.reduce({0, %{}}, &desugar/2)
      # |> dump("DESUGARED:")

    ruleset = if Map.has_key?(ruleset, ~m(ignore)) do
      ruleset
      |> Stream.map(&apply_ignore/1)
      |> Enum.into(%{})
      #|> dump("IGNORED WHITESPACE:")
    else
      ruleset
    end

    # Map.split_with is introduced in 1.15 so we use something else similar
    split_with = fn (map, cond) ->
      {l, r} = 
        map 
        |> Stream.into([])
        |> Enum.split_with(cond)
      {Enum.into(l, %{}), Enum.into(r, %{})}
    end

    {ruleset_generated, ruleset_non_generated} =
      ruleset
      |> split_with.(fn {k, _} ->
        case k do
          {:generated, _, _} -> true
          _ -> false
        end
      end)
    {ruleset_generated, ruleset_non_generated} = 
      ruleset_non_generated
      |> Enum.reduce({ruleset_generated, ruleset_non_generated}, &clear_redundant_rules/2)
    ruleset = 
      Map.merge(ruleset_non_generated, ruleset_generated)
      #|> dump("CLEAR_REDUNDANT_RULES:")
    ruleset = ruleset
      |> Enum.reduce(ruleset, &mark_aliases_type/2)
      |> Map.put(~m(start), ~m(root))
      |> Stream.map(&ensure_wrapped_with_seq/1)
      |> Enum.into(%{})
      # |> dump("!!!!MARK ALIAS TYPE")
      |> dump("FINAL RULESET:")
  end

end
