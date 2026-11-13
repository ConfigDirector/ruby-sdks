# frozen_string_literal: true

RSpec.describe "configdirector-server-sdk.gemspec" do
  it "packages the signatures and the file Bundler.require loads" do
    specification = Gem::Specification.load(File.expand_path("../configdirector-server-sdk.gemspec", __dir__))

    expect(specification.files).to include("sig/configdirector.rbs", "lib/configdirector-server-sdk.rb")
  end
end
