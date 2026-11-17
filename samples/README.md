# Sample apps

Small, self-contained applications showing how to use the ConfigDirector Ruby gems with different web frameworks,
grouped by the gem they demonstrate.

## [configdirector-server-sdk](configdirector-server-sdk/)

| Sample | Framework | Description |
|---|---|---|
| [rails/](configdirector-server-sdk/rails/) | [Rails](https://rubyonrails.org) on [Puma](https://puma.io) | Minimal API app in cluster mode: one client per process, created on first use, and per-request evaluation |

Each sample is an independent Bundler project with its own `Gemfile` and `Gemfile.lock`, and installs its gems into
its own `vendor/bundle`. A sample names a released version of the gem it shows, the way an application does.
`make samples` runs the suite of every sample against that release, and `make samples-local` against the gems as
they are in your checkout.

To run one:

```bash
cd samples/configdirector-server-sdk/rails
bundle install
bundle exec puma
```

> The samples need a real server SDK key to resolve configs. Without one ConfigDirector refuses the connection, the
> client stays not ready and every config falls back to the in-code default value the sample passes in, which is
> also what a production app sees when it cannot reach ConfigDirector.
