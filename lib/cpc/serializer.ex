defmodule Cpc.Serializer do
  use GenServer
  require Logger

  def start_link(name) do
    GenServer.start_link(__MODULE__, {%{}, %{}, nil}, name: name)
  end

  def handle_info({from, :state?, filename}, state = {pid2fn, fn2content_length, ref}) do
    # The downloader has received a GET request which is neither a database nor a locally
    # available file. Hence, it needs to check if someone is already downloading this file.
    filename_status = case fn2content_length[filename] do
      nil -> :unknown
      content_length -> {:downloading, content_length}
    end
    send from, filename_status
    # If the filename state is unknown, it will start downloading the file, informing us of the
    # content length. No other downloads will be started while we wait for the content-length to
    # arrive.
    case filename_status do
      :unknown ->
        receive do
          {^from, :content_length, {filename, content_length, pid}} ->
            ref = :erlang.monitor(:process, pid)
            map1 = Map.put(pid2fn, pid, filename)
            map2 = Map.put(fn2content_length, filename, content_length)
            {:noreply, {map1, map2, ref}}
          {^from, :not_found} ->
            # Was not able to GET this file (server replied 404)
            {:noreply, state}
          {^from, :complete} ->
            # We have previously assumed that the locally stored file is incomplete, but it turns
            # out the file was already complete. No new download is started, state remains
            # unchanged.
            {:noreply, state}
        after 5000 ->
            raise "Expected an answer within 5 seconds."
        end
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, status}, {pid2fn, fn2content_length, _}) do
    :erlang.demonitor(ref)
    filename = pid2fn[pid]
    case status do
      :normal -> Logger.debug "Process #{inspect pid} has ended with status normal."
      status -> Logger.error "Process #{inspect pid} has ended with status #{inspect status}."
    end
    map1 = Map.delete(pid2fn, pid)
    map2 = Map.delete(fn2content_length, filename)
    {:noreply, {map1, map2, nil}}
  end

  def handle_cast({:download_ended, filename, pid}, {pid2fn, fn2content_length, ref}) do
    :erlang.demonitor(ref)
    Logger.info "Download ended: #{filename}"
    filename = pid2fn[pid]
    map1 = Map.delete(pid2fn, pid)
    map2 = Map.delete(fn2content_length, filename)
    {:noreply, {map1, map2, ref}}
  end

end
