# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.

# Methods added to Project for compiling, handling of resources and generating source documentation.
module OSGi
  
  module BundleCollector #:nodoc:
    
    attr_accessor :bundles
    
    # Collects the bundles associated with a project.
    # Returns them as a sorted array.
    #
    def collect(project)
      @bundles = []
      project.manifest_dependencies().each {|dep| _collect(dep, project)}
      @bundles.sort
    end
    
    # Collects the bundles associated with the bundle
    # 
    def _collect(bundle, project)
      if bundle.is_a? Bundle
        if bundle.resolve!(project)
          if !(@bundles.include? bundle)
            @bundles << bundle
            @bundles |= bundle.fragments(project)       
            (bundle.bundles + bundle.imports).each {|b|
              _collect(b, project)  
            }
          end
        end
      elsif bundle.is_a?(BundlePackage)
        bundle.resolve(project).each {|b| 
          if !(@bundles.include? b)
            @bundles << b
            (b.bundles + b.imports).each {|import|
              _collect(import, project)  
            }
          end
        }
      end
    end
    
  end
  
  class DependenciesTask < Rake::Task #:nodoc:
    include BundleCollector
    attr_accessor :project

    def initialize(*args) #:nodoc:
      super

      enhance do |task|
        dependencies = {}
        project.projects.each do |subp|
          subp_deps = collect(subp)
          if subp_deps.empty?
            warn "No OSGi dependencies found for #{subp.name}"
          else
            dependencies[subp.name] = subp_deps
          end
        end
        
        dependencies[project.name] = collect(project)
        
        Buildr::write File.join(project.base_dir, "dependencies.yml"), dependencies.to_yaml
      end
    end
  end
  
  class InstallTask < Rake::Task #:nodoc:
    include BundleCollector
    attr_accessor :project, :local

    def initialize(*args) #:nodoc:
      super

      enhance do |task|
        dependencies = []
        project.projects.each do |subp|
          dependencies |= collect(subp)
        end
        dependencies |= collect(project)
        dependencies.flatten.uniq.sort.each {|bundle|
          begin
            if File.directory?(bundle.file)
              begin
               
                tmp = File.join(Dir::tmpdir, "bundle")
                base = Pathname.new(bundle.file)
                Zip::ZipFile.open(tmp, Zip::ZipFile::CREATE) {|zipfile|
                  Dir.glob("#{bundle.file}/**/**").each do |file|
                    zipfile.add(Pathname.new(file).relative_path_from(base), file)
                  end
                }
                bundle.file = tmp
                
              rescue Exception => e
                error e.message
                trace e.backtrace.join("\n")
              end
              
            end
            
            if local
              artifact = Buildr::artifact(bundle.to_s)
              installed = Buildr.repositories.locate(artifact)
              mkpath File.dirname(installed)
              Buildr::artifact(bundle.to_s).from(bundle.file).install
              info "Installed #{installed}"
            else
              Buildr::artifact(bundle.to_s).from(bundle.file).upload
              info "Uploaded #{bundle}"
            end
          rescue Exception => e
            error "Error installing the artifact #{bundle.to_s}"
            trace e.message
            trace e.backtrace.join("\n")
          end
        }
      end
    end
  end
  
  module ProjectExtension #:nodoc:
    include Extension

    first_time do
      desc 'Evaluate OSGi dependencies and places them in dependencies.yml'
      Project.local_task('osgi:resolve:dependencies') { |name| "Resolve dependencies for #{name}" }
      desc 'Installs OSGi dependencies in the Maven local repository'
      Project.local_task('osgi:install:dependencies') { |name| "Install dependencies for #{name}" }
      desc 'Installs OSGi dependencies in the Maven local repository'
      Project.local_task('osgi:upload:dependencies') { |name| "Upload dependencies for #{name}" }
      desc 'Cleans the dependencies.yml file'
      Project.local_task('osgi:clean:dependencies') {|name| "Clean dependencies for #{name}"}
    end

    before_define do |project|
      dependencies = DependenciesTask.define_task('osgi:resolve:dependencies')
      dependencies.project = project
      install = InstallTask.define_task('osgi:install:dependencies')
      install.project = project
      install.local = true
      upload = InstallTask.define_task('osgi:upload:dependencies')
      upload.project = project
      
      
      clean = Rake::Task.define_task('osgi:clean:dependencies').enhance do
        Buildr::write File.join(project.base_dir, "dependencies.yml"), 
          project.projects.inject({}) {|hash, p| hash.merge({p.name => []})}.merge({project.name => []}).to_yaml
      end
      install.project = project
    end

    #
    # Calls the osgi:resolve:dependencies task if no dependencies.yml file is present.
    # Then reads the dependencies from dependencies.yml
    #
    def dependencies(&block)
      task('osgi:resolve:dependencies').enhance(&block).invoke if !(File.exists?("dependencies.yml"))
      dependencies =YAML.load(File.read("dependencies.yml"))
      names = [project.name] + project.projects.collect {|p| p.name}
      return dependencies.collect {|key, value| value if names.include? key}.flatten.compact.uniq
    end

    class OSGi #:nodoc:

      attr_reader :options, :registry

      def initialize(project)
        if (project.parent)
          @options = project.parent.osgi.options.dup
          @registry = project.parent.osgi.registry.dup
        end
        @options ||= Options.new
        @registry ||= ::OSGi::Registry.new
      end

      # The options for the osgi.options method
      #   package_resolving_strategy:
      #     The package resolving strategy, it should be a symbol representing a module function in the OSGi::PackageResolvingStrategies module.
      #   bundle_resolving_strategy:
      #     The bundle resolving strategy, it should be a symbol representing a module function in the OSGi::BundleResolvingStrategies module.
      class Options
        attr_accessor :package_resolving_strategy, :bundle_resolving_strategy

        def initialize
          @package_resolving_strategy = :all
          @bundle_resolving_strategy = :latest
        end

      end
    end
    
    # Makes a osgi instance available to the project.
    # The osgi object may be used to access OSGi containers
    # or set options, currently the resolving strategies.
    def osgi
      @osgi ||= OSGi.new(self)
      @osgi
    end
    
    # returns an array of the dependencies of the plugin, read from the manifest.
    def manifest_dependencies()
      return [] unless File.exists?("#{base_dir}/META-INF/MANIFEST.MF")
      as_bundle = Bundle.fromManifest(Manifest.read(File.read(File.join(project.base_dir, "META-INF/MANIFEST.MF"))), project.name)
      as_bundle.nil? ? [] : as_bundle.bundles.collect{|b| b.resolve(project)} + as_bundle.imports.collect {|i| i.resolve(project)}.flatten
    end
  end
end

module Buildr #:nodoc:
  class Project #:nodoc:
    include OSGi::ProjectExtension
  end
end