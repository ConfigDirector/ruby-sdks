# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe "Bundler.require" do
  it "loads ConfigDirector from a Gemfile that names the gem without a require option" do
    Dir.mktmpdir do |application_directory|
      gemfile = File.join(application_directory, "Gemfile")
      File.write(gemfile, <<~GEMFILE)
        source "https://rubygems.org"

        gem "configdirector-server-sdk", path: #{File.expand_path("..", __dir__).dump}
      GEMFILE

      output, = Bundler.with_unbundled_env do
        Open3.capture2e({ "BUNDLE_GEMFILE" => gemfile }, Gem.ruby, "-e", <<~RUBY, chdir: application_directory)
          require "bundler/setup"
          Bundler.require
          print ConfigDirector.name
        RUBY
      end

      expect(output).to eq("ConfigDirector")
    end
  end
end
