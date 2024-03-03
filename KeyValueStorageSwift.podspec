Pod::Spec.new do |spec|
  spec.name         = "KeyValueStorageSwift"
  spec.version      = "2.0.0"
  
  spec.summary      = "Key-value storage written in Swift."
  spec.description  = "An elegant, multipurpose key-value storage, compatible with all Apple platforms."
  spec.homepage     = "https://github.com/narek-sv/KeyValueStorage"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Narek Sahakyan" => "narek.sv.work@gmail.com" }
  
  spec.swift_version = "5.9"
  spec.ios.deployment_target = "13.0"
  spec.osx.deployment_target = "10.15"
  spec.watchos.deployment_target = "6.0"
  spec.tvos.deployment_target = "13.0"
  
  spec.source       = { :git => "https://github.com/narek-sv/KeyValueStorage.git", :tag => "v2.0.0" }
  spec.source_files = "Sources/**/*"
  
  spec.test_spec 'Tests' do |test_spec|
    test_spec.source_files = "Tests/**/*"
  end
  
end
