require 'etc'
require 'facter'
require 'puppet/type/state'
require 'puppet/type/nameservice'

module Puppet
    newtype(:user, Puppet::Type::NSSType) do
        case Facter["operatingsystem"].value
        when "Darwin":
            @parentstate = Puppet::NameService::NetInfo::NetInfoState
            @parentmodule = Puppet::NameService::NetInfo
        else
            @parentstate = Puppet::NameService::ObjectAdd::ObjectAddUser
            @parentmodule = Puppet::NameService::ObjectAdd
        end

        newstate(:uid, @parentstate) do
            desc "The user ID.  Must be specified numerically.  For new users
                being created, if no user ID is specified then one will be
                chosen automatically, which will likely result in the same user
                having different IDs on different systems, which is not
                recommended."

            isautogen

            def autogen
                highest = 0
                Etc.passwd { |user|
                    if user.uid > highest
                        unless user.uid > 65000
                            highest = user.uid
                        end
                    end
                }

                return highest + 1
            end

            munge do |value|
                case value
                when String
                    if value =~ /^[-0-9]+$/
                        value = Integer(value)
                    end
                when Symbol
                    unless value == :notfound or value == :auto
                        raise Puppet::DevError, "Invalid UID %s" % value
                    end

                    if value == :auto
                        value = autogen()
                    end
                end

                return value
            end
        end

        newstate(:gid, @parentstate) do
            desc "The user's primary group.  Can be specified numerically or
                by name."

            isautogen

            munge do |gid|
                method = :getgrgid
                case gid
                when String
                    if gid =~ /^[-0-9]+$/
                        gid = Integer(gid)
                    else
                        method = :getgrnam
                    end
                when Symbol
                    unless gid == :auto or gid == :notfound
                        raise Puppet::DevError, "Invalid GID %s" % gid
                    end
                    # these are treated specially by sync()
                    return gid
                end

                # FIXME this should really check to see if we already have a
                # group ready to be managed; if so, then we should just mark it
                # as a prereq
                begin
                    ginfo = Etc.send(method, gid)
                rescue ArgumentError => detail
                    raise Puppet::Error, "Could not find group %s: %s" %
                        [gid, detail]
                end

                self.notice "setting gid to %s" % ginfo.gid.inspect
                return ginfo.gid
            end
        end

        newstate(:comment, @parentstate) do
            desc "A description of the user.  Generally is a user's full name."

            isoptional

            @posixmethod = :gecos
        end

        newstate(:home, @parentstate) do
            desc "The home directory of the user.  The directory must be created
                separately and is not currently checked for existence."

            isautogen
            @posixmethod = :dir
        end

        newstate(:shell, @parentstate) do
            desc "The user's login shell.  The shell must exist and be
                executable."
            isautogen
        end

        # these three states are all implemented differently on each platform,
        # so i'm disabling them for now

        # FIXME Puppet::State::UserLocked is currently non-functional
        #newstate(:locked, @parentstate) do
        #    desc "The expected return code.  An error will be returned if the
        #        executed command returns something else."
        #end

        # FIXME Puppet::State::UserExpire is currently non-functional
        #newstate(:expire, @parentstate) do
        #    desc "The expected return code.  An error will be returned if the
        #        executed command returns something else."
        #    @objectaddflag = "-e"
        #    isautogen
        #end

        # FIXME Puppet::State::UserInactive is currently non-functional
        #newstate(:inactive, @parentstate) do
        #    desc "The expected return code.  An error will be returned if the
        #        executed command returns something else."
        #    @objectaddflag = "-f"
        #    isautogen
        #end

        newparam(:name) do
            desc "User name.  While limitations are determined for
                each operating system, it is generally a good idea to keep to
                the degenerate 8 characters, beginning with a letter."
            isnamevar
        end

        @doc = "Manage users.  Currently can create and modify users, but
            cannot delete them.  Theoretically all of the parameters are
            optional, but if no parameters are specified the comment will
            be set to the user name in order to make the internals work out
            correctly."

        @netinfodir = "users"

        def exists?
            self.class.parentmodule.exists?(self)
        end

        def getinfo(refresh = false)
            if @userinfo.nil? or refresh == true
                begin
                    @userinfo = Etc.getpwnam(self[:name])
                rescue ArgumentError => detail
                    @userinfo = nil
                end
            end

            @userinfo
        end

        def initialize(hash)
            @userinfo = nil
            super

            # Verify that they have provided everything necessary, if we
            # are trying to manage the user
            if self.managed?
                self.class.states.each { |state|
                    next if @states.include?(state.name)

                    unless state.autogen? or state.isoptional?
                        if state.method_defined?(:autogen)
                            self[state.name] = :auto
                        else
                            raise Puppet::Error,
                                "Users require a value for %s" % state.name
                        end
                    end
                }

                if @states.empty?
                    self[:comment] = self[:name]
                end
            end
        end

        def retrieve
            info = self.getinfo(true)

            if info.nil?
                # the user does not exist
                @states.each { |name, state|
                    state.is = :notfound
                }
                return
            else
                super
            end
        end
    end
end

# $Id$
