defmodule IMAP.Commands do
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

  def cmd_to_data(internal) do
    Enum.intersperse(cmd_to_list(internal), " ") ++ ["\r\n"]
  end

  def cmd_to_list({:login, {:plain, username, password}}) do
    ["LOGIN", username, password]
  end

  def cmd_to_list({:uid, cmd}) do
    ["UID" | cmd_to_list(cmd)]
  end

  def cmd_to_list(:list) do
    ["LIST", "\"\"", "%"]
  end

  def cmd_to_list({:list, ref, match}) do
    ["LIST", ref, match]
  end

  def cmd_to_list({:status, mailbox}) do
    ["STATUS", quote_wrap_binary(mailbox)]
  end

  def cmd_to_list({:status, mailbox, items}) do
    ["STATUS", quote_wrap_binary(mailbox), items]
  end

  def cmd_to_list({:search, terms}) do
    ["SEARCH" | terms]
  end

  def cmd_to_list({:rename, existing, new}) do
    ["RENAME", quote_wrap_binary(existing), quote_wrap_binary(new)]
  end

  def cmd_to_list({:fetch, seq}) do
    cmd_to_list({:fetch, seq, "full"})
  end

  def cmd_to_list({:fetch, seq, data}) do
    ["FETCH", seqset_to_list(seq), list_to_imap_list(data)]
  end

  def cmd_to_list({cmd, mailbox})
  when cmd in [:select, :examine, :delete, :subscribe, :unsubscribe] do
    [atom_to_cmd(cmd), quote_wrap_binary(mailbox)]
  end

  def cmd_to_list(cmd)
  when cmd in [:noop, :idle, :done, :close, :expunge, :logout, :capability] do
    [atom_to_cmd(cmd)]
  end

  def atom_to_cmd(cmd) do
    cmd
    |> to_string()
    |> String.upcase()
  end

  def quote_wrap_binary(bin), do: <<?", bin::binary, ?">>

  def list_to_imap_list(list) when is_list(list) do
    ["(" | Enum.intersperse(" ", list)] ++ [")"]
  end

  def list_to_imap_list(term) do
    term
  end

  def seqset_to_list([head | tail]) do
    Enum.reduce(tail, head, fn(id, acc) ->
      <<acc::binary, ?,, :erlang.integer_to_binary(id)::binary>>
    end)
  end

  def seqset_to_list({nil, stop}) do
    ":" <> :erlang.integer_to_binary(stop)
  end

  def seqset_to_list({:*, stop}) do
    "*:" <> :erlang.integer_to_binary(stop)
  end

  def seqset_to_list({start, nil}) do
    :erlang.integer_to_binary(start) <> ":"
  end

  def seqset_to_list({start, :*}) do
    :erlang.integer_to_binary(start) <> ":*"
  end

  def seqset_to_list({start, stop}) do
    :erlang.integer_to_binary(start) <> ":" <> :erlang.integer_to_binary(stop)
  end

  def seqset_to_list(:*) do
    "*"
  end

  def seqset_to_list(item) do
    :erlang.integer_to_binary(item)
  end
end
