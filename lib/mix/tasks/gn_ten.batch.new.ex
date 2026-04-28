defmodule Mix.Tasks.GnTen.Batch.New do
  @moduledoc "Creates a gn-ten batch receipt scaffold."

  use Mix.Task

  alias StackLab.GnTen.BatchReceipt

  @shortdoc "Creates a gn-ten batch receipt scaffold"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [name: :string, repo: :string, out: :string, force: :boolean]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    opts
    |> Keyword.fetch(:name)
    |> create_receipt(opts)
  end

  defp create_receipt(:error, _opts), do: Mix.raise("expected --name <slug>")

  defp create_receipt({:ok, name}, opts) do
    receipt_opts =
      [
        repo: Keyword.get(opts, :repo, "stack_lab"),
        out_dir: Keyword.get(opts, :out, BatchReceipt.default_out_dir()),
        force?: Keyword.get(opts, :force, false)
      ]

    case BatchReceipt.new(name, receipt_opts) do
      {:ok, receipt} ->
        Mix.shell().info("gn_ten.batch.new created")
        Mix.shell().info("batch_id=#{receipt.batch_id}")
        Mix.shell().info("markdown=#{receipt.md_path}")
        Mix.shell().info("json=#{receipt.json_path}")

      {:error, reason} ->
        Mix.raise("gn_ten.batch.new failed: #{inspect(reason)}")
    end
  end
end
