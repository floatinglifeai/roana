# MCP and LSP Setup

Status: not configured in this repo.

The repo is primarily Android/Kotlin plus iOS/Swift. Editor/build correctness
comes from Gradle/Android Studio and Xcode. There is no checked-in `.mcp.json`,
`.serena/`, `.vscode/`, or language-server config yet.

## Recommendation

Use Serena MCP as the preferred agent-facing semantic tooling when this repo
needs broad symbol-aware refactors.

Do not claim Serena is active until both are true:

1. The MCP client is configured for this repository.
2. The agent session exposes Serena tools and can activate this project.

The official Serena docs currently recommend installing with `uv`:

```bash
uv tool install -p 3.13 serena-agent
serena init
```

For quick experiments, `uvx` can run Serena from the upstream repository:

```bash
uvx -p 3.13 --from git+https://github.com/oraios/serena serena start-mcp-server --context codex --project "$PWD"
```

Prefer a deliberate setup pass before committing `.mcp.json`: Kotlin/Android and
Swift/iOS support depends on the available language-server backend, Xcode, and
Android toolchain state on the host.

References:

- https://github.com/oraios/serena
- https://oraios.github.io/serena/02-usage/020_running.html

