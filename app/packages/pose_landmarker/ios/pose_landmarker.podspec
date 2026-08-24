#
# pose_landmarker — iOS. MediaPipe Tasks Vision Pose Landmarker over a recorded
# clip (VIDEO mode), mirroring the Android Kotlin plugin's channel contract.
#
Pod::Spec.new do |s|
  s.name             = 'pose_landmarker'
  s.version          = '0.1.0'
  s.summary          = 'MediaPipe Pose Landmarker over a recorded clip (iOS).'
  s.description      = <<-DESC
Thin federated plugin around MediaPipe Tasks Vision Pose Landmarker. Runs pose
estimation over a recorded video file and streams the landmark sequence back to
Dart on the same method/event channels as the Android implementation.
                       DESC
  s.homepage         = 'https://aiboxingcoach.example'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'AI Boxing Coach' => 'phisoluciones.es@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # MediaPipe Tasks Vision provides PoseLandmarker for iOS.
  s.dependency 'MediaPipeTasksVision', '~> 0.10.14'

  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice; MediaPipe ships arm64 only.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
