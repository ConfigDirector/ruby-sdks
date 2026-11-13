# frozen_string_literal: true

RSpec.describe "configdirector-openfeature-server-provider.gemspec" do
  it "packages the signatures and the file Bundler.require loads" do
    specification = Gem::Specification.load(
      File.expand_path("../configdirector-openfeature-server-provider.gemspec", __dir__)
    )

    expect(specification.files).to include(
      "sig/configdirector/openfeature.rbs", "lib/configdirector-openfeature-server-provider.rb"
    )
  end
end
