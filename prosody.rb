require "formula"

class Prosody < Formula
  homepage "http://prosody.im"

  url "https://prosody.im/downloads/source/prosody-0.9.14.tar.gz"
  sha256 "27d1388acd79eaa453f2b194bd23c25121fe0a704d0dd940457caf1874ea1123"
  version "0.9.14"

  # url "https://hg.prosody.im/0.9/", :using => :hg
  # revision 1

  depends_on "lua51"
  depends_on "expat"
  depends_on "libidn"
  depends_on "openssl"

  resource "luarocks" do
    url "http://luarocks.github.io/luarocks/releases/luarocks-2.4.1.tar.gz"
    sha256 "e429e0af9764bfd5cb640cac40f9d4ed1023fa17c052dff82ed0a41c05f3dcf9"
  end

  def install
    # Install to the Cellar, but direct modules to prefix
    # Specify where the Lua is to avoid accidental conflict.
    lua_prefix = Formula["lua51"].opt_prefix
    openssl = Formula["openssl"]

    # set CFLAGS/LDFLAGS based on host OS (for shared libraries)
    if OS.linux?
        cflags = "-fPIC -I#{openssl.opt_include}"
        ldflags = "-shared -L#{openssl.opt_lib}"
    else
        cflags = "-I#{openssl.opt_include}"
        ldflags = "-bundle -undefined dynamic_lookup -L#{openssl.opt_lib}"
    end

    args = ["--prefix=#{prefix}",
            "--sysconfdir=#{etc}/prosody",
            "--datadir=#{var}/lib/prosody",
            "--with-lua=#{lua_prefix}",
            "--with-lua-include=#{lua_prefix}/include/lua5.1",
            "--runwith=lua5.1",
            "--cflags=#{cflags}",
            "--ldflags=#{ldflags}"]

    system "./configure", *args
    system "make"

    # patch config
    inreplace 'prosody.cfg.lua.install' do |s|
      s.sub! '--"posix";', '"posix";'
      s.sub! 'info = "prosody.log";', "-- info = \"#{var}/log/prosody/prosody.log\";"
      s.sub! 'error = "prosody.err";', "-- error = \"#{var}/log/prosody/prosody.err\";"
      # s.sub! '-- "*syslog";', '"*syslog";'
      s.sub! '-- "*console";', '"*console";'
      s.sub! '----------- Virtual hosts -----------', "daemonize=false\n\n----------- Virtual hosts -----------"
      # pid
    end

    (etc+"prosody").mkpath
    (var+"lib/prosody").mkpath
    (var+"run/prosody").mkpath
    (var+"log/prosody").mkpath

    system "make", "install"
    cd "tools/migration" do
      system "make", "install"
    end

    resource("luarocks").stage do
      args = ["--prefix=#{libexec}",
              "--rocks-tree=#{libexec}",
              "--sysconfdir=#{libexec}/etc/luarocks",
              "--force-config",
              "--with-lua=#{lua_prefix}",
              "--lua-version=5.1",
              "--lua-suffix=5.1"]

      system "./configure", *args
      system "make", "build"
      system "make", "install"
      bin.install_symlink "#{libexec}/bin/luarocks" => "prosody-luarocks"
      bin.install_symlink "#{libexec}/bin/luarocks-admin" => "prosody-luarocks-admin"

      # always build rocks against the homebrew openssl, not the system one
      File.open("#{libexec}/etc/luarocks/config-5.1.lua", "a") do |file|
        file.write("external_deps_dirs = { [[#{openssl.opt_prefix}]] }\n")
      end
    end

    # set lua paths for our prosody-luarocks
    inreplace ["#{prefix}/bin/prosody", "#{prefix}/bin/prosodyctl"] do |s|
      rep = "-- Will be modified by configure script if run --"
      luapaths = <<~EOS.chomp
      package.path=[[#{libexec}/share/lua/5.1/?.lua;#{libexec}/share/lua/5.1/?/init.lua]];
      package.cpath=[[#{libexec}/lib/lua/5.1/?.so]];
      EOS
      s.sub! rep, "#{rep}\n\n#{luapaths}"
    end

    system "#{bin}/prosody-luarocks", "install", "luasocket"
    system "#{bin}/prosody-luarocks", "install", "luasec"
    system "#{bin}/prosody-luarocks", "install", "luafilesystem"
    system "#{bin}/prosody-luarocks", "install", "luaexpat", "EXPAT_DIR=#{Formula["expat"].opt_prefix}"
    # system "#{bin}/prosody-luarocks", "install", "lua-zlib"
  end

  # TODO more detailed
  def caveats; <<~EOS
    Prosody configs in: #{etc}/prosody
    Rocks install to: #{libexec}/lib/luarocks/rocks

    You may need to run `prosody-luarocks install` inside the Homebrew build
    environment for rocks to successfully build. To do this, first run `brew sh`.
    EOS
  end

  test do
    system "#{bin}/luarocks", "install", "say"
  end
end

# external_deps_dirs = { "/usr/local/opt/openssl" }
