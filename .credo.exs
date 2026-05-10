%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "mix.exs",
          "lib/",
          "support/*/lib/",
          "examples/*/lib/"
        ],
        excluded: [
          "_build/",
          "deps/",
          "dist/",
          "doc/",
          "tmp/"
        ]
      },
      checks: [
        {Weld.Credo.Check.NoRuntimeOsEnv, []}
      ]
    }
  ]
}
