defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.RepoSandbox do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support

  for {name, arity} <- [
        seed_mezzanine_subject!: 2,
        seed_trace_ledger: 3,
        fetch_installation!: 1,
        enrich_subject_trace_graph!: 4,
        archived_pivot_summaries!: 2,
        archived_pivot_error!: 3,
        dump_uuid!: 1
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Support
  end
end
