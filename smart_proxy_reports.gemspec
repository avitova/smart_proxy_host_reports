# frozen_string_literal: true
require_relative "lib/smart_proxy_reports/version"

Gem::Specification.new do |s|
  s.name = "smart_proxy_reports"
  s.version = Proxy::Reports::VERSION

  s.summary = "Foreman Host Reports processor"
  s.description = "Transform and upload Foreman host reports via REST API"
  s.authors = ["Lukas Zapletal"]
  s.email = "lukas-x@zapletalovi.com"
  s.extra_rdoc_files = ["README.md", "LICENSE"]
  s.files = Dir["{lib,settings.d,bundler.d}/**/*"] + s.extra_rdoc_files
  s.homepage = "http://github.com/theforeman/smart_proxy_reports"
  s.license = "GPL-3.0-or-later"
  s.required_ruby_version = ">= 2.5"

  s.metadata = { "rubygems_mfa_required" => "true" }
end
