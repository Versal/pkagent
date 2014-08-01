# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "sshkey"
  s.version = "1.6.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["James Miller"]
  s.date = "2013-11-14"
  s.description = "Generate private/public SSH keypairs using pure Ruby"
  s.email = ["bensie@gmail.com"]
  s.homepage = "https://github.com/bensie/sshkey"
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubyforge_project = "sshkey"
  s.rubygems_version = "1.8.11"
  s.summary = "SSH private/public key generator in Ruby"

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rake>, [">= 0"])
    else
      s.add_dependency(%q<rake>, [">= 0"])
    end
  else
    s.add_dependency(%q<rake>, [">= 0"])
  end
end
