Pod::Spec.new do |s|
  s.name         = 'PfsUpk'
  s.version      = '0.1.0'
  s.summary      = 'PFS archive unpacker'
  s.description  = 'PFS archive reader (pfs-upk) compiled as a dynamic framework for iOS.'
  s.homepage     = 'https://github.com/anomalyco/art3m1s'
  s.license      = { :type => 'MIT' }
  s.author       = { 'Art3m1s' => '' }
  s.platform     = :ios, '13.0'
  s.source       = { :path => '.' }
  s.vendored_frameworks = 'pfs_upk.xcframework'
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
