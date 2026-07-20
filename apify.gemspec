# frozen_string_literal: true

require_relative "lib/apify/version"

Gem::Specification.new do |spec|
  spec.name = "apify"
  spec.version = Apify::VERSION
  spec.authors = ["Roberto Rivas"]
  spec.email = ["roberto.rivas.dev@gmail.com"]

  spec.summary = "Ruby client for Apify API v2"
  spec.description = "HTTP client for Apify actors with retry and typed errors"
  spec.homepage = "https://github.com/EmeralHQ/apify-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/EmeralHQ/apify-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/EmeralHQ/apify-ruby/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "dry-configurable", "~> 1.0"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
