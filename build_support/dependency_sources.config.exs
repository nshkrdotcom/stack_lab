%{
  deps: %{
    ground_plane_contracts: %{
      path: "../ground_plane/core/ground_plane_contracts",
      github: %{
        repo: "nshkrdotcom/ground_plane",
        branch: "main",
        subdir: "core/ground_plane_contracts"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    }
  }
}
