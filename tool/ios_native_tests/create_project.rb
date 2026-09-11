require 'fileutils'
require 'xcodeproj'

output = File.expand_path(ARGV.fetch(0))
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'NativeStartupTests.xcodeproj'))
target = project.new_target(:ui_test_bundle, 'NativeStartupTests', :ios, '13.0')
source = project.main_group.new_file(File.expand_path('StartupUITests.swift', __dir__))
target.source_build_phase.add_file_reference(source)
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'SWIFT_VERSION' => '5.0',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'moe.alphaly.art3m1s.startup-tests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'TARGETED_DEVICE_FAMILY' => '1,2',
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.save_as(project.path, 'NativeStartupTests', true)
