defmodule StackLab.FuguLiveProviderGuard do
  @moduledoc false

  @schema_version "stack_lab.fugu_live_provider_guard.v1"
  @secret_wrapper "~/scripts/with_bash_secrets"
  @default_command "mix stack_lab.provider_smoke_check"

  @spec validate(keyword()) :: {:ok, map()} | {:error, map()}
  def validate(opts) when is_list(opts) do
    allow_live? = Keyword.get(opts, :allow_live?, false)
    secrets_loaded? = Keyword.get(opts, :secrets_loaded?, false)

    cond do
      allow_live? and secrets_loaded? ->
        {:ok, receipt(opts)}

      allow_live? ->
        {:error,
         error("live_profile_requires_secret_wrapper",
           required_prefix: @secret_wrapper,
           safe_action: "rerun_with_secret_wrapper_or_drop_live_flag"
         )}

      secrets_loaded? ->
        {:error,
         error("live_profile_requires_allow_live",
           required_flag: "--allow-live",
           safe_action: "rerun_with_explicit_live_opt_in"
         )}

      true ->
        {:error,
         error("live_profile_requires_explicit_opt_in",
           required_flags: ["--allow-live", "--secrets-loaded"],
           safe_action: "run_provider_free_readiness_handoff_instead"
         )}
    end
  end

  @spec claim() :: map()
  def claim do
    %{
      "schema_version" => @schema_version,
      "live_provider_behavior_ci_default?" => false,
      "requires_explicit_flags" => ["--allow-live", "--secrets-loaded"],
      "required_secret_wrapper" => @secret_wrapper,
      "guarded_command" => @default_command,
      "does_not_prove" => [
        "production credential rotation",
        "provider billing correctness",
        "multi-product live-provider parity",
        "distributed BEAM placement"
      ]
    }
  end

  defp receipt(opts) do
    claim()
    |> Map.merge(%{
      "status" => "guard_passed",
      "execution_mode" => Keyword.get(opts, :execution_mode, "ready_to_run"),
      "forwarded_command" => Keyword.get(opts, :command, @default_command)
    })
  end

  defp error(code, details) do
    %{
      "schema_version" => @schema_version,
      "status" => "rejected",
      "code" => code,
      "details" => Map.new(details)
    }
  end
end
