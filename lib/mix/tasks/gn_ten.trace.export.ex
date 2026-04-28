defmodule Mix.Tasks.GnTen.Trace.Export do
  @moduledoc "Exports deterministic gn-ten proof trace fixtures."

  use Mix.Task

  alias StackLab.GnTen.TraceFixtures

  @shortdoc "Exports a gn-ten proof trace fixture"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args, strict: [profile: :string, out: :string])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    profile = Keyword.get(opts, :profile) || Mix.raise("expected --profile <name>")
    out = Keyword.get(opts, :out) || Mix.raise("expected --out <path>")

    trace = TraceFixtures.build!(profile)

    case TraceFixtures.validate_export(trace) do
      :ok ->
        File.mkdir_p!(Path.dirname(out))
        File.write!(out, Jason.encode!(trace, pretty: true))
        Mix.shell().info("gn_ten.trace.export wrote #{out}")

      {:error, failures} ->
        Mix.raise("trace export failed: #{inspect(failures)}")
    end
  end
end
