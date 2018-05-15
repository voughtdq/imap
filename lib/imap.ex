defmodule IMAP do
  # Copyright (c) 2014, ThusFresh Inc
  # All rights reserved.
  #
  # Redistribution and use in source and binary forms, with or without
  # modification, are permitted provided that the following conditions
  # are met:
  #
  # 1. Redistributions of source code must retain the above copyright
  # notice, this list of conditions and the following disclaimer.
  #
  # 2. Redistributions in binary form must reproduce the above
  # copyright notice, this list of conditions and the following
  # disclaimer in the documentation and/or other materials provided
  # with the distribution.
  #
  # 3. Neither the name of the copyright holder nor the names of its
  # contributors may be used to endorse or promote products derived
  # from this software without specific prior written permission.
  #
  # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
  # CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
  # INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
  # MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  # DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS
  # BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
  # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
  # TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  # DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
  # ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
  # TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
  # THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
  # SUCH DAMAGE.

  use GenServer

  alias IMAP.Tokenizer
  import IMAP.Commands, only: [cmd_to_data: 1]

  require Logger

  defstruct [socket: nil,
             connspec: nil,
             +: false,
             opts: [],
             tag: 0,
             tokenizer: %Tokenizer{},
             cmds: {0, nil}]

  def start_link([connspec, opts]) do
    GenServer.start_link(__MODULE__, [connspec, opts])
  end

  def init([{socket, host, port} = connspec, opts]) do
    startup(self(), Keyword.get(opts, :cmds, []))

    init_callback = Keyword.get(opts, :init_callback, fn x -> x end)

    state = %__MODULE__{connspec: connspec, opts: opts}

    case socket.connect(host, port, [:binary]) do
      {:ok, socket} ->
        {:ok, init_callback.(%{state | socket: socket})}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_cast({:cmd, cmd, _}, %{+: true, socket: socket} = state) do
    :ok = :ssl.send(socket, cmd_to_data(cmd))
    {:noreply, %{state | +: false}}
  end

  def handle_cast({:cmd, cmd, _} = cmd_tup,
    %{cmds: cmds, socket: socket, tag: tag} = state) do

    ctag = make_tag(tag)
    :ok  = :ssl.send(socket, [ctag, " " | cmd_to_data(cmd)])
    cmds = put_cmd(ctag, cmd_tup, cmds)

    {:noreply, %{state | cmds: cmds, tag: tag+1}}
  end

  def handle_cast({:lifecycle, :finished}, %{opts: opts} = state) do
    post_init_callback =  Keyword.get(opts, :post_init_callback, fn(x) -> x end)

    {:noreply, post_init_callback.(state)}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_cast(request, state) do
    Logger.debug(fn ->
      "unhandled cast: #{inspect(request)}"
    end)
    {:noreply, state}
  end

  defp make_tag(tag) do
    <<?C, :erlang.integer_to_binary(tag)::binary>>
  end

  def handle_info({:ssl, socket, data},
    %{socket: socket, tokenizer: tokenizer} = state) do
    %{token_state: {buffer, acc}} = tokenizer

    buffer    = <<buffer::binary, data::binary>>
    tokenizer = %{tokenizer | token_state: {buffer, acc}}
    state     = %{state | tokenizer: tokenizer}

    {:noreply, churn_buffer(state)}
  end

  def handle_info({:ssl_closed, socket}, %{socket: socket} = state) do
    {:stop, {:error, :ssl_closed}, state}
  end

  def handle_info(msg, state) do
    Logger.debug(fn ->
      "unhandled message: #{inspect(msg)}"
    end)
    {:noreply, state}
  end

  def dispatch_to(ref) do
    fn(message) -> send(ref, message) end
  end

  def cast(server, cmd) do
    cast(server, cmd, [dispatch: dispatch_to(self())])
  end

  def cast(server, cmd, opts) do
    GenServer.cast(server, {:cmd, cmd, opts})
  end

  def call(server, cmd) do
    call(server, cmd, [dispatch: dispatch_to(self())])
  end

  def call(server, cmd, opts, timeout \\ 5000) do
    if Process.alive?(server) do
      cast(server, cmd, opts)

      ref       = Process.monitor(server)
      responses = recv(timeout, ref)
      true      = Process.demonitor(ref)

      responses
    else
      {:error, :noprocess}
    end
  end

  def recv(timeout, ref, responses \\ []) do
    receive do
      {:+, resp} ->
        {:+, Enum.reverse([{:+, resp} | responses])}
      {:*, resp} ->
        recv(timeout, ref, [{:*, resp} | responses])
      {:OK, resp} ->
        {:ok, {{:OK, resp}, Enum.reverse(responses)}}
      {at, resp} when at in [:NO, :BAD] ->
        {:error, {{at, resp}, Enum.reverse(responses)}}
      {:DOWN, ^ref, :process, _, reason} ->
        {:error, {{:down, reason}, Enum.reverse(responses)}}
    after
      timeout -> {:error, :timeout}
    end
  end

  def finished(imap) do
    GenServer.cast(imap, {:lifecycle, :finished})
  end

  def startup(imap, []) do
    finished(imap)
  end

  def startup(imap, cmds) do
    spawn_link(fn ->
      cmds
      |> Enum.map(&map_cmds/1)
      |> Enum.each(fn({gen, args}) ->
        case apply(__MODULE__, gen, [imap | args]) do
          :ok      -> :ok
          {:ok, _} -> :ok
          {:+, _}  -> :ok
        end
      end)

      finished(imap)
    end)
  end

  def dispatch({:cmd, _, opts} = internal, msg) do
    dispatch(internal, msg, Keyword.get_values(opts, :dispatch))
  end

  def dispatch(_, _, []) do
    :ok
  end

  def dispatch(internal, msg, [fun | rest]) do
    :ok = fun.(msg)
    dispatch(internal, msg, rest)
  end

  defp map_cmds({:cmd, {gen, cmd}}) do
    {gen, [cmd]}
  end

  defp map_cmds({:cmd, {gen, cmd}, opts}) do
    {gen, [cmd, opts]}
  end

  def churn_buffer(%{tokenizer: tokenizer} = state) do
    %{token_state: token_state, parse_state: parse_state} = tokenizer

    {result, token_state, parse_state} = Tokenizer.decode_line(token_state, parse_state)
    tokenizer = %{tokenizer | token_state: token_state,
                  parse_state: parse_state}

    churn_buffer(%{state | tokenizer: tokenizer}, result)
  end

  def churn_buffer(state, nil) do
    state
  end

  def churn_buffer(state, []) do
    state
  end

  def churn_buffer(%{cmds: cmds} = state, ["*" | resp]) do
    :ok = Enum.each(:gb_trees.values(cmds), fn cmd ->
      dispatch(cmd, {:*, resp})
    end)

    churn_buffer(state)
  end


  # The IMAP rfc says that we have to account for continuation
  # mode. This ensures that the imap client is aware that we are in
  # continuation mode.
  def churn_buffer(%{cmds: cmds} = state, ["+" | resp]) do
    :ok = Enum.each(:gb_trees.values(cmds), fn cmd ->
      dispatch(cmd, {:+, resp})
    end)

    churn_buffer(%{state | +: true})
  end

  def churn_buffer(%{cmds: cmds} = state, [tag | resp]) do
    case get_cmd(tag, cmds) do
      {:value, cmd} ->
        :ok = dispatch(cmd,
        case resp do
          ["OK" | rest]  -> {:OK, rest}
          ["NO" | rest]  -> {:NO, rest}
          ["BAD" | rest] -> {:BAD, rest}
        end)

        %{state | cmds: del_cmd(tag, cmds)}
      :none ->
        Logger.warn(fn ->
          "unknown tag: #{tag}"
        end)
        state
    end
  end

  defp get_cmd(tag, cmds) do
    :gb_trees.lookup(tag, cmds)
  end

  defp del_cmd(tag, cmds) do
    :gb_trees.delete(tag, cmds)
  end

  defp put_cmd(tag, cmd, cmds) do
    :gb_trees.insert(tag, cmd, cmds)
  end

  defp get_callback(name, opts, default \\ fn x -> x end) do
    Keyword.get(opts, name, default)
  end
end
