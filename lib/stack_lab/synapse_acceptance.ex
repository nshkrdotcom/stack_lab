defmodule StackLab.SynapseAcceptance do
  @moduledoc false

  @schema_version "stack_lab.synapse_product_acceptance.v1"
  @example_command ["stack_lab.proof_app.synapse.acceptance"]

  @spec default_example_root() :: String.t()
  def default_example_root do
    Path.expand("../../examples/synapse_product_acceptance", __DIR__)
  end

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.expand("tmp/stack_lab/synapse_acceptance/receipt.json", File.cwd!())
  end

  @spec run(keyword()) :: {:ok, map()} | {:error, map()}
  def run(opts \\ []) do
    example_root = Keyword.get(opts, :example_root, default_example_root())
    receipt_path = Keyword.get(opts, :example_receipt_path, default_example_receipt_path())
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    command = Keyword.get(opts, :mix_executable, mix_executable())
    args = @example_command ++ ["--receipt", receipt_path]

    with :ok <- remove_stale_receipt(receipt_path),
         {output, 0} when is_binary(output) <- runner.(command, args, command_opts(example_root)),
         {:ok, receipt} <- read_receipt(receipt_path),
         :ok <- validate_receipt(receipt) do
      {:ok, Map.put(receipt, "root_command_output", output_excerpt(output))}
    else
      {output, status} when is_binary(output) ->
        {:error,
         error("synapse_acceptance_command_failed",
           exit_status: status,
           output_excerpt: output_excerpt(output)
         )}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, error("synapse_acceptance_unexpected_result", returned: inspect(other))}
    end
  end

  @spec write_receipt!(map(), String.t()) :: String.t()
  def write_receipt!(receipt, path) when is_binary(path) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true))
    path
  end

  defp command_opts(root) do
    [
      cd: root,
      env: [{"MIX_ENV", "test"}],
      stderr_to_stdout: true
    ]
  end

  defp read_receipt(path) do
    with {:ok, body} <- File.read(path),
         {:ok, %{} = receipt} <- Jason.decode(body) do
      {:ok, receipt}
    else
      {:ok, decoded} ->
        {:error, error("synapse_acceptance_receipt_not_object", decoded: inspect(decoded))}

      {:error, %Jason.DecodeError{} = reason} ->
        {:error,
         error("synapse_acceptance_receipt_json_invalid", reason: Exception.message(reason))}

      {:error, reason} ->
        {:error, error("synapse_acceptance_receipt_read_failed", reason: inspect(reason))}
    end
  end

  defp validate_receipt(receipt) do
    with :ok <- require_equal(receipt["schema_version"], @schema_version, "bad_schema_version"),
         :ok <- require_equal(receipt["status"], "pass", "bad_status"),
         :ok <- require_equal(receipt["product_repo"], "synapse", "bad_product_repo"),
         :ok <- require_equal(receipt["no_bypass"]["status"], "pass", "no_bypass_not_pass"),
         :ok <- require_equal(receipt["proofs"]["run_start"]["status"], "pass", "run_not_pass"),
         :ok <-
           require_equal(
             receipt["proofs"]["turn_submission"]["status"],
             "accepted",
             "turn_not_accepted"
           ) do
      require_equal(
        receipt["proofs"]["review_decision"]["status"],
        "accepted",
        "review_not_accepted"
      )
    end
  end

  defp require_equal(actual, expected, _code) when actual == expected, do: :ok

  defp require_equal(actual, expected, code) do
    {:error, error(code, actual: actual, expected: expected)}
  end

  defp remove_stale_receipt(path) do
    File.rm(path)
    :ok
  end

  defp default_example_receipt_path do
    Path.expand("tmp/stack_lab/synapse_acceptance/example_receipt.json", File.cwd!())
  end

  defp output_excerpt(output) do
    output
    |> String.split("\n")
    |> Enum.take(-20)
    |> Enum.join("\n")
  end

  defp error(code, details) do
    %{"code" => code, "details" => Map.new(details)}
  end

  defp mix_executable do
    System.find_executable("mix") || "mix"
  end
end
