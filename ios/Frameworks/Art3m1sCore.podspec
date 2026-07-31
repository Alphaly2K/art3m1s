Pod::Spec.new do |s|
  s.name         = 'Art3m1sCore'
  s.version      = '0.2.2'
  s.summary      = 'Art3m1s visual novel engine core'
  s.description  = 'Core game engine (art3m1s-core) compiled as a dynamic framework for iOS.'
  s.homepage     = 'https://github.com/anomalyco/art3m1s'
  s.license      = { :type => 'MIT' }
  s.author       = { 'Art3m1s' => '' }
  s.platform     = :ios, '13.0'
  s.source       = { :path => '.' }
  s.vendored_frameworks = 'art3m1s_core.xcframework'
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
