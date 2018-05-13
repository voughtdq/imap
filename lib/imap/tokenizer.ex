defmodule IMAP.Tokenizer do
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

  defstruct [token_state: {"", nil}, parse_state: {[], []}]

  def decode_line(data) do
    decode_line({data, nil}, {[],[]})
  end

  def decode_line({data, state}, {buffer, acc}) do
    case tokenize(data, state) do
      {nil, data, state} ->
        {nil, {data, state}, {buffer, acc}}

      {tokens, data, state} ->
        {line, buffer, acc} = parse(buffer ++ tokens, acc)
        {line, {data, state}, {buffer, acc}}
    end
  end

  def tokenize(data) do
    tokenize(data, [], pop_token(data))
  end

  def tokenize(data, state) do
    tokenize(data, [], pop_token(data, state))
  end

  def tokenize(_data, tokens, {nil, rest, state}) do
    {:lists.reverse(tokens), rest, state}
  end

  def tokenize(data, tokens, {token, rest, state}) do
    tokenize(data, [token | tokens], pop_token(rest, state))
  end

  def pop_token(data, state \\ nil)

  def pop_token("", state) do
    {nil, "", state}
  end

  def pop_token(" " <> rest, nil) do
    pop_token(rest, nil)
  end

  def pop_token("\r\n" <> rest, nil) do
    {:crlf, rest, nil}
  end

  def pop_token("NIL" <> rest, nil) do
    {:NIL, rest, nil}
  end

  def pop_token("(" <> rest, nil) do
    {:'(', rest, nil}
  end

  def pop_token(")" <> rest, nil) do
    {:')', rest, nil}
  end

  def pop_token("[" <> rest, nil) do
    {:'[', rest, nil}
  end

  def pop_token("]" <> rest, nil) do
    {:']', rest, nil}
  end

  # numbers

  def pop_token(<<c, _rest::binary>> = data, {:number, acc})
  when c in [?\s, ?(, ?), ?[, ?]] do
    {:erlang.binary_to_integer(acc), data, nil}
  end

  def pop_token("\r\n" <> _rest = data, {:number, acc}) do
    {:erlang.binary_to_integer(acc), data, nil}
  end

  def pop_token(" " <> rest, {:number, acc}) do
    {:erlang.binary_to_integer(acc), rest, nil}
  end

  def pop_token(<<d, rest::binary>>, {:number, acc})
  when d >= 48 and d < 58 do
    pop_token(rest, {:number, <<acc::binary, d>>})
  end

  def pop_token(<<d, rest::binary>>, nil)
  when d >= 48 and d < 58 do
    pop_token(rest, {:number, <<d>>})
  end

  def pop_token(<<c, rest::binary>>, {:number, acc})
  when c >= 35 and c < 123 do
    pop_token(rest, {:atom, <<acc::binary, c>>})
  end

  # atom

  def pop_token(<<c, _rest::binary>> = data, {:atom, acc})
  when c in [?\s, ?(, ?), ?[, ?]] do
    {acc, data, nil}
  end

  def pop_token("\r\n" <> _rest = data, {:atom, acc}) do
    {acc, data, nil}
  end

  def pop_token(<<c, rest::binary>>, nil)
  when c >= 35 and c < 123 do
    pop_token(rest, {:atom, <<c>>})
  end

  def pop_token(<<c, rest::binary>>, {:atom, acc})
  when c >= 35 and c <123 do
    pop_token(rest, {:atom, <<acc::binary, c>>})
  end

  # literals

  def pop_token("{" <> rest, nil) do
    pop_token(rest, {:literal, ""})
  end

  def pop_token("}\r\n" <> rest, {:literal, acc}) do
    pop_token(rest, {:literal, :erlang.binary_to_integer(acc), ""})
  end

  def pop_token(<<d, rest::binary>>, {:literal, acc})
  when d >= 48 and d < 58 do
    pop_token(rest, {:literal, <<acc::binary, d>>})
  end

  def pop_token(bin, {:literal, bytes, acc})
  when is_integer(bytes) do
    case bin do
      <<literal::binary-size(bytes), rest::binary>> ->
        {{:string, <<acc::binary, literal::binary>>}, rest, nil}
      _ ->
        pop_token("", {:literal, bytes - byte_size(bin), <<acc::binary, bin::binary>>})
    end
  end

  # quoted strings

  def pop_token(<<?", rest::binary>>, nil) do
    pop_token(rest, {:quoted, <<>>})
  end

  def pop_token(<<?\\, c, rest::binary>>, {:quoted, acc}) do
    pop_token(rest, {:quoted, <<acc::binary, c>>})
  end

  def pop_token(<<?", rest::binary>>, {:quoted, acc}) do
    {{:string, acc}, rest, nil}
  end

  def pop_token(<<?\r, ?\n, _rest::binary>>, {:quoted, _acc}) do
    throw({:error, :crlf_in_quoted})
  end

  def pop_token(<<c, rest::binary>>, {:quoted, acc}) do
    pop_token(rest, {:quoted, <<acc::binary, c>>})
  end

  def pop_token(bin, _) do
    {nil, bin, nil}
  end

  def parse(tokens, acc \\ [])

  def parse([], acc) do
    {nil, [], acc}
  end

  def parse([:crlf | rest], acc) do
    {:lists.reverse(acc), rest, []}
  end

  def parse([:'(' | rest] = tokens, acc) do
    case parse(rest) do
      {nil, _, _} ->
        {nil, tokens, acc}
      {list, rest, []} ->
        parse(rest, [list | acc])
    end
  end

  def parse([:')' | rest], acc) do
    {:lists.reverse(acc), rest, []}
  end

  def parse([token | rest], acc) do
    parse(rest, [token | acc])
  end
end
