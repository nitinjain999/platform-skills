# Claude Code delegation probe

Status: Draft

`doctor` reads `fixture.json` and reports `delegation verified: yes` only when
**all** of these hold:

1. `delegation_verified` is `true`.
2. `client_version` equals the currently installed `claude --version`.
3. `probe_version` equals the version `doctor` expects.

Any mismatch — including a client upgrade — reports `no (runtime fixture
required)`. A stale fixture is not weaker evidence, it is no evidence: the
behaviour it recorded belonged to a different build.

The shipped `fixture.json` is deliberately **un-run**: `delegation_verified` is
`false` and every observation is `null`. This repository has not run a live
session, so claiming otherwise would be the exact error this gate exists to
prevent. Run `run-probe.sh` on your own machine to populate it.

Why questions 1 and 2 are not automated: distinguishing a real subagent dispatch
from the main agent answering in the worker's voice, and confirming the parent
conversation was not carried in, both require reading a transcript. An automated
check that only confirmed "a response came back" would pass in both cases, which
is precisely the failure mode that made an earlier revision of this design claim
Copilot CLI delegation worked.
