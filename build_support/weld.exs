unless Code.ensure_loaded?(StackLab.Build.WeldContract) do
  Code.require_file("weld_contract.exs", __DIR__)
end

StackLab.Build.WeldContract.manifest()
