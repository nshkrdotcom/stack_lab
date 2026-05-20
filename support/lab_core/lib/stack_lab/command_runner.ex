defmodule StackLab.CommandRunner do
  @moduledoc """
  Central command execution boundary for StackLab harnesses and Mix tasks.

  StackLab is allowed to orchestrate local commands, but every call must pass
  through one place for cwd validation, shell-mode declaration, environment
  allowlisting, timeout metadata, and output redaction.
  """

  defmodule Receipt do
    @moduledoc "Structured command execution receipt."

    @enforce_keys [:command, :args, :cwd, :status, :exit_status, :timeout_ms]
    defstruct [
      :command,
      :args,
      :cwd,
      :status,
      :exit_status,
      :timeout_ms,
      :output,
      :started_at_ms,
      :duration_ms,
      env_keys: [],
      shell?: false,
      redacted?: false,
      reason: nil
    ]

    @type t :: %__MODULE__{
            command: String.t(),
            args: [String.t()],
            cwd: String.t(),
            status: :ok | :failed | :blocked,
            exit_status: non_neg_integer(),
            timeout_ms: pos_integer(),
            output: term(),
            started_at_ms: integer(),
            duration_ms: non_neg_integer(),
            env_keys: [String.t()],
            shell?: boolean(),
            redacted?: boolean(),
            reason: term()
          }
  end

  @blocked_shell_tokens [";", "&&", "||", "`", "$(", ">", "<", "|", "\n"]
  @default_timeout_ms 30_000

  @type receipt :: Receipt.t()

  @spec run(String.t(), [String.t()], keyword()) :: {:ok, receipt()} | {:error, receipt()}
  def run(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    started_at = System.monotonic_time(:millisecond)

    with {:ok, cwd} <- validate_cwd(opts),
         {:ok, timeout_ms} <- validate_timeout(opts),
         :ok <- validate_shell_mode(command, args, opts),
         :ok <- validate_shell_tokens(command, args, opts),
         {:ok, env_keys} <- validate_env(opts) do
      {output, exit_status} =
        command
        |> System.cmd(args, system_opts(opts))
        |> normalize_output(opts)

      receipt =
        receipt(command, args, cwd, opts,
          status: status(exit_status),
          exit_status: exit_status,
          timeout_ms: timeout_ms,
          output: output,
          env_keys: env_keys,
          started_at_ms: started_at
        )

      if exit_status == 0, do: {:ok, receipt}, else: {:error, receipt}
    else
      {:error, reason} ->
        {:error,
         receipt(command, args, cwd_from_opts(opts), opts,
           status: :blocked,
           exit_status: 1,
           timeout_ms: timeout_from_opts(opts),
           output: "",
           env_keys: env_keys_from_opts(opts),
           reason: reason,
           started_at_ms: started_at
         )}
    end
  end

  @spec system_cmd(String.t(), [String.t()], keyword()) :: {term(), non_neg_integer()}
  def system_cmd(command, args, opts \\ []) do
    case run(command, args, opts) do
      {:ok, %Receipt{output: output, exit_status: exit_status}} -> {output, exit_status}
      {:error, %Receipt{output: output, exit_status: exit_status}} -> {output, exit_status}
    end
  end

  @spec run_ok(String.t(), [String.t()], keyword()) ::
          {:ok, String.t()} | {:error, %{exit_status: non_neg_integer(), output: String.t()}}
  def run_ok(command, args, opts \\ []) do
    case run(command, args, opts) do
      {:ok, %Receipt{output: output}} ->
        {:ok, output}

      {:error, %Receipt{output: output, exit_status: exit_status}} ->
        {:error, %{exit_status: exit_status, output: output}}
    end
  end

  defp validate_cwd(opts) do
    cwd = cwd_from_opts(opts)

    if File.dir?(cwd), do: {:ok, cwd}, else: {:error, {:invalid_cwd, cwd}}
  end

  defp validate_timeout(opts) do
    case timeout_from_opts(opts) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> {:ok, timeout_ms}
      timeout_ms -> {:error, {:invalid_timeout_ms, timeout_ms}}
    end
  end

  defp validate_shell_mode("sh", ["-lc", _command], opts) do
    if Keyword.get(opts, :allow_shell, false),
      do: :ok,
      else: {:error, :shell_mode_requires_explicit_allowance}
  end

  defp validate_shell_mode(_command, _args, _opts), do: :ok

  defp validate_shell_tokens(command, args, opts) do
    if Keyword.get(opts, :allow_shell, false) do
      :ok
    else
      command
      |> List.wrap()
      |> Kernel.++(args)
      |> Enum.find(&blocked_shell_token?/1)
      |> case do
        nil -> :ok
        value -> {:error, {:blocked_shell_token, value}}
      end
    end
  end

  defp blocked_shell_token?(value) when is_binary(value) do
    Enum.any?(@blocked_shell_tokens, &String.contains?(value, &1))
  end

  defp blocked_shell_token?(_value), do: true

  defp validate_env(opts) do
    env = Keyword.get(opts, :env, [])
    allowlist = opts |> Keyword.get(:env_allowlist, []) |> MapSet.new()

    env
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> Enum.find(&(not MapSet.member?(allowlist, &1)))
    |> case do
      nil -> {:ok, Enum.map(env, fn {key, _value} -> to_string(key) end)}
      key -> {:error, {:env_key_not_allowed, key}}
    end
  end

  defp normalize_output({output, exit_status}, opts) when is_binary(output) do
    {redact(output, Keyword.get(opts, :redact, [])), exit_status}
  end

  defp normalize_output({output, exit_status}, _opts), do: {output, exit_status}

  defp redact(output, redactions) do
    Enum.reduce(redactions, output, fn
      secret, output when is_binary(secret) and secret != "" ->
        String.replace(output, secret, "[REDACTED]")

      _secret, output ->
        output
    end)
  end

  defp system_opts(opts) do
    opts
    |> Keyword.drop([:allow_shell, :env_allowlist, :redact, :timeout, :timeout_ms])
  end

  defp receipt(command, args, cwd, opts, attrs) do
    finished_at = System.monotonic_time(:millisecond)
    started_at = Keyword.fetch!(attrs, :started_at_ms)

    %Receipt{
      command: command,
      args: args,
      cwd: cwd,
      status: Keyword.fetch!(attrs, :status),
      exit_status: Keyword.fetch!(attrs, :exit_status),
      timeout_ms: Keyword.fetch!(attrs, :timeout_ms),
      output: Keyword.fetch!(attrs, :output),
      started_at_ms: started_at,
      duration_ms: max(finished_at - started_at, 0),
      env_keys: Keyword.fetch!(attrs, :env_keys),
      shell?: Keyword.get(opts, :allow_shell, false),
      redacted?: Keyword.get(opts, :redact, []) != [],
      reason: Keyword.get(attrs, :reason)
    }
  end

  defp status(0), do: :ok
  defp status(_exit_status), do: :failed

  defp cwd_from_opts(opts), do: opts |> Keyword.get(:cd, File.cwd!()) |> Path.expand()

  defp timeout_from_opts(opts),
    do: Keyword.get(opts, :timeout_ms, Keyword.get(opts, :timeout, @default_timeout_ms))

  defp env_keys_from_opts(opts) do
    opts
    |> Keyword.get(:env, [])
    |> Enum.map(fn {key, _value} -> to_string(key) end)
  end
end
