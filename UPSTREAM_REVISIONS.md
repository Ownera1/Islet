# Upstream references

- boring.notch: https://github.com/TheBoredTeam/boring.notch @ `e2654ee41b0b9aee72c5a8113a11ab855896d6e6`
- CodeIsland: https://github.com/wxtsky/CodeIsland @ `b444ae28551e607dd7c66953343b9bb50c78b63d`
- CodexBar: https://github.com/steipete/CodexBar @ `7180cf777e04b27c78394e5c914cbe442a0f794a`

CodeIslandCore and the CLI bridge/Pi extension are adapted from CodeIsland (MIT).
The JSON minimal editor and native Markdown renderer are also adapted from CodeIsland.
Core-only source files remain vendored for compatibility; the integration only installs and accepts
Pi, Codex, Claude Code, ZCode, and Google Antigravity.

Antigravity quota schemas, the version-gated CLI report strategy, and Darwin process/port
enumeration are adapted from CodexBar (MIT). No CodexBar UI or shared credentials store is bundled.

Local integration changes live in `Packages/NotchIntegrations`, `boringNotch/Integrations`,
`boringNotch/IntegrationResources`, and the integration files of `BoringNotchXPCHelper`.
The upstream main app remains sandboxed; the upstream helper retains its existing entitlements.

Distribution uses the independent name Islet, bundle identifier
`com.ownera1.agentusagenotch`, helper identifier `com.ownera1.agentusagenotch.helper`,
and GitHub Releases instead of the upstream Sparkle feed. Minimum macOS is 15 to
match the included MediaRemoteAdapter. The original deployment/localization workflows
are replaced by a read-only integration build/test workflow.
