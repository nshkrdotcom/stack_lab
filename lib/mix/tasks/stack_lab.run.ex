defmodule Mix.Tasks.StackLab.Run do
  @moduledoc "Runs StackLab proof-tag commands."

  use Mix.Task

  @shortdoc "Run StackLab proof tag command"

  @impl true
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [tag: :string, json: :boolean])
    tag = Keyword.get(opts, :tag, tag(args))

    case StackLab.ChassisBridge.run(normalize_tag(tag)) do
      {:ok, report} ->
        emit(report, Keyword.get(opts, :json, false))

      {:error, reason} ->
        Mix.raise("stack_lab.run failed: #{inspect(reason)}")
    end
  end

  defp tag(["--tag", tag | _args]), do: tag
  defp tag([tag | _args]), do: tag
  defp tag([]), do: "all"

  defp normalize_tag("chassis"), do: :chassis
  defp normalize_tag(tag), do: tag

  defp emit(report, true) do
    report
    |> StackLab.ChassisBridge.jsonable_report()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp emit(report, false) do
    Enum.each(report.proofs, fn proof ->
      Mix.shell().info("#{proof.name}: #{String.upcase(to_string(proof.status))}")
    end)
  end
end
