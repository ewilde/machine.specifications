require 'rake'
require 'fileutils'
require 'configatron'
Dir.glob(File.join(File.dirname(__FILE__), 'tools/Rake/*.rb')).each do |f|
  require f
end
include FileUtils

project = "Machine.Specifications"
mspec_options = []

task :configure do
  version = ENV.include?('version') ? ENV['version'].to_sym : :net_35
  target = ENV.include?('target') ? ENV['target'] : 'Debug'
  
  build_config = {
    :net_35 => {
      :version => 'v3.5',
      :project => project,
      :compileTarget => target,
      :outDir => "Build/net-3.5/#{target}/",
      :packageName => "Distribution/#{project}-net-3.5-#{target}.zip",
      :nunit_framework => "net-3.5"
    },
    :net_40 => {
      :version => 'v4\Full',
      :project => "#{project}-2010",
      :compileTarget => "#{target} .NET 4.0".escape,
      :outDir => "Build/net-4.0/#{target}/",
      :packageName => "Distribution/#{project}-net-4.0-#{target}.zip",
      :nunit_framework => "net-4.0.30319",
      :other_clr_projects => {
        :version => 'v3.5',
        :target => target,
        :outDir => "Build/net-3.5/#{target}/",
        :projects => [ 'Machine.Specifications.Reporting.Specs', 'Machine.Specifications.ReSharperRunner.5.0' ],
        :artifacts => [ '**/Machine.Specifications.Reporting.Templates.dll', 'Machine.Specifications.ReSharperRunner.5.0.*' ]
        }
    }
  }

  configatron.configure_from_hash build_config[version]
  configatron.protect_all!
  puts configatron.inspect
end

Rake::Task["configure"].invoke

desc "Build and run specs"
task :default => [ "build", "tests:run", "specs:run" ]

desc "Clean"
task :clean do
  MSBuild.compile \
    :project => "Source/#{configatron.project}.sln",
    :version => configatron.version,
    :properties => {
      :Configuration => configatron.compileTarget
    },
    :switches => {
      :target => 'Clean'
    }

  rm_f configatron.packageName
  rm_rf "Build"
end

desc "Build"
task :build do
  MSBuild.compile \
    :project => "Source/#{configatron.project}.sln",
    :version => configatron.version,
    :properties => {
      :Configuration => configatron.compileTarget
    }

  if configatron.exists?(:other_clr_projects)
    # Compile some projects for another CLR and pull their artifacts.
    configatron.other_clr_projects.projects.each do |project|
      MSBuild.compile \
        :project => "Source/#{project}/#{project}.csproj",
        :version => configatron.other_clr_projects.version,
        :properties => {
          :Configuration => configatron.other_clr_projects.target
        }
    end

    configatron.other_clr_projects.artifacts.each do |artifact|
      FileList \
        .new(File.join(configatron.other_clr_projects.outDir, artifact)) \
        .copy_hierarchy \
          :source_dir => configatron.other_clr_projects.outDir,
          :target_dir => configatron.outDir
    end
  end
end

desc "Rebuild"
task :rebuild => [ :clean, :build ]

namespace :specs do
  task :view => :run do
    system "start Specs/#{configatron.project}.Specs.html"
  end

  task :run do
    puts 'Running Specs...'
    specs = ["Machine.Specifications.Specs.dll", "Machine.Specifications.Reporting.Specs.dll", "Machine.Specifications.ConsoleRunner.Specs.dll"].map {|spec| "#{configatron.outDir}/Tests/#{spec}"}
    sh "#{configatron.outDir}/mspec.exe", "--html", "Specs/#{configatron.project}.Specs.html", "-x", "example", *(mspec_options + specs)
    puts "Wrote specs to Specs/#{configatron.project}.Specs.html, run 'rake specs:view' to see them"
  end
end

namespace :tests do
  task :run do
    # As a temporary fix until NUnit /really/ supports running on the CLR 4, copy the config file for the selected framework.
	cp "Tools/NUnit/nunit-console-x86.exe.config.#{configatron.nunit_framework}", "Tools/NUnit/nunit-console-x86.exe.config"
	
	puts 'Running NUnit tests...'
    tests = ["Machine.Specifications.Tests.dll"].map {|test| "#{configatron.outDir}/Tests/#{test}"}
    runner = NUnitRunner.new :platform => 'x86', :results => "Specs", :clr_version => configatron.nunit_framework
    runner.executeTests tests

    if File.exists? "#{configatron.outDir}/Tests/Gallio/Machine.Specifications.TestGallioAdapter.3.1.Tests.dll"
		puts 'Running Gallio tests...'
		sh "Tools/Gallio/v3.1.397/Gallio.Echo.exe", "#{configatron.outDir}/Tests/Gallio/Machine.Specifications.TestGallioAdapter.3.1.Tests.dll", "/plugin-directory:#{configatron.outDir}", "/r:Local"
	end
  end
end

desc "Open solution in VS"
task :sln do
  Thread.new do
    system "devenv Source/#{configatron.project}.sln"
  end
end

desc "Packages the build artifacts"
task :package => [ "rebuild", "tests:run", "specs:run" ] do
  rm_f configatron.packageName
  
  cp 'License.txt', configatron.outDir
  cp_r 'Distribution/Specifications/.', configatron.outDir
  
  sz = SevenZip.new \
    :tool => 'Tools/7-Zip/7za.exe',
    :zip_name => configatron.packageName

  Dir.chdir(configatron.outDir) do
    sz.zip :files => FileList.new('**/*').exclude('*.InstallLog').exclude('*.InstallState').exclude('Generation').exclude('Tests')
  end
end

desc "TeamCity build"
task :teamcity => [ :teamcity_environment, :package ]

desc "Sets up the TeamCity environment"
task :teamcity_environment do
  mspec_options.push "--teamcity"
end