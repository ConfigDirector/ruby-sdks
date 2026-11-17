# frozen_string_literal: true

gem_directory = File.expand_path(ARGV.fetch(0))
gemspec = Gem::Specification.load(File.join(gem_directory, "#{File.basename(gem_directory)}.gemspec"))

puts "eval_gemfile #{File.join(gem_directory, "Gemfile").dump}"

gemspec.runtime_dependencies.each do |dependency|
  gemspec_in_this_working_tree = File.join(File.dirname(gem_directory), dependency.name, "#{dependency.name}.gemspec")
  next if File.exist?(gemspec_in_this_working_tree)

  lower_bounds = dependency.requirement.requirements.filter_map do |operator, version|
    version if [">=", "~>"].include?(operator)
  end
  next if lower_bounds.empty?

  lowest_allowed_version = lower_bounds.max
  puts "gem #{dependency.name.dump}, #{lowest_allowed_version.to_s.dump}"
end
