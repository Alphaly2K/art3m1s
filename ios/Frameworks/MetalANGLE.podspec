Pod::Spec.new do |s|
  s.name         = 'MetalANGLE'
  s.version      = '0.1.0'
  s.summary      = 'ANGLE (Almost Native Graphics Layer Engine) with Metal backend'
  s.description  = 'MetalANGLE provides EGL and GLES symbols via Apple Metal for iOS.'
  s.homepage     = 'https://github.com/anomalyco/art3m1s'
  s.license      = { :type => 'BSD' }
  s.author       = { 'ANGLE Authors' => '' }
  s.platform     = :ios, '13.0'
  s.source       = { :path => '.' }
  s.vendored_frameworks = 'MetalANGLE.xcframework'
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
