defmodule Parsex.StateBuilder do

  import Parsex.Utils

  defmodule LALR1Item do
    # star_pos == 0 => we are at the begining of this alternative
    # star_pos == length_of_this_alternative => we are at the end of this alternative
    @enforce_keys [:lhs, :alt_id, :star_pos]
    defstruct [:lhs, :alt_id, :star_pos, :lookahead]
  end

  def get_fixpoint(x_in, f, equal_fn \\ &(&1 == &2)) do
    x_out = f.(x_in)
    if equal_fn.(x_in, x_out) do 
      x_in
    else
      get_fixpoint(x_out, f, equal_fn)
    end
  end

  def rhs_nilable_seq([:seq, rest], nilables_already) do
    rest |> Enum.all?(&Enum.member?(nilables_already, &1))
  end
  def term_nilable(term, ruleset, nilables_already) do
    # if Map.has_key?(term) do
    case Map.fetch(ruleset, term) do 
      {:ok, [:alt, alts]} ->
        alts |> Enum.any?(&rhs_nilable_seq(&1, nilables_already))
      _ -> # This must be a non-nil literal as we put `nil` in the set in the begining
        false 
    end
  end

  # non-recursive
  def nilable_propagate(ruleset, nilables_already) do
    new_nilables = 
      ruleset 
      |> Map.keys()
      |> Stream.reject(&Enum.member?(nilables_already, &1))
      |> Stream.filter(&term_nilable(&1, ruleset, nilables_already))
      |> MapSet.new()
      |> MapSet.union(nilables_already)
  end

  def get_nilables(ruleset) do
    get_fixpoint(MapSet.new([nil]), &nilable_propagate(ruleset, &1))
  end

  # contains duplicate, non-recursive
  def term_closure_propagate(term, ruleset) do
    # Here we don't need to differentiate nil case from other case because 
    # either way we can't add new items
    [:alt | alts] = Map.get(ruleset, term)
    0..Enum.count(alts)-1 
    |> Stream.map(&%LALR1Item{lhs: term, alt_id: &1, star_pos: 0})
  end

  # contains duplicate, non-recursive
  def sequence_closure_propagate(seq, ruleset, nilables) do
    seq 
    |> Stream.take_while(&Enum.member?(nilables, &1))
    |> Stream.flat_map(&term_closure_propagate(&1, ruleset))
  end

  def item_to_alt(%LALR1Item{lhs: lhs, alt_id: alt_id}, ruleset) do
    [:alt | rest] = Map.fetch!(ruleset, lhs)
    Enum.at(rest, alt_id)
  end

  def item_to_alt_rest(item = %LALR1Item{star_pos: star_pos}, ruleset) do
    # this will be empty if we already are at the end 
    item_to_alt(item, ruleset) |> Stream.drop(star_pos)
  end

  # contains duplicate, non-recursive
  def item_closure_propagate(item, ruleset, nilables) do
    item_to_alt_rest(item, ruleset)
    |> sequence_closure_propagate(ruleset, nilables)
  end

  # contains no duplicate, non-recursive
  def items_closure_propagate(items, ruleset, nilables) do
    items
    |> Stream.flat_map(&item_closure_propagate(&1, ruleset, nilables))
    |> MapSet.new()
    |> MapSet.union(items)
  end

  defmodule State do
    @enforce_keys [:kernel_items, :closure_items]
    defstruct [:kernel_items, :closure_items]

    def new(kernel, ruleset, nilables) do
      closure_items = 
        Parsex.StateBuilder.get_fixpoint(
          kernel, 
          &Paresex.StateBuilder.item_closure_propagate(&1, ruleset, nilables))
      %State{kernel_items: kernel, closure_items: closure_items}
    end
  end

  # defmodule LALR1Item do
  #   # star_pos == 0 => we are at the begining of this alternative
  #   # star_pos == length_of_this_alternative => we are at the end of this alternative
  #   @enforce_keys [:lhs, :alt_id, :star_pos]
  #   defstruct [:lhs, :alt_id, :star_pos, :lookahead]
  # end

  def goto_state_propagate(
    {ker, {:new, %State{kernel_items: ker, closure_items: closure }, id}, }, 
    {counter, state_map, transition_graph, ruleset}) do

    first_term_after_dot = fn item ->
      [next | _] = item_to_alt_rest(item)
      next
    end

    advance_dot = fn item = %LALR1Item{star_pos: star_pos} ->
      {item | star_pos: star_pos + 1}
    end

    insert_state = fn {{term, transition_to}, {counter, state_map, transition_graph}} -> 

      # state_map = %{start_kernel => {:new, initial_state, counter}}
      case Map.get(state_map, transition_to) do
        nil -> 
          
          {counter + 1,}
        any -> 
          #counter = counter + 1

          {counter, state_map, transition_graph}
      end
    end

    {counter, state_map, transition_graph} = 
      closure
      |> Stream.reject(&(item_to_alt_rest(&1) == []))
      |> Enum.group_by(first_term_after_dot, advance_dot)
      |> Enum.reduce({counter, state_map, transition_graph}, insert_state)

    {new_states, {counter, transition_graph, ruleset}}
  end

  # State map is a map from kernel to {:old/:new, State, state_id}
  # NOTE: We can optimize this by splicting up state_map to new_state_map and 
  # old_state_map, but we'd better do this when refactoring
  def goto_graph_propagate({counter, state_map, transition_graph, ruleset}) do
    {new_states, old_states} = 
      state_map
      |> Enum.split_with(fn {k, v} -> 
          case v do 
            {:new, _, _} -> true 
            _ -> false
          end
        end)

    old_states = 
      new_states 
      # Mark state as old.
      |> Enum.map(fn {ker, {:new, state, id}} -> {ker, {:old, state, id}} end) 
      # Merge with original old state
      |> Map.merge(old_states)
    {new_states, {counter, transition_graph, _, _}} =
      new_states
      |> Stream.flat_map_reduce({counter, transition_graph, ruleset, nilables}, &goto_state_propagate/2)
    {counter, Map.merge(new_states, old_states), transition_graph}
  end

  def get_goto_graph(ruleset, nilables) do
    start_kernel = MapSet.new([ %LALR1Item{lhs: ~m(start), alt_id: 0, star_pos: 0} ])
    initial_state = State.new(start_kernel, ruleset, nilables)
    counter = 0
    state_map = %{start_kernel => {:new, initial_state, counter}}
    transition_graph = Graph.new() |> Graph.add_vertex(counter)
    # we don't want to repeat the work on checking ruleset & nilables repeatedly
    state_eq = fn ({c1, s1, t1, _, _}, {c2, s2, t2, _, _}) ->
      {c1, s1, t1} == {c2, s2, t2}
    end
    get_fixpoint(&goto_graph_propagate/1, {counter, state_map, transition_graph, ruleset, nilables}, state_eq)
  end

  def state(ruleset) do
    nilables = get_nilables(ruleset)
    goto = get_goto_graph(ruleset, nilables)
  end

end
