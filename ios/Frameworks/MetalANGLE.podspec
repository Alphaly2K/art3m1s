Pod::Spec.new do |s|
  s.name         = 'MetalANGLE'
  s.version      = '0.1.0'
  s.summary      = 'Official ANGLE with the Metal backend'
  s.description  = 'Official Chromium ANGLE provides EGL and GLES over Metal for iOS.'
  s.homepage     = 'https://chromium.googlesource.com/angle/angle/'
  s.license      = { :type => 'BSD-3-Clause' }
  s.author       = { 'ANGLE Authors' => '' }
  s.platform     = :ios, '13.0'
  s.source       = { :path => '.' }
  s.vendored_frameworks = 'libEGL.xcframework', 'libGLESv2.xcframework'
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
