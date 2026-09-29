# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'

class FirebaseFlavorCopyTest < Minitest::Test
  def test_every_copy_phase_selects_profile_flavor_instead_of_leaving_a_stale_plist
    project = File.read(File.expand_path('../Runner.xcodeproj/project.pbxproj', __dir__))
    scripts = project.scan(/shellScript = ("(?:[^"\\]|\\.)*");/).flatten.map { |s| JSON.parse(s) }
      .select { |s| s.include?('DEV_GOOGLE_PLIST') }
    refute_empty scripts
    scripts.each do |script|
      %w[Profile-prod Profile-dev Debug-prod Release-prod Debug-dev Release-dev].each do |config|
        Dir.mktmpdir('omi-firebase-flavor') do |dir|
          %w[Runner Config/Prod Config/Dev].each { |p| FileUtils.mkdir_p(File.join(dir, p)) }
          File.write(File.join(dir, 'Config/Prod/GoogleService-Info.plist'), 'production')
          File.write(File.join(dir, 'Config/Dev/GoogleService-Info.plist'), 'development')
          File.write(File.join(dir, 'Runner/GoogleService-Info.plist'), 'stale')
          stdout, stderr, status = Open3.capture3({ 'PROJECT_DIR' => dir, 'CONFIGURATION' => config }, 'sh', '-c', script)
          assert status.success?, "#{config}: #{stdout}\n#{stderr}"
          assert_equal config.end_with?('-prod') ? 'production' : 'development',
            File.read(File.join(dir, 'Runner/GoogleService-Info.plist')), config
        end
      end
    end
  end
end
