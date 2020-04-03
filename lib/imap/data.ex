defmodule IMAP.Data do
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

  def clean_props({:*, [_id, "FETCH", params]}) do
    clean_props(params, %{})
  end

  def clean_props([], acc) do
    {:fetch, acc}
  end

  def clean_props(["UID", uid | rest], acc) do
    clean_props(rest, Map.put(acc, "uid", uid))
  end

  def clean_props(["FLAGS", flags | rest], acc) do
    clean_props(rest, Map.put(acc, "flags", flags))
  end

  def clean_props(["INTERNALDATE", {:string, internal_date} | rest], acc) do
    clean_props(rest, Map.put(acc, "internal_date", internal_date))
  end

  def clean_props(["RFC822.SIZE", rfc822_size | rest], acc) do
    clean_props(rest, Map.put(acc, "rfc822_size", rfc822_size))
  end

  def clean_props(["ENVELOPE",
          [
            {:string, date},
            {:string, subject},
            from,
            sender,
            reply_to,
            to,
            cc,
            bcc,
            in_reply_to,
            {:string, message_id}
          ]
          | rest
        ],
        acc
      ) do
    envelope = %{
      "date" => date,
      "subject" => subject,
      "from" => clean_addresses(from),
      "sender" => clean_addresses(sender),
      "reply_to" => clean_addresses(reply_to),
      "to" => clean_addresses(to),
      "cc" => clean_addresses(cc),
      "bcc" => clean_addresses(bcc),
      "in_reply_to" => clean_addresses(in_reply_to),
      "message_id" => message_id
    }

    clean_props(rest, Map.put(acc, "envelope", envelope))
  end

  def clean_props(["BODY", :"[", :"]", {:string, body} | rest], acc) do
    clean_props(rest, Map.put(acc, "body", body))
  end

  def clean_props(["BODY", :"[", "TEXT", :"]", {:string, body} | rest], acc) do
    clean_props(rest, Map.put(acc, "text_body", body))
  end

  def clean_props(["BODY", '[', part, :"]", {:string, body} | rest], acc) do
    clean_props(rest, Map.put(acc, "body."<>part, body))
  end

  def clean_props(["BODY", body | rest], acc) do
    clean_props(rest, Map.put(acc, "body", clean_body(body)))
  end

  def clean_body(body) do
    clean_body(body, [])
  end

  def clean_body(
        [
          {:string, type},
          {:string, subtype},
          params,
          id,
          description,
          {:string, encoding},
          size | _
        ],
        []
      ) do
    %{
      "type" => type,
      "subtype" => subtype,
      "params" => clean_imap_props(params),
      "id" => id,
      "description" => description,
      "encoding" => encoding,
      "size" => size
    }
  end

  def clean_body([{:string, multipart_type}], acc) do
    %{
      "multipart" => multipart_type,
      "parts" => Enum.reverse(acc)
    }
  end

  def clean_body([head | tail], acc) do
    clean_body(tail, [clean_body(head) | acc])
  end

  def clean_imap_props(props) do
    clean_imap_props(props, %{})
  end

  def clean_imap_props([], acc) do
    acc
  end

  def clean_imap_props([{:string, key}, {:string, value} | rest], acc) do
    clean_imap_props(rest, Map.put(acc, key, value))
  end

  def clean_addresses(:NIL) do
    []
  end

  def clean_addresses({:string, ""}) do
    []
  end

  def clean_addresses({:string, address}) do
    [{:address, [{:email, strip_address(address)}]}]
  end

  def clean_addresses(addresses) do
    clean_addresses(addresses, [])
  end

  def clean_addresses([], acc) do
    Enum.reverse(acc)
  end

  def clean_addresses([[raw_name, _, {:string, mailbox}, host] | rest], acc) do
    address = build_address(mailbox, host)

    clean_addresses(rest, [
      {:address,
       case raw_name do
         :NIL -> [{:name, ""} | address]
         {:string, name} -> [{:name, name} | address]
       end}
      | acc
    ])
  end

  def build_address(mailbox, host) do
    domain =
      case host do
        {:string, string} -> string
        _ -> ""
      end

    [{:email, mailbox <> "@" <> domain}]
  end

  def strip_address(address) when is_binary(address) do
    case {:binary.first(address), :binary.last(address)} do
      {?<, ?>} ->
        length = byte_size(address) - 2
        <<?<, stripped::binary-size(length), ?>>> = address
        stripped

      _ ->
        address
    end
  end
end
