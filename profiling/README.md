# Profiling

Two measurements of the server SDK, each against a local SDK server, so neither needs a server SDK key or the
network. They are measurements, not checks: their numbers depend on the machine, so `make check-all` runs neither.

```sh
make profile               # what an init, a read and a payload cost
make profile-fork-per-job  # what forking for each background job costs
```

Both print the Ruby version and the machine first. Quote those two with any number you report.

## What a read costs

[`benchmark.rb`](benchmark.rb) holds a client on a full payload of 200 configs, each with two conditional rules, on a
trait and on segments, and a percentage rollout ([`workload.rb`](workload.rb)), and measures:

- **init against the local server**: from the call to `init` to its return, for 50 clients one after another. It
  covers the connection, the first payload and its handlers, and nothing of a real network.
- **get_value on one thread**: 200,000 reads for 500 contexts, each read evaluating the rules, recording the
  evaluation for telemetry and calling the `config_evaluated` handlers, of which there are none.
- **get_value on 16 threads at once**: the same 200,000 reads split between 16 threads. Ruby runs one thread at a
  time, so the reads a second in all should match the single thread. A lower number means the threads wait for
  each other on a lock.
- **taking in a full payload**: from the local server's write of a payload to the `configs_updated` handler, for
  200 payloads.

Run it under YJIT with `RUBYOPT=--yjit make profile`.

## What forking for each job costs

[`fork_per_job.rb`](fork_per_job.rb) measures an application that forks for each background job, as Resque does. A
parent with an initialized client forks 200 times, one after another, and each forked process runs one job and
leaves with `exit!`, as Resque's forked processes do. It reports, for each kind of job, how long a job took from
`fork` to exit, how many streams the SDK server opened for the forked processes and how long each stayed open, and
how many telemetry reports and evaluations it received. Two parents without a client give the numbers to compare
with.

The jobs:

- one that reads a config and exits at once;
- one that reads a config and works for 50 ms;
- one that reads a config, works for 50 ms and calls `close` before it exits.
