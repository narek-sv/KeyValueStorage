Pod::Spec.new do |spec|
  spec.name         = "KeyValueStorageSwift"
  spec.version      = "1.1.0"
  
  spec.summary      = "Key-value storage written in Swift."
  spec.description  = "An elegant, multipurpose key-value storage, compatible with all Apple platforms."
  spec.homepage     = "https://github.com/narek-sv/KeyValueStorage"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Narek Sahakyan" => "narek.sv.work@gmail.com" }
  
  spec.swift_version = "5.6"
  spec.ios.deployment_target = "12.0"
  spec.osx.deployment_target = "10.13"
  spec.watchos.deployment_target = "4.0"
  spec.tvos.deployment_target = "12.0"
  
  spec.source       = { :git => "https://github.com/narek-sv/KeyValueStorage.git", :tag => "v1.1.0" }
  spec.source_files = "Sources/**/*"
end
