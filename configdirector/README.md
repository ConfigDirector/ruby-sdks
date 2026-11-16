# configdirector

[![Gem Version][gem-badge]][gem]

This gem installs [configdirector-server-sdk](https://rubygems.org/gems/configdirector-server-sdk), the Ruby server SDK for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with JSON Schema validation and safe renames of live flags. It holds no code of its own: it exists so that `gem install configdirector` and `gem "configdirector"` in a `Gemfile` give you the SDK.

Prefer naming the SDK itself, which is also where its versions and changelog are:

```bash
bundle add configdirector-server-sdk
```

Either way the SDK is required as `configdirector`:

```ruby
require "configdirector"

client = ConfigDirector.create_client(ENV.fetch("CONFIGDIRECTOR_SERVER_KEY"))
```

See the [README of the SDK](https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector-server-sdk) and the [official documentation](https://docs.configdirector.com/sdks/server/ruby).

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[gem-badge]: https://img.shields.io/gem/v/configdirector
[gem]: https://rubygems.org/gems/configdirector
