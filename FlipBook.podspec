Pod::Spec.new do |s|
  s.name             = 'FlipBook'
  s.version          = '1.5.10'
  s.summary          = 'A swift package for recording views. Record a view and write to video, gif, or Live Photo. Also, create videos, gifs, and Live Photos from an array of images.'
  s.homepage         = 'https://github.com/bgayman/FlipBook'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Brad Gayman' => 'bgayman@mac.com' }
  s.source           = { :git => 'https://github.com/bgayman/FlipBook.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.ios.frameworks = 'AVFoundation', 'CoreGraphics', 'CoreImage', 'CoreServices', 'ImageIO', 'Photos', 'ReplayKit', 'UIKit', 'VideoToolbox'

  s.tvos.deployment_target = '10.0'
  s.tvos.frameworks = 'AVFoundation', 'CoreGraphics', 'CoreImage', 'CoreServices', 'ImageIO', 'Photos', 'ReplayKit', 'UIKit', 'VideoToolbox'

  s.osx.deployment_target = '10.15'
  s.osx.frameworks = 'AVFoundation', 'CoreGraphics', 'CoreImage', 'CoreServices', 'ImageIO', 'Photos', 'ReplayKit', 'AppKit', 'VideoToolbox'

  s.source_files = 'Sources/FlipBook/*.swift'
end
