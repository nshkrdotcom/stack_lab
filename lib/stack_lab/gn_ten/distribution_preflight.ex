defmodule StackLab.GnTen.DistributionPreflight do
  @moduledoc """
  Phase 2 local Erlang distribution preflight for the gn-ten distributed proof.

  This module intentionally lives at the StackLab root until
  `support/gn_ten_node_lab` exists. It proves the host-level substrate pieces
  that the later package will own: EPMD, controller distribution, shortname
  generation, redacted per-run cookie generation, port range validation,
  temporary peer lifecycle, bounded remote calls, socket exposure recording, and
  cleanup.
  """

  alias StackLab.CommandRunner

  @schema_version "stack_lab.gn_ten.distribution_preflight.v1"
  @receipt_ref "receipt://stack_lab/gn_ten_distributed_preflight/latest"
  @trace_ref "trace://stack_lab/gn_ten_distributed_preflight/latest"
  @default_port_range 43_000..43_100
  @remote_call_timeout_ms 5_000

  @type failure :: %{
          required(:code) => String.t(),
          optional(:message) => String.t(),
          optional(:details) => term()
        }

  @spec receipt_ref() :: String.t()
  def receipt_ref, do: @receipt_ref

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.join(["docs", "receipts", "gn_ten_distributed", "distribution_preflight.json"])
  end

  @spec run(keyword()) :: {:ok, map()} | {:error, map()}
  def run(opts \\ []) when is_list(opts) do
    started_at = DateTime.utc_now()
    run_id = run_id()
    cookie = Keyword.get_lazy(opts, :cookie, &generate_cookie!/0)
    port_range = Keyword.get(opts, :dist_port_range, @default_port_range)

    result =
      with {:ok, epmd} <- ensure_epmd_started(Keyword.get(opts, :epmd_path, :system)),
           {:ok, distribution} <- ensure_distribution_started(),
           {:ok, port_range_receipt} <- validate_port_range(port_range),
           {:ok, peer_probe} <- run_peer_probe() do
        epmd = refresh_epmd_names(epmd)
        socket_exposure = socket_exposure(epmd, distribution)

        {:ok,
         receipt(%{
           run_id: run_id,
           started_at: started_at,
           finished_at: DateTime.utc_now(),
           status: "pass",
           epmd: epmd,
           distribution: distribution,
           cookie_posture: cookie_posture(cookie),
           port_range: port_range_receipt,
           peer_probe: peer_probe,
           socket_exposure: socket_exposure,
           failures: [],
           warnings: socket_warnings(socket_exposure)
         })}
      else
        {:error, failure} ->
          {:error,
           receipt(%{
             run_id: run_id,
             started_at: started_at,
             finished_at: DateTime.utc_now(),
             status: "fail",
             epmd: %{},
             distribution: %{},
             cookie_posture: cookie_posture(cookie),
             port_range: %{},
             peer_probe: %{},
             socket_exposure: %{},
             failures: [failure],
             warnings: []
           })}
      end

    write_if_requested(result, opts)
  end

  @spec ensure_epmd_started(keyword() | nil | :system | String.t()) ::
          {:ok, map()} | {:error, failure()}
  def ensure_epmd_started(epmd_path \\ :system)

  def ensure_epmd_started(:system), do: ensure_epmd_started(System.find_executable("epmd"))

  def ensure_epmd_started(nil),
    do: {:error, failure("epmd_not_found", "epmd executable not found")}

  def ensure_epmd_started(epmd_path) when is_binary(epmd_path) do
    started_at = System.monotonic_time(:millisecond)

    case CommandRunner.run(epmd_path, ["-daemon"], timeout_ms: 5_000) do
      {:ok, command_receipt} ->
        {:ok,
         %{
           "executable_found?" => true,
           "path" => epmd_path,
           "start_status" => "ok",
           "duration_ms" => elapsed_ms(started_at),
           "names" => epmd_names(epmd_path),
           "command" => command_summary(command_receipt)
         }}

      {:error, command_receipt} ->
        {:error,
         failure("epmd_start_failed", "epmd -daemon failed",
           command: command_summary(command_receipt)
         )}
    end
  end

  @spec ensure_distribution_started() :: {:ok, map()} | {:error, failure()}
  def ensure_distribution_started do
    if Node.alive?(),
      do: {:ok, distribution_receipt(false)},
      else: start_controller_distribution()
  end

  defp start_controller_distribution do
    with {:ok, node_name} <- generated_node_name(:controller),
         :ok <- validate_node_name_available(node_name) do
      node_name
      |> Node.start(name_domain: :shortnames)
      |> normalize_node_start(node_name)
    end
  end

  defp normalize_node_start({:ok, _pid}, _node_name), do: {:ok, distribution_receipt(true)}

  defp normalize_node_start({:error, {:already_started, _pid}}, _node_name),
    do: ensure_distribution_started()

  defp normalize_node_start({:error, reason}, node_name) do
    {:error,
     failure("distribution_start_failed", "unable to start distributed node",
       reason: inspect(reason),
       attempted_name: Atom.to_string(node_name)
     )}
  end

  defp distribution_receipt(started_by_preflight?) do
    %{
      "node_alive?" => true,
      "node_name" => Atom.to_string(Node.self()),
      "name_domain" => name_domain(Node.self()),
      "started_by_preflight?" => started_by_preflight?
    }
  end

  @spec generated_node_name(:controller | :peer) :: {:ok, atom()} | {:error, failure()}
  def generated_node_name(kind) when kind in [:controller, :peer] do
    suffix = System.unique_integer([:positive, :monotonic])
    {:ok, :"stack_lab_preflight_#{kind}_#{suffix}"}
  end

  @spec validate_node_name_available(node()) :: :ok | {:error, failure()}
  def validate_node_name_available(name) when is_atom(name) do
    cond do
      Node.alive?() and Node.self() == name ->
        {:error, failure("duplicate_node_name", "node name is already used by the controller")}

      name in Node.list(:connected) ->
        {:error, failure("duplicate_node_name", "node name is already connected")}

      true ->
        :ok
    end
  end

  @spec generate_cookie() :: {:ok, String.t()}
  def generate_cookie do
    {:ok, generate_cookie!()}
  end

  @spec validate_cookie(String.t()) :: :ok | {:error, failure()}
  def validate_cookie(cookie) when is_binary(cookie) do
    valid? =
      byte_size(cookie) in 24..128 and
        cookie
        |> :binary.bin_to_list()
        |> Enum.all?(&safe_cookie_byte?/1)

    if valid? do
      :ok
    else
      {:error, failure("invalid_cookie", "cookie must be 24..128 safe printable bytes")}
    end
  end

  def validate_cookie(_cookie), do: {:error, failure("invalid_cookie", "cookie must be binary")}

  @spec cookie_posture(String.t()) :: map()
  def cookie_posture(cookie) when is_binary(cookie) do
    :ok = validate_cookie!(cookie)

    %{
      "posture" => "generated_redacted_not_applied_in_phase2",
      "byte_size" => byte_size(cookie),
      "secret_value_present?" => false,
      "phase3_required_action" =>
        "support/gn_ten_node_lab must apply a per-run cookie when it owns peer boot"
    }
  end

  @spec validate_port_range(Range.t()) :: {:ok, map()} | {:error, failure()}
  def validate_port_range(first..last//1)
      when is_integer(first) and is_integer(last) and first >= 1 and last <= 65_535 and
             first < last do
    {:ok,
     %{
       "configured?" => true,
       "min" => first,
       "max" => last,
       "vm_args" => [
         "-kernel",
         "inet_dist_listen_min",
         Integer.to_string(first),
         "inet_dist_listen_max",
         Integer.to_string(last)
       ]
     }}
  end

  def validate_port_range(_range) do
    {:error,
     failure(
       "invalid_dist_port_range",
       "distribution port range must be ascending and inside 1..65535"
     )}
  end

  @spec with_probe_peer((map() -> term())) :: {:ok, term()} | {:error, failure()}
  def with_probe_peer(fun) when is_function(fun, 1) do
    with {:ok, _distribution} <- ensure_distribution_started(),
         {:ok, peer_name} <- generated_node_name(:peer),
         :ok <- validate_node_name_available(peer_name),
         {:ok, peer_pid, peer_node} <- start_peer(peer_name) do
      peer = %{peer_pid: peer_pid, peer_node: peer_node, peer_name: peer_name}

      try do
        {:ok, fun.(peer)}
      rescue
        exception ->
          {:error,
           failure("peer_probe_failed", Exception.message(exception),
             cleanup: cleanup_peer(peer),
             exception: inspect(exception.__struct__)
           )}
      catch
        kind, reason ->
          {:error,
           failure("peer_probe_failed", "peer probe threw or exited",
             cleanup: cleanup_peer(peer),
             kind: kind,
             reason: inspect(reason)
           )}
      else
        {:ok, value} ->
          cleanup = cleanup_peer(peer)

          if cleanup["stopped?"] do
            {:ok, value}
          else
            {:error, failure("peer_cleanup_failed", "peer did not stop", cleanup: cleanup)}
          end
      end
    end
  end

  @spec write_receipt!(map(), Path.t()) :: Path.t()
  def write_receipt!(receipt, path) when is_map(receipt) and is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true) <> "\n")
    path
  end

  defp run_peer_probe do
    with_probe_peer(fn %{peer_node: peer_node} ->
      started_at = System.monotonic_time(:millisecond)

      case remote_call(peer_node, :erlang, :node, []) do
        {:ok, ^peer_node} ->
          %{
            "started?" => true,
            "peer_node" => Atom.to_string(peer_node),
            "remote_call" => "ok",
            "remote_call_duration_ms" => elapsed_ms(started_at)
          }

        {:ok, other_node} ->
          raise "peer returned unexpected node #{inspect(other_node)}"

        {:error, reason} ->
          raise "peer remote call failed #{inspect(reason)}"
      end
    end)
    |> case do
      {:ok, receipt} ->
        {:ok,
         receipt
         |> Map.put("stopped?", true)
         |> Map.put("reachable_after_stop?", false)}

      {:error, failure} ->
        {:error, failure}
    end
  end

  defp write_if_requested({:ok, receipt}, opts) do
    case Keyword.get(opts, :receipt_path) do
      nil -> {:ok, receipt}
      path -> {:ok, Map.put(receipt, "receipt_path", write_receipt!(receipt, path))}
    end
  end

  defp write_if_requested({:error, receipt}, opts) do
    case Keyword.get(opts, :receipt_path) do
      nil -> {:error, receipt}
      path -> {:error, Map.put(receipt, "receipt_path", write_receipt!(receipt, path))}
    end
  end

  defp start_peer(peer_name) do
    case :peer.start_link(%{name: peer_name}) do
      {:ok, _peer_pid, _peer_node} = peer ->
        peer

      {:error, reason} ->
        {:error,
         failure("peer_start_failed", "unable to start probe peer", reason: inspect(reason))}
    end
  end

  defp cleanup_peer(%{peer_pid: peer_pid, peer_node: peer_node}) do
    if Process.alive?(peer_pid) do
      _ = :peer.stop(peer_pid)
    end

    reachable_after_stop? = :net_adm.ping(peer_node) == :pong

    %{
      "stopped?" => not Process.alive?(peer_pid),
      "reachable_after_stop?" => reachable_after_stop?
    }
  end

  defp remote_call(node, module, function, args) do
    {:ok, :erpc.call(node, module, function, args, @remote_call_timeout_ms)}
  rescue
    error in ErlangError -> {:error, normalize_erpc_error(error.original)}
  catch
    :exit, reason -> {:error, reason}
  end

  defp receipt(attrs) do
    %{
      "schema_version" => @schema_version,
      "receipt_ref" => @receipt_ref,
      "trace_ref" => @trace_ref,
      "status" => attrs.status,
      "run_id" => attrs.run_id,
      "started_at" => DateTime.to_iso8601(attrs.started_at),
      "finished_at" => DateTime.to_iso8601(attrs.finished_at),
      "epmd" => attrs.epmd,
      "distribution" => attrs.distribution,
      "cookie_posture" => attrs.cookie_posture,
      "port_range" => attrs.port_range,
      "peer_probe" => attrs.peer_probe,
      "socket_exposure" => attrs.socket_exposure,
      "existing_multi_node_proofs" => existing_multi_node_proofs(),
      "failures" => attrs.failures,
      "warnings" => attrs.warnings,
      "does_not_prove" => [
        "owner facade availability",
        "domain business semantics",
        "monolith/distributed parity",
        "per-run cookie application to peers",
        "production distribution security",
        "release artifact boot"
      ]
    }
  end

  defp epmd_names(epmd_path) do
    case CommandRunner.run(epmd_path, ["-names"], timeout_ms: 5_000) do
      {:ok, %{output: output}} ->
        %{
          "status" => "ok",
          "raw_redacted" => String.trim(output),
          "ports" => parse_epmd_ports(output)
        }

      {:error, %{output: output, exit_status: exit_status}} ->
        %{
          "status" => "failed",
          "exit_status" => exit_status,
          "raw_redacted" => String.trim(output),
          "ports" => []
        }
    end
  end

  defp refresh_epmd_names(%{"path" => epmd_path} = epmd) do
    Map.put(epmd, "names", epmd_names(epmd_path))
  end

  defp parse_epmd_ports(output) do
    ~r/name\s+([^\s]+)\s+at\s+port\s+(\d+)/
    |> Regex.scan(output)
    |> Enum.map(fn [_match, name, port] ->
      %{"name" => name, "port" => String.to_integer(port)}
    end)
  end

  defp socket_exposure(epmd, distribution) do
    ports =
      [4_369]
      |> Kernel.++(distribution_ports(epmd, distribution))
      |> Enum.uniq()

    case listen_sockets(ports) do
      {:ok, sockets} ->
        %{
          "source" => "ss -ltn",
          "ports_checked" => ports,
          "sockets" => sockets,
          "loopback_only?" => loopback_only?(sockets),
          "posture" =>
            if(loopback_only?(sockets), do: "loopback_only", else: "non_loopback_or_unknown")
        }

      {:error, reason} ->
        %{
          "source" => "unavailable",
          "ports_checked" => ports,
          "sockets" => [],
          "loopback_only?" => nil,
          "posture" => "unknown",
          "reason" => reason
        }
    end
  end

  defp distribution_ports(epmd, distribution) do
    current_name =
      distribution
      |> Map.get("node_name", "")
      |> String.split("@")
      |> List.first()

    epmd
    |> get_in(["names", "ports"])
    |> List.wrap()
    |> Enum.filter(&(Map.get(&1, "name") == current_name))
    |> Enum.map(&Map.fetch!(&1, "port"))
  end

  defp listen_sockets(ports) do
    case System.find_executable("ss") do
      nil ->
        {:error, "ss executable not found"}

      ss ->
        case CommandRunner.run(ss, ["-ltn"], timeout_ms: 5_000) do
          {:ok, %{output: output}} -> {:ok, parse_listen_sockets(output, ports)}
          {:error, %{exit_status: status}} -> {:error, "ss exited #{status}"}
        end
    end
  end

  defp parse_listen_sockets(output, ports) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case socket_line(line, ports) do
        nil -> []
        socket -> [socket]
      end
    end)
  end

  defp socket_line(line, ports) do
    parts = String.split(line)

    with true <- List.first(parts) == "LISTEN",
         local when is_binary(local) <- Enum.at(parts, 3),
         {:ok, port} <- local_port(local),
         true <- port in ports do
      %{
        "local" => local,
        "port" => port,
        "loopback?" => loopback_local?(local)
      }
    else
      _ -> nil
    end
  end

  defp local_port(local) do
    local
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(":")
    |> List.last()
    |> Integer.parse()
    |> case do
      {port, ""} -> {:ok, port}
      _other -> :error
    end
  end

  defp loopback_only?([]), do: nil

  defp loopback_only?(sockets) do
    Enum.all?(sockets, &Map.fetch!(&1, "loopback?"))
  end

  defp loopback_local?(local) do
    local in ["127.0.0.1", "[::1]", "::1"] or
      String.starts_with?(local, "127.") or
      String.starts_with?(local, "[::1]:") or
      String.starts_with?(local, "::1:")
  end

  defp socket_warnings(%{"loopback_only?" => false}) do
    [
      %{
        "code" => "non_loopback_distribution_socket",
        "message" =>
          "local development may continue, but staging/production distribution claims must fail closed"
      }
    ]
  end

  defp socket_warnings(_socket_exposure), do: []

  defp command_summary(%CommandRunner.Receipt{} = receipt) do
    %{
      "command" => receipt.command,
      "args" => receipt.args,
      "status" => Atom.to_string(receipt.status),
      "exit_status" => receipt.exit_status,
      "duration_ms" => receipt.duration_ms,
      "redacted?" => receipt.redacted?
    }
  end

  defp existing_multi_node_proofs do
    [
      %{
        "project" => "examples/multi_node_roundtrip",
        "current_root_ci_posture" => "included_by_blitz_monorepo_test_credo_docs",
        "phase2_migration_decision" => "kept_parallel_until_support_gn_ten_node_lab_migration"
      },
      %{
        "project" => "support/citadel_spine_harness",
        "current_root_ci_posture" => "included_by_blitz_monorepo_test_credo_docs",
        "phase2_migration_decision" => "source_reference_and_future_consumer"
      }
    ]
  end

  defp failure(code, message, details \\ []) do
    %{code: code, message: message}
    |> maybe_put_details(details)
  end

  defp maybe_put_details(failure, []), do: failure

  defp maybe_put_details(failure, details) when is_list(details) do
    Enum.reduce(details, failure, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  defp generate_cookie! do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp validate_cookie!(cookie) do
    case validate_cookie(cookie) do
      :ok -> :ok
      {:error, failure} -> raise ArgumentError, inspect(failure)
    end
  end

  defp safe_cookie_byte?(byte)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?_, ?-],
       do: true

  defp safe_cookie_byte?(_byte), do: false

  defp run_id do
    "gn-ten-preflight-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp elapsed_ms(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end

  defp name_domain(node) do
    node
    |> Atom.to_string()
    |> String.contains?(".")
    |> if(do: "longnames", else: "shortnames")
  end

  defp normalize_erpc_error({:erpc, _reason} = reason), do: reason
  defp normalize_erpc_error(reason), do: {:erpc, reason}
end
