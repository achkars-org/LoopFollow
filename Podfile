platform :ios, '16.6'

target 'LoopFollow' do
  use_frameworks!

  pod 'Charts'
  pod 'ShareClient', :git => 'https://github.com/loopandlearn/dexcom-share-client-swift.git', :branch => 'loopfollow'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.6'
    end
  end
end