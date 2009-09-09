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

require File.join(File.dirname(__FILE__), '../spec_helpers')

describe OSGi::Registry do

  it 'should be possible to set containers from the Buildr settings' do
    yaml = {"osgi" => ({"containers" => ["myContainer"]})}
    write 'home/.buildr/settings.yaml', yaml.to_yaml
    define("foo").osgi.registry.containers.should == ["myContainer"]
  end
  
  it 'should be accessible from a project' do
    define('foo').osgi.registry.should be_instance_of(OSGi::Registry)
  end
  
  
  
  it 'should be possible to set the containers from the OSGi environment variables' do
    ENV['OSGi'] = "foo;bar"
    define('foo').osgi.registry.containers.should == ["foo","bar"]
  end
  
  it 'should be possible to modify the containers in the registry before the resolved_instances method is called' do
    foo = define('foo')
    lambda {foo.osgi.registry.containers << "hello"}.should_not raise_error
    lambda {foo.osgi.registry.containers = ["hello"]}.should_not raise_error
  end
  
  it 'should throw an exception when modifying the containers in the registry after the resolved_instances method is called' do
    foo = define('foo')
    foo.osgi.registry.resolved_containers
    lambda {foo.osgi.registry.containers << "hello"}.should raise_error(TypeError)
    lambda {foo.osgi.registry.containers = ["hello"]}.should raise_error(RuntimeError, /Cannot set containers, containers have been resolved already/)
  end
end