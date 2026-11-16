# frozen_string_literal: true

require "rubygems/package"

DOCUMENTS_EVERY_GEM_SHIPS = ["CHANGELOG.md", "LICENSE", "README.md"].freeze

def ruby_code?(file) = file.start_with?("lib/") && file.end_with?(".rb")

def rbs_signature?(file) = file.start_with?("sig/") && file.end_with?(".rbs")

def needed_by_an_application?(file)
  ruby_code?(file) || rbs_signature?(file) || file == ".yardopts" || DOCUMENTS_EVERY_GEM_SHIPS.include?(file)
end

def problems_of_files_no_application_needs(files)
  files.reject { |file| needed_by_an_application?(file) }.map do |file|
    "holds #{file}, which an application does not need. A gem ships lib/**/*.rb, sig/**/*.rbs, .yardopts, " \
      "#{DOCUMENTS_EVERY_GEM_SHIPS.join(", ")} and nothing else: see the files of its gemspec."
  end
end

def problems_of_missing_documents(files)
  (DOCUMENTS_EVERY_GEM_SHIPS - files).map { |document| "lacks #{document}." }
end

def problems_of_code_without_signatures(files)
  return [] if files.none? { |file| ruby_code?(file) } || files.any? { |file| rbs_signature?(file) }

  ["holds Ruby code and no RBS signatures under sig/."]
end

def problems_of_owners_without_multi_factor_authentication(metadata)
  return [] if metadata["rubygems_mfa_required"] == "true"

  ["does not set rubygems_mfa_required to \"true\" in its metadata, so RubyGems would let an owner without " \
   "multi-factor authentication push and yank it."]
end

def problems_of(package)
  files = package.contents

  problems_of_files_no_application_needs(files) + problems_of_missing_documents(files) +
    problems_of_code_without_signatures(files) +
    problems_of_owners_without_multi_factor_authentication(package.spec.metadata)
end

problems_by_gem_file = ARGV.to_h { |gem_file| [File.basename(gem_file), problems_of(Gem::Package.new(gem_file))] }

problems_by_gem_file.each do |gem_file, problems|
  problems.each { |problem| warn "#{gem_file} #{problem}" }
end

exit 1 if problems_by_gem_file.values.any?(&:any?)
