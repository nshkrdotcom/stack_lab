defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.Environment do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support

  for {name, arity} <- [
        with_lower_backed_runtime: 3,
        surface_opts: 0,
        request_context: 3,
        request_context: 4,
        revision_epoch_metadata: 2,
        ensure_store_local_ready!: 1,
        stop_store_local: 0,
        store_local_dir: 1,
        lower_transport_config: 2,
        lower_transport_config: 3,
        policy_pack: 0,
        authorization_scope!: 1,
        tenant_scope!: 1,
        tenant_scope!: 2
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Support
  end
end
