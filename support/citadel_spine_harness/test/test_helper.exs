case StackLab.CitadelSpineHarness.RemoteSupport.ensure_distribution_started() do
  :ok ->
    :ok

  {:error, reason} ->
    raise StackLab.CitadelSpineHarness.RemoteSupport.distribution_start_error_message(reason)
end

ExUnit.start(capture_log: true, max_cases: 1)
