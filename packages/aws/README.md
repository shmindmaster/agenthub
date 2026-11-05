# AH-AWS

Run AWS commands and read AWS documentation through the official AWS MCP server, using the fleet's approved AWS profile. Starts one local proxy for a session, so install it only on hosts that do AWS work.

A thin wrapper: one skill and one server, no hooks. Hosts with a clean native plugin for this service use that instead. `registry/mcps.json` records which plugin owns the server on each host.
