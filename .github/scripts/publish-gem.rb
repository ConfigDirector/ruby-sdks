# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

AUDIENCE_RUBYGEMS_ACCEPTS = "rubygems.org"
DRY_RUN_BY_ITS_TEXT = { "true" => true, "false" => false }.freeze

def identity_token_of_this_job(request_url, request_token)
  answer = Net::HTTP.get_response(
    URI("#{request_url}&audience=#{AUDIENCE_RUBYGEMS_ACCEPTS}"), "Authorization" => "bearer #{request_token}"
  )
  unless answer.is_a?(Net::HTTPOK)
    abort "GitHub did not give this job an identity token (HTTP #{answer.code}): #{answer.body}"
  end

  JSON.parse(answer.body).fetch("value")
end

def trusted_publisher_of_this_job(rubygems_host, identity_token, owner_id)
  answer = Net::HTTP.post(
    URI("#{rubygems_host}/api/v1/oidc/trusted_publisher/exchange_token"),
    JSON.generate({ jwt: identity_token, owner: owner_id }),
    "Content-Type" => "application/json", "Accept" => "application/json"
  )
  unless answer.is_a?(Net::HTTPSuccess)
    abort "RubyGems did not exchange the identity token of this job for a key (HTTP #{answer.code}): #{answer.body}\n" \
          "See 'When RubyGems refuses the workflow' in CONTRIBUTING.md."
  end

  JSON.parse(answer.body)
end

$stdout.sync = true

gem_file = ARGV.fetch(0)
identity_token_request_url = ENV.fetch("ACTIONS_ID_TOKEN_REQUEST_URL", "")
identity_token_request_token = ENV.fetch("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "")
owner_id = ENV.fetch("RUBYGEMS_OWNER_ID", "")
dry_run_as_given = ENV.fetch("DRY_RUN", "")
rubygems_host = ENV.fetch("RUBYGEMS_HOST", "").then { |host| host.empty? ? "https://rubygems.org" : host }

if identity_token_request_url.empty?
  abort "This job may not request an identity token from GitHub: ACTIONS_ID_TOKEN_REQUEST_URL is empty. The job " \
        "that publishes needs the permission 'id-token: write'."
end

unless owner_id.match?(/\A\d+\z/)
  abort "RUBYGEMS_OWNER_ID is '#{owner_id}', and has to be the ID, a number, of the RubyGems account that owns " \
        "the gems. It is a variable of this repository: see Releasing in CONTRIBUTING.md."
end

dry_run = DRY_RUN_BY_ITS_TEXT.fetch(dry_run_as_given) do
  abort "DRY_RUN is '#{dry_run_as_given}', and has to be true or false."
end

identity_token = identity_token_of_this_job(identity_token_request_url, identity_token_request_token)
trusted_publisher = trusted_publisher_of_this_job(rubygems_host, identity_token, owner_id)
key = trusted_publisher.fetch("rubygems_api_key")

puts "::add-mask::#{key}"
puts "RubyGems trusts this workflow as '#{trusted_publisher["name"]}', and reads the owner #{owner_id} as the " \
     "account '#{trusted_publisher["owner"]}'."

if dry_run
  puts "Dry run: #{File.basename(gem_file)} is not pushed, and the key expires unused."
  exit
end

exit 1 unless system({ "GEM_HOST_API_KEY" => key }, "gem", "push", gem_file)
