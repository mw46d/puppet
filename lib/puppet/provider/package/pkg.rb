require 'puppet/provider/package'

Puppet::Type.type(:package).provide :pkg, :parent => Puppet::Provider::Package do
  desc "OpenSolaris image packaging system. See pkg(5) for more information"

  commands :pkg => "/usr/bin/pkg"

  confine :operatingsystem => :solaris

  #defaultfor [:operatingsystem => :solaris, :kernelrelease => "5.11"]
  #
  # do this here,
  def self.newstylepkgoutput
    unless defined?( @newstylepkgoutput )
      # This isn't ideal, as it's a SHA1/hash of some ilk, rather than a
      # real version number so you can't do comparisons on it. I think we
      # need a more computational way of finding it out.
      @newstylepkgoutput = ( pkg(:version).chomp == 'a6782843ee0c' )
    end
    @newstylepkgoutput
  end

  def self.instances

    self.newstylepkgoutput

    packages = []

    pkg(:list, '-H').each_line do |line|
      # now turn each returned line into a package object
      if hash = parse_line(line.chomp)
        packages << new(hash)
      end
    end

    packages
  end

  # Sol 11 version
  # x11/library/libxcb  1.7-0.175.0.0.0.0.1215     i--

  self::REGEX = /^(\S+)(?:\s+\(.*?\))?\s+(\S+)\s+(\S+)\s+\S+$/
  self::SOL11REGEX = /^(\S+)\s+(\S+)\s+(\S+)$/
  self::FIELDS = [:name, :version, :status]

  def self.parse_line(line)
    hash = {}

    if newstylepkgoutput
      regex = self::SOL11REGEX
    else
      regex = self::REGEX
    end

    if match = regex.match(line)

      self::FIELDS.zip(match.captures) { |field,value|
        hash[field] = value
      }

      hash[:provider] = self.name

      if hash[:status] == "installed" or hash[:status] == "i--"
        hash[:ensure] = :present
      else
        hash[:ensure] = :absent
      end
    else
      warning "Failed to match 'pkg list' line #{line.inspect}"
      return nil
    end

    hash
  end

  # return the version of the package
  # TODO deal with multiple publishers
  def latest
    version = nil
    pkg(:list, "-Ha", @resource[:name]).each_line do |line|
      v = self.class.parse_line(line.chomp)[:status]
      case v
      when "known"
        return v
      when "installed"
        version = v
      when "i--"
        version = self.class.parse_line(line.chomp)[:version]
      else
        Puppet.warn "unknown package state for #{@resource[:name]}: #{v}"
      end
    end
    version
  end

  # install the package
  def install
    pkg :install, @resource[:name]
  end

  # uninstall the package
  def uninstall
    pkg :uninstall, '-r', @resource[:name]
  end

  # update the package to the latest version available
  def update
    self.install
  end

  # list a specific package
  def query
    self.class.newstylepkgoutput
    begin
      output = pkg(:list, "-H", @resource[:name])
    rescue Puppet::ExecutionFailure
      # pkg returns 1 if the package is not found.
      return {:ensure => :absent, :name => @resource[:name]}
    end

    hash = self.class.parse_line(output.chomp) || {:ensure => :absent, :name => @resource[:name]}
    hash
  end
end
