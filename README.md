# IMAP

This is a port
of the [switchboard](https://github.com/MainframeHQ/switchboard)
`imap` client to Elixir.

* The GenServer state indicates when it is in continuation mode
* The parsing code has been split into three separate modules
* The switchboard specific code has been removed

This library isn't ready for general use and breaking changes are likely.

## Installation

The package can be installed by adding `imap` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:imap, git: "voughtdq/imap"}
  ]
end
```
