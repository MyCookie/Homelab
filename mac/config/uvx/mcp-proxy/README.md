# MCP

Put the `config.json` in `~/.config/uvx/mcp-proxy/`. [Install](https://docs.astral.sh/uv/getting-started/installation/) `uvx`.

As configured, the servers are available at: `http://localhost:8001/servers/${name}/mcp`.

When adding them via the `llama.cpp` webui, you may need to enable the "User llama-server proxy" option. The option appears after adding the server and letting it error out first. This option requires the `llama-server` to be launched with `--webui-mcp-proxy`.