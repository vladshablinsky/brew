module Homebrew
  module Diagnostic
    class Checks
      def all_development_tools_checks
        %w[
          check_for_unsupported_osx
          check_for_bad_install_name_tool
          check_for_installed_developer_tools
          check_xcode_license_approved
          check_for_osx_gcc_installer
        ]
      end

      def check_for_unsupported_osx
        return if ARGV.homebrew_developer?

        who = "We"
        if OS::Mac.prerelease?
          what = "pre-release version"
        elsif OS::Mac.outdated_release?
          who << " (and Apple)"
          what = "old version"
        else
          return
        end

        <<-EOS.undent
          You are using OS X #{MacOS.version}.
          #{who} do not provide support for this #{what}.
          You may encounter build failures or other breakages.
          Please create pull-requests instead of filing issues.
        EOS
      end

      # TODO: distill down into single method definition a la BuildToolsError
      if MacOS.version >= "10.9"
        def check_for_installed_developer_tools
          return if MacOS::Xcode.installed? || MacOS::CLT.installed?

          <<-EOS.undent
            No developer tools installed.
            Install the Command Line Tools:
              xcode-select --install
          EOS
        end

        if OS::Mac.prerelease?
          def check_xcode_up_to_date
            return unless MacOS::Xcode.installed? && MacOS::Xcode.outdated?

            <<-EOS.undent
              Your Xcode (#{MacOS::Xcode.version}) is outdated
              Please update to Xcode #{MacOS::Xcode.latest_version}.
              Xcode can be updated from
                https://developer.apple.com/xcode/downloads/
            EOS
          end
        else
          def check_xcode_up_to_date
            return unless MacOS::Xcode.installed? && MacOS::Xcode.outdated?

            <<-EOS.undent
              Your Xcode (#{MacOS::Xcode.version}) is outdated
              Please update to Xcode #{MacOS::Xcode.latest_version}.
              Xcode can be updated from the App Store.
            EOS
          end
        end

        def check_clt_up_to_date
          return unless MacOS::CLT.installed? && MacOS::CLT.outdated?

          <<-EOS.undent
            A newer Command Line Tools release is available.
            Update them from Software Update in the App Store.
          EOS
        end
      elsif MacOS.version == "10.8" || MacOS.version == "10.7"
        def check_for_installed_developer_tools
          return if MacOS::Xcode.installed? || MacOS::CLT.installed?

          <<-EOS.undent
            No developer tools installed.
            You should install the Command Line Tools.
            The standalone package can be obtained from
              https://developer.apple.com/downloads
            or it can be installed via Xcode's preferences.
          EOS
        end

        def check_xcode_up_to_date
          return unless MacOS::Xcode.installed? && MacOS::Xcode.outdated?

          <<-EOS.undent
            Your Xcode (#{MacOS::Xcode.version}) is outdated
            Please update to Xcode #{MacOS::Xcode.latest_version}.
            Xcode can be updated from
              https://developer.apple.com/xcode/downloads/
          EOS
        end

        def check_clt_up_to_date
          return unless MacOS::CLT.installed? && MacOS::CLT.outdated?

          <<-EOS.undent
            A newer Command Line Tools release is available.
            The standalone package can be obtained from
              https://developer.apple.com/downloads
            or it can be installed via Xcode's preferences.
          EOS
        end
      else
        def check_for_installed_developer_tools
          return if MacOS::Xcode.installed?

          <<-EOS.undent
            Xcode is not installed. Most formulae need Xcode to build.
            It can be installed from
              https://developer.apple.com/xcode/downloads/
          EOS
        end

        def check_xcode_up_to_date
          return unless MacOS::Xcode.installed? && MacOS::Xcode.outdated?

          <<-EOS.undent
            Your Xcode (#{MacOS::Xcode.version}) is outdated
            Please update to Xcode #{MacOS::Xcode.latest_version}.
            Xcode can be updated from
              https://developer.apple.com/xcode/downloads/
          EOS
        end
      end

      def check_for_osx_gcc_installer
        return unless MacOS.version < "10.7" || ((MacOS::Xcode.version || "0") > "4.1")
        return unless DevelopmentTools.clang_version == "2.1"

        fix_advice = if MacOS.version >= :mavericks
          "Please run `xcode-select --install` to install the CLT."
        elsif MacOS.version >= :lion
          "Please install the CLT or Xcode #{MacOS::Xcode.latest_version}."
        else
          "Please install Xcode #{MacOS::Xcode.latest_version}."
        end

        <<-EOS.undent
          You seem to have osx-gcc-installer installed.
          Homebrew doesn't support osx-gcc-installer. It causes many builds to fail and
          is an unlicensed distribution of really old Xcode files.
          #{fix_advice}
        EOS
      end

      def check_for_stray_developer_directory
        # if the uninstaller script isn't there, it's a good guess neither are
        # any troublesome leftover Xcode files
        uninstaller = Pathname.new("/Developer/Library/uninstall-developer-folder")
        return unless ((MacOS::Xcode.version || "0") >= "4.3") && uninstaller.exist?

        <<-EOS.undent
          You have leftover files from an older version of Xcode.
          You should delete them using:
            #{uninstaller}
        EOS
      end

      def check_for_bad_install_name_tool
        return if MacOS.version < "10.9"

        libs = Pathname.new("/usr/bin/install_name_tool").dynamically_linked_libraries

        # otool may not work, for example if the Xcode license hasn't been accepted yet
        return if libs.empty?
        return if libs.include? "/usr/lib/libxcselect.dylib"

        <<-EOS.undent
          You have an outdated version of /usr/bin/install_name_tool installed.
          This will cause binary package installations to fail.
          This can happen if you install osx-gcc-installer or RailsInstaller.
          To restore it, you must reinstall OS X or restore the binary from
          the OS packages.
        EOS
      end

      def check_for_other_package_managers
        ponk = MacOS.macports_or_fink
        return if ponk.empty?

        <<-EOS.undent
          You have MacPorts or Fink installed:
            #{ponk.join(", ")}

          This can cause trouble. You don't have to uninstall them, but you may want to
          temporarily move them out of the way, e.g.

            sudo mv /opt/local ~/macports
        EOS
      end

      def check_ruby_version
        ruby_version = MacOS.version >= "10.9" ? "2.0" : "1.8"
        return if RUBY_VERSION[/\d\.\d/] == ruby_version

        <<-EOS.undent
          Ruby version #{RUBY_VERSION} is unsupported on #{MacOS.version}. Homebrew
          is developed and tested on Ruby #{ruby_version}, and may not work correctly
          on other Rubies. Patches are accepted as long as they don't cause breakage
          on supported Rubies.
        EOS
      end

      def check_xcode_prefix
        prefix = MacOS::Xcode.prefix
        return if prefix.nil?
        return unless prefix.to_s.include?(" ")

        <<-EOS.undent
          Xcode is installed to a directory with a space in the name.
          This will cause some formulae to fail to build.
        EOS
      end

      def check_xcode_prefix_exists
        prefix = MacOS::Xcode.prefix
        return if prefix.nil? || prefix.exist?

        <<-EOS.undent
          The directory Xcode is reportedly installed to doesn't exist:
            #{prefix}
          You may need to `xcode-select` the proper path if you have moved Xcode.
        EOS
      end

      def check_xcode_select_path
        return if MacOS::CLT.installed?
        return if File.file?("#{MacOS.active_developer_dir}/usr/bin/xcodebuild")

        path = MacOS::Xcode.bundle_path
        path = "/Developer" if path.nil? || !path.directory?
        <<-EOS.undent
          Your Xcode is configured with an invalid path.
          You should change it to the correct path:
            sudo xcode-select -switch #{path}
        EOS
      end

      def check_for_bad_curl
        return unless MacOS.version <= "10.8"
        return if Formula["curl"].installed?

        <<-EOS.undent
          The system curl on 10.8 and below is often incapable of supporting
          modern secure connections & will fail on fetching formulae.

          We recommend you:
            brew install curl
        EOS
      end

      def check_for_unsupported_curl_vars
        # Support for SSL_CERT_DIR seemed to be removed in the 10.10.5 update.
        return unless MacOS.version >= :yosemite
        return if ENV["SSL_CERT_DIR"].nil?

        <<-EOS.undent
          SSL_CERT_DIR support was removed from Apple's curl.
          If fetching formulae fails you should:
            unset SSL_CERT_DIR
          and remove it from #{shell_profile} if present.
        EOS
      end

      def check_for_other_package_managers
        ponk = MacOS.macports_or_fink
        return if ponk.empty?

        <<-EOS.undent
          You have MacPorts or Fink installed:
            #{ponk.join(", ")}

          This can cause trouble. You don't have to uninstall them, but you may want to
          temporarily move them out of the way, e.g.

            sudo mv /opt/local ~/macports
        EOS
      end

      def check_xcode_license_approved
        # If the user installs Xcode-only, they have to approve the
        # license or no "xc*" tool will work.
        return unless `/usr/bin/xcrun clang 2>&1` =~ /license/ && !$?.success?

        <<-EOS.undent
          You have not agreed to the Xcode license.
          Builds will fail! Agree to the license by opening Xcode.app or running:
            sudo xcodebuild -license
        EOS
      end

      def check_for_latest_xquartz
        return unless MacOS::XQuartz.version
        return if MacOS::XQuartz.provided_by_apple?

        installed_version = Version.new(MacOS::XQuartz.version)
        latest_version = Version.new(MacOS::XQuartz.latest_version)
        return if installed_version >= latest_version

        <<-EOS.undent
          Your XQuartz (#{installed_version}) is outdated
          Please install XQuartz #{latest_version}:
            https://xquartz.macosforge.org
        EOS
      end

      def check_for_beta_xquartz
        return unless MacOS::XQuartz.version
        return unless MacOS::XQuartz.version.include? "beta"

        <<-EOS.undent
        The following beta release of XQuartz is installed: #{MacOS::XQuartz.version}

        XQuartz beta releases include address sanitization, and do not work with
        all software; notably, wine will not work with beta releases of XQuartz.
        We recommend only installing stable releases of XQuartz.
        EOS
      end
    end
  end
end
