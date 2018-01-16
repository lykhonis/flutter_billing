#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'flutter_billing'
  s.version          = '0.0.1'
  s.summary          = 'A flutter plugin to communicate with billing on iOS and Android.'
  s.description      = <<-DESC
A flutter plugin to communicate with billing on iOS and Android.
                       DESC
  s.homepage         = 'http://vladimirlichonos.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Volodymyr Lykhonis' => 'vladimirlichonos@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  
  s.ios.deployment_target = '8.0'
end
