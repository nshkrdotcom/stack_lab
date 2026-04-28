defmodule Mix.Tasks.GnTen.Plan do
  @moduledoc "Prints a bounded gn-ten plan for one repo."

  use Mix.Task

  alias StackLab.GnTen.Plan

  @shortdoc "Prints a bounded gn-ten repo plan"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [repo: :string, json: :boolean],
        aliases: [r: :repo]
      )

    repo = Keyword.get(opts, :repo)

    cond do
      invalid != [] ->
        Mix.raise("invalid options: #{inspect(invalid)}")

      is_nil(repo) ->
        Mix.raise("expected --repo <name>")

      true ->
        print(repo, Keyword.get(opts, :json, false))
    end
  end

  defp print(repo, json?) do
    case Plan.for_repo(repo, json?: json?) do
      {:ok, plan} when json? ->
        plan
        |> Jason.encode!(pretty: true)
        |> Mix.shell().info()

      {:ok, text} ->
        Mix.shell().info(text)

      {:error, {:unknown_repo, name}} ->
        Mix.raise("unknown gn-ten repo: #{name}")

      {:error, reason} ->
        Mix.raise("unable to build gn-ten plan: #{inspect(reason)}")
    end
  end
end
