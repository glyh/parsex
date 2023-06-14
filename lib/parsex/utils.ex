defmodule Parsex.Utils do
  def tree_map(tree, f) do 
    tree = case tree do
      [op | rest] -> 
        [op | Enum.map(rest, &tree_map(&1, f))]
      any -> any
    end
    f.(tree)
  end

  # f: (node, state) -> {node_new, state_new}
  # yields: {node_new, state_new}
  def tree_map_reduce(tree, f, acc) do
    #IO.puts "FROM #{inspect tree}"
    {tree, acc} = case tree do 
      [op | rest] -> 
        {rest, acc} = Enum.map_reduce(rest, acc, fn (child, acc) -> 
          {child, state_new} = tree_map_reduce(child, f, acc)
        end)
        {[op | rest], acc}
      any -> {any, acc}
    end
    #tree |> dump("YES")
    ret = f.(tree, acc)
    #|> dump("TO:")
  end

  def f <~> g when is_function(f, 1) and is_function(g, 1) do
    fn x -> f.(g.(x)) end
  end

  # defmacro a <~ b do
  #   quote do
  #     case unquote(a) do
  #       ^unquote(b) -> true
  #       _ -> false
  #     end
  #   end
  # end

  def dump(what, label) do 
    IO.puts "#{label} #{inspect(what)}"
    what
  end

  def sigil_m(meta, []), do: {:meta, String.to_atom(meta)}
end
