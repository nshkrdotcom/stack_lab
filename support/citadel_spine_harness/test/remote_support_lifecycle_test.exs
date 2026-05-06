defmodule StackLab.CitadelSpineHarness.RemoteSupportLifecycleTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness.BoundedNames
  alias StackLab.CitadelSpineHarness.RemoteSpine
  alias StackLab.CitadelSpineHarness.RemoteSupport

  test "local distributed node names are run-scoped instead of fixed slots" do
    names = for _index <- 1..16, do: BoundedNames.local_node_name()
    strings = Enum.map(names, &Atom.to_string/1)

    assert Enum.uniq(names) == names
    refute Enum.any?(strings, &Regex.match?(~r/^stack_lab_local_[a-z]$/, &1))
    assert Enum.all?(strings, &String.starts_with?(&1, "stack_lab_stack_lab_"))
  end

  @tag timeout: 30_000
  test "two harness tests can start remote spine peers concurrently" do
    tasks =
      for case_name <- [:concurrent_remote_spine_a, :concurrent_remote_spine_b] do
        Task.async(fn ->
          remote = RemoteSupport.start_remote_spine!(case_name)

          try do
            assert :ok == RemoteSupport.remote_call!(remote.remote_node, RemoteSpine, :ping, [])
            {remote.remote_node, remote.storage_dir}
          after
            :ok = RemoteSupport.stop_remote_spine(remote)
          end
        end)
      end

    results = Task.await_many(tasks, 30_000)

    assert results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2
    assert results |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 2
  end

  test "harness test modules do not force async false" do
    forbidden = "async: " <> "false"

    offenders =
      __DIR__
      |> Path.join("*_test.exs")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?(forbidden)
      end)
      |> Enum.map(&Path.relative_to(&1, Path.expand("../../..", __DIR__)))
      |> Enum.sort()

    assert offenders == []
  end
end
