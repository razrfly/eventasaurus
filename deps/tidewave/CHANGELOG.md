# Changelog

## 0.1.6 (2025-05-08)

* Bug fixes
  * fix invalid schema definition for `get_source_location` tool

## 0.1.5 (2025-05-07)

* Enhancements
  * capture compile errors in `project_eval` tool
  * allow enabling debug logs with `config :tidewave, debug: true`
  * use a single `reference` instead of separate `module` and `function` parameters in `get_source_location` tool

## 0.1.4 (2025-05-02)

* Enhancements
  * ensure Hex dependency search tool only returns package name and version to
    prevent prompt injections from package descriptions
  * make `:inspect_opts` configurable and format charlists as lists by default

## 0.1.3 (2025-05-01)

* Enhancements
  * new Igniter installer for Tidewave
  * new documentation page for Neovim
* Bug fixes
  * allow tool calls without arguments
  * properly cleanup sessions when re-using processes (only applies to Bandit)

## 0.1.2 (2025-04-30)

* Enhancements
  * Perform code reloading on shell eval
  * Support new versions of the MCP standard
  * Refute to use `iex` on `shell_eval`
  * Improve `shell_eval` description
  * Allow ipv4 mapped ipv6 address for `127.0.0.1`

## 0.1.1 (2025-04-30)

* Enhancements
  * evaluate commands in a separate process with timeout
  * handle clients that are trying to establish a connection using the new Streamable transport by replying with 405 (Method not allowed)
    as documented in the MCP specification. (we will work on adding support for the new Streamable transport in the future!)
  * small improvements to the documentation and tool descriptions

## 0.1.0 (2025-04-29)

Initial release.