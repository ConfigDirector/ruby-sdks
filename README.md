# ConfigDirector Ruby SDKs

[![CI][ci-badge]][ci]

Ruby gems for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with JSON Schema validation and safe renames of live flags. Start free, no card required.

| Gem | RubyGems | Description |
|---|---|---|
| [configdirector-server-sdk](configdirector-server-sdk/) | [![Gem Version][sdk-badge]][sdk-rubygems] | The Ruby server SDK |
| [configdirector-openfeature-server-provider](configdirector-openfeature-server-provider/) | [![Gem Version][provider-badge]][provider-rubygems] | [OpenFeature](https://openfeature.dev) server provider, built on the server SDK |
| [configdirector](configdirector/) | [![Gem Version][bare-name-badge]][bare-name-rubygems] | Installs the server SDK, and holds no code of its own |

Each gem has its own changelog, version, and release. Pick the server SDK to use ConfigDirector directly, or the OpenFeature provider if your application reads flags through the OpenFeature API.

## Sample apps

Small, runnable applications live under [`samples/`](samples/), grouped by the gem they demonstrate: for the server
SDK, a Rails application served by Puma in cluster mode.

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/ruby-sdks/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/ConfigDirector/ruby-sdks/actions/workflows/ci.yml
[sdk-badge]: https://img.shields.io/gem/v/configdirector-server-sdk
[sdk-rubygems]: https://rubygems.org/gems/configdirector-server-sdk
[provider-badge]: https://img.shields.io/gem/v/configdirector-openfeature-server-provider
[provider-rubygems]: https://rubygems.org/gems/configdirector-openfeature-server-provider
[bare-name-badge]: https://img.shields.io/gem/v/configdirector
[bare-name-rubygems]: https://rubygems.org/gems/configdirector
