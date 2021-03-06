defmodule Cpc do
  use Application
  alias Cpc.TableAccess
  require Logger
  @config_path "/etc/cpcache/cpcache.toml"

  defp init_round_robin(config) do
    num_mirrors = Enum.count(get_or_raise(config, "mirrors_predefined"))
    random = Enum.random(0..(num_mirrors - 1))
    :ets.insert(:cpc_state, {:round_robin, {random, num_mirrors}})
  end

  def get_or_raise(map = %{}, key) do
    case Map.get(map, key) do
      nil ->
        raise "Unable to fetch key #{inspect(key)}. Please make sure the TOML file " <>
                "#{inspect(@config_path)} contains all required keys."

      value ->
        value
    end
  end

  def init_config() do
    config = Jerry.decode!(File.read!(@config_path))
    :ets.new(:cpc_config, [:named_table, :protected, read_concurrency: true])
    :ets.new(:cpc_state, [:named_table, :public])
    :ets.insert(:cpc_config, {:port, get_or_raise(config, "port")})
    :ets.insert(:cpc_config, {:cache_directory, get_or_raise(config, "cache_directory")})
    :ets.insert(:cpc_config, {:ipv6_enabled, get_or_raise(config, "ipv6_enabled")})
    :ets.insert(:cpc_config, {:mirrors, get_or_raise(config, "mirrors_predefined")})
    :ets.insert(:cpc_config, {:mirrors_blacklist, get_or_raise(config, "mirrors_blacklist")})
    :ets.insert(:cpc_config, {:recv_packages, config["recv_packages"]})

    case get_or_raise(config, "mirror_selection_method") do
      "auto" ->
        mirrors_auto = get_or_raise(config, "mirrors_auto")

        map = %{
          https_required: get_or_raise(mirrors_auto, "https_required"),
          ipv4: get_or_raise(mirrors_auto, "ipv4"),
          ipv6: get_or_raise(mirrors_auto, "ipv6"),
          max_score: get_or_raise(mirrors_auto, "max_score"),
          timeout: get_or_raise(mirrors_auto, "timeout"),
          test_interval: get_or_raise(mirrors_auto, "test_interval")
        }

        :ets.insert(:cpc_config, {:mirror_selection, {:auto, map}})

      "predefined" ->
        :ok
    end

    init_round_robin(config)
  end

  def init_dets() do
    TableAccess.create_table("content_length")
    TableAccess.create_table("ipv6_support")
    TableAccess.create_table("ipv4_support")
    TableAccess.create_table("mirrors_status")
  end

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    init_config()
    init_dets()

    children = [
      supervisor(Cpc.ArchSupervisor, []),
      supervisor(Cpc.AcceptorSupervisor, [])
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
