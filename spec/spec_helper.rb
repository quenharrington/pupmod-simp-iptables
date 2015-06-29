require 'pathname'
require 'rspec-puppet'
require 'puppetlabs_spec_helper/module_spec_helper'

require 'simp/rspec-puppet-facts'
include Simp::RspecPuppetFacts

# RSpec Material

def mod_site_pp(content)
  File.open(@orig_site_pp,'w'){|f| f.write(content) }
end

fixture_path = File.expand_path(File.join(__FILE__, '..', 'fixtures'))
module_name = File.basename(File.expand_path(File.join(__FILE__,'../..')))

# Add fixture lib dirs to LOAD_PATH. Work-around for PUP-3336
if Puppet.version < "4.0.0"
  Dir["#{fixture_path}/modules/*/lib"].entries.each do |lib_dir|
    $LOAD_PATH << lib_dir
  end
end

default_hiera_config =<<-EOM
---
:backends:
  - "rspec"
  - "yaml"
:yaml:
  :datadir: "stub"
:hierarchy:
  # This is a variable that you can set in your test classes to ensure that the
  # targeted YAML file gets loaded in the fixtures.
  - "%{custom_hiera}"
  - "%{module_name}"
  - "default"
EOM

# This can be used from inside your spec tests to set the testable environment.
# You can use this to stub out an ENC.
#
# Example:
#
# context 'in the :foo environment' do
#   let(:environment){:foo}
#   ...
# end
#
def set_environment(environment = :production)
    RSpec.configure { |c| c.default_facts['environment'] = environment.to_s }
end

# This can be used from inside your spec tests to load custom hieradata within
# any context.
#
# Example:
#
# describe 'some::class' do
#   context 'with version 10' do
#     let(:hieradata){ "#{class_name}_v10" }
#     ...
#   end
# end
#
# Then, create a YAML file at spec/fixtures/hieradata/some__class_v10.yaml.
#
# Hiera will use this file as it's base of information stacked on top of
# 'default.yaml' and <module_name>.yaml per the defaults above.
#
# Note: Any colons (:) are replaced with underscores (_) in the class name.
def set_hieradata(hieradata)
    RSpec.configure { |c| c.default_facts['custom_hiera'] = hieradata }
end


if not File.directory?(File.join(fixture_path,'hieradata')) then
  FileUtils.mkdir_p(File.join(fixture_path,'hieradata'))
end

if not File.directory?(File.join(fixture_path,'modules',module_name)) then
  FileUtils.mkdir_p(File.join(fixture_path,'modules',module_name))
end

Dir.chdir(File.join(fixture_path,'modules',module_name)) do
  ['manifests','templates','lib'].each do |tgt|
    if not File.symlink?(tgt) then
      FileUtils.ln_sf("../../../../#{tgt}",tgt)
    end
  end
end


RSpec.configure do |c|
  # ENC-style environment facts
  c.default_facts = {
#    :fqdn           => 'production.rspec.test.localdomain',
    :path           => '/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin',
    :concat_basedir => '/tmp'
  }

  c.mock_framework = :rspec
  c.mock_with :mocha

  c.module_path = File.join(fixture_path, 'modules')
  c.manifest_dir = File.join(fixture_path, 'manifests')

  c.hiera_config = File.join(fixture_path,'hieradata','hiera.yaml')

  if true
    # Supress useless backtrace noise
    # START BKGRND
    backtrace_exclusion_patterns = [
      /spec_helper/,
      /gems/
    ]

    if c.respond_to?(:backtrace_exclusion_patterns)
      c.backtrace_exclusion_patterns = backtrace_exclusion_patterns
    elsif c.respond_to?(:backtrace_clean_patterns)
      c.backtrace_clean_patterns = backtrace_exclusion_patterns
    end
    # END BKGRND
  end

  # create the default hierarchy file
  c.before(:all) do
    data = YAML.load(default_hiera_config)
    data[:yaml][:datadir] = File.join(fixture_path, 'hieradata')

    File.open(c.hiera_config, 'w') do |f|
      f.write data.to_yaml
    end
  end

  c.before(:each) do
    if defined?(environment)
      set_environment(environment)
    end

    if defined?(hieradata)
      set_hieradata(hieradata.gsub(':','_'))
    elsif defined?(class_name)
      set_hieradata(class_name.gsub(':','_'))
    end
  end
end

Dir.glob("#{RSpec.configuration.module_path}/*").each do |dir|
  begin
    Pathname.new(dir).realpath
  rescue
    fail "ERROR: The module '#{dir}' is not installed. Tests cannot continue."
  end
end
