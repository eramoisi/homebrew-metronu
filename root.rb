class Root < Formula
  desc "Object oriented framework for large scale data analysis"
  homepage "https://root.cern.ch/"
  url "https://root.cern.ch/download/root_v6.18.04.source.tar.gz"
  version "6.18.04"
  sha256 "315a85fc8363f8eb1bffa0decbf126121258f79bd273513ed64795675485cfa4"
  head "https://github.com/root-project/root.git"

  bottle do
    sha256 "9ce760ff961b29b382d8373c6fbe72808e025b9a3e6113deb64df8586b0a853d" => :mojave
    sha256 "acbac57657964414945706d499bab86ad7ac6367c78493a5e47de2eba111e0f1" => :high_sierra
    sha256 "82e6f8dc5048f3977c9a942c2fd62671423f95bfe77e6d5abd9f53b6ac141b13" => :sierra
  end

  # https://github.com/Homebrew/homebrew-core/issues/30726
  # strings libCling.so | grep Xcode:
  #  /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include/c++/v1
  #  /Applications/Xcode.app/Contents/Developer
  pour_bottle? do
    reason "The bottle hardcodes locations inside Xcode.app"
    satisfy do
      MacOS::Xcode.installed? &&
        MacOS::Xcode.prefix.to_s.include?("/Applications/Xcode.app/")
    end
  end

  depends_on "cmake" => :build
  depends_on "davix"
  depends_on "fftw"
  depends_on "gcc" # for gfortran
  depends_on "graphviz"
  depends_on "gsl"
  # Temporarily depend on Homebrew libxml2 to work around a brew issue:
  # https://github.com/Homebrew/brew/issues/5068
  depends_on "libxml2" if MacOS.version >= :mojave
  depends_on "lz4"
  depends_on "openssl@1.1"
  depends_on "pcre"
  depends_on "python"
  depends_on "tbb"
  depends_on "xrootd"
  depends_on "xz" # for LZMA

  skip_clean "bin"

  def install
    # Work around "error: no member named 'signbit' in the global namespace"
    ENV.delete("SDKROOT") if DevelopmentTools.clang_build_version >= 900

    # Freetype/afterimage/gl2ps/lz4 are vendored in the tarball, so are fine.
    # However, this is still permitting the build process to make remote
    # connections. As a hack, since upstream support it, we inreplace
    # this file to "encourage" the connection over HTTPS rather than HTTP.
    inreplace "cmake/modules/SearchInstalledSoftware.cmake",
              "http://lcgpackages",
              "https://lcgpackages"

    py_exe = Utils.popen_read("which python3").strip
    py_prefix = Utils.popen_read("python3 -c 'import sys;print(sys.prefix)'").chomp
    py_inc = Utils.popen_read("python3 -c 'from distutils import sysconfig;print(sysconfig.get_python_inc(True))'").chomp
    ohai "Python executable:   #{py_exe}"
    ohai "Python prefix:       #{py_prefix}"
    ohai "Python include path: #{py_inc}"

    args = std_cmake_args + %W[
      -DCLING_CXX_PATH=clang++
      -DCMAKE_INSTALL_ELISPDIR=#{elisp}
      -DPYTHON_EXECUTABLE=#{py_exe}
      -DPYTHON_INCLUDE_DIR=#{py_inc}
      -DPYTHON_LIBRARY=#{py_prefix}/Python
      -Dbuiltin_cfitsio=OFF
      -Dbuiltin_freetype=ON
      -Ddavix=ON
      -Dfftw3=ON
      -Dfitsio=OFF
      -Dfortran=ON
      -Dgdml=ON
      -Dgnuinstall=ON
      -Dimt=ON
      -Dmathmore=ON
      -Dminuit2=ON
      -Dmysql=OFF
      -Dpgsql=OFF
      -Dpython=ON
      -Droofit=ON
      -Dssl=ON
      -Dtmva=ON
      -Dxrootd=ON
    ]

    cxx_version = (MacOS.version < :mojave) ? 14 : 17
    args << "-DCMAKE_CXX_STANDARD=#{cxx_version}"

    mkdir "builddir" do
      system "cmake", "..", *args

      # Work around superenv stripping out isysroot leading to errors with
      # libsystem_symptoms.dylib (only available on >= 10.12) and
      # libsystem_darwin.dylib (only available on >= 10.13)
      if MacOS.version < :high_sierra
        system "xcrun", "make", "install"
      else
        system "cmake --build . -- -j8"
        system "cmake --build . -- install"
      end

      chmod 0755, Dir[bin/"*.*sh"]
    end
  end

  def caveats; <<~EOS
    Because ROOT depends on several installation-dependent
    environment variables to function properly, you should
    add the following commands to your shell initialization
    script (.bashrc/.profile/etc.), or call them directly
    before using ROOT.

    For bash users:
      . #{HOMEBREW_PREFIX}/bin/thisroot.sh
    For zsh users:
      pushd #{HOMEBREW_PREFIX} >/dev/null; . bin/thisroot.sh; popd >/dev/null
    For csh/tcsh users:
      source #{HOMEBREW_PREFIX}/bin/thisroot.csh
    For fish users:
      . #{HOMEBREW_PREFIX}/bin/thisroot.fish
  EOS
  end

  test do
    (testpath/"test.C").write <<~EOS
      #include <iostream>
      void test() {
        std::cout << "Hello, world!" << std::endl;
      }
    EOS

    # Test ROOT command line mode
    system "#{bin}/root", "-b", "-l", "-q", "-e", "gSystem->LoadAllLibraries(); 0"

    # Test ROOT executable
    (testpath/"test_root.bash").write <<~EOS
      . #{bin}/thisroot.sh
      root -l -b -n -q test.C
    EOS
    assert_equal "\nProcessing test.C...\nHello, world!\n",
                 shell_output("/bin/bash test_root.bash")

    (testpath/"test.cpp").write <<~EOS
      #include <iostream>
      #include <TString.h>
      int main() {
        std::cout << TString("Hello, world!") << std::endl;
        return 0;
      }
    EOS

    # Test linking
    (testpath/"test_compile.bash").write <<~EOS
      . #{bin}/thisroot.sh
      $(root-config --cxx) $(root-config --cflags) $(root-config --libs) $(root-config --ldflags) test.cpp
      ./a.out
    EOS
    assert_equal "Hello, world!\n",
                 shell_output("/bin/bash test_compile.bash")

    # Test Python module
    ENV["PYTHONPATH"] = lib/"root"
    system "python3", "-c", "import ROOT; ROOT.gSystem.LoadAllLibraries()"
  end
end
