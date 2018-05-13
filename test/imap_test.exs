defmodule IMAPTest do
  use ExUnit.Case
  doctest IMAP

  test "greets the world" do
    assert IMAP.hello() == :world
  end
end
