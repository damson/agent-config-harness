# Security

## Reporting a vulnerability

Use GitHub's private reporting: **Security → Advisories → Report a
vulnerability** on this repository. Please don't open a public issue for
anything exploitable. Maintained by one person, so acknowledgement may take a
few days — but it comes.

## Supported versions

The latest release only. Fixes land on `develop` and ship in the next release;
nothing is backported.

## Scope

What's worth reporting, and what isn't:

- **The eval gate is an advisory signal, not a security control** — the README
  says so up front. The grade comes from an LLM reading the PR author's own
  file, so "an author can steer their own grade" is a documented limitation,
  not a vulnerability.
- **The GitHub Action is where the threat model actually lives.** It runs in
  jobs holding an `ANTHROPIC_API_KEY`, so what matters most is output
  validation (nothing model-generated reaching the shell or job outputs
  unvalidated) and supply-chain pinning (the CLI installs at an exact version,
  never `latest`). Holes in either are exactly what to report.
- The shell scripts run locally, with your privileges, over your own config.
  Bugs there are ordinary issues — unless untrusted input reaches them.
