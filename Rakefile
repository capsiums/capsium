# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :rbs do
  desc "Validate the RBS signatures (sig/)"
  task :validate do
    sh "bundle exec rbs -I sig validate"
  end
end

task default: %i[spec rubocop rbs:validate]
