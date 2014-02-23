# Puppet Library
# Copyright (C) 2014 drrb
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'json'
require 'zlib'
require 'open3'
require 'rubygems/package'
require 'puppet_library/forge/abstract'
require 'puppet_library/util/git'
require 'puppet_library/util/temp_dir'

module PuppetLibrary::Forge
    class GitRepository < PuppetLibrary::Forge::Abstract
        def initialize(url, version_tag_regex)
            super(self)
            @url = url
            @path = PuppetLibrary::Util::TempDir.create("git-repo-cache")
            @version_tag_regex = version_tag_regex
            @git = PuppetLibrary::Util::Git.new(@path)
            @mutex = Mutex.new
        end

        def destroy!
            FileUtils.rm_rf @path
        end

        def get_module(author, name, version)
            update_cache

            return nil unless tags.include? tag_for(version)

            metadata = modulefile_for(version).to_metadata
            return nil unless metadata["name"] == "#{author}-#{name}"

            on_tag_for(version) do
                PuppetLibrary::Archive::Archiver.archive_dir('.', "#{metadata["name"]}-#{version}") do |archive|
                    archive.add_file("metadata.json", 0644) do |entry|
                        entry.write metadata.to_json
                    end
                end
            end
        end

        def get_all_metadata
            update_cache
            tags.map do |tag|
                modulefile_for_tag(tag).to_metadata
            end
        end

        def get_metadata(author, module_name)
            metadata = get_all_metadata
            metadata.select do |m|
                m["author"] == author
                m["name"] == "#{author}-#{module_name}"
            end
        end

        private
        def update_cache
            puts "Updating git repo cache"
            @mutex.synchronize do
                if File.directory? "#{@path}/.git"
                    puts "    Cache already exists: fetching updates from #{@url}"
                    @git.git "fetch --tags"
                else
                    puts "    No cache yet: creating one in #{@path}"
                    @git.git "clone --bare #{@url} #{@path}/.git"
                end
            end
        end

        def tags
            @git.tags.select {|tag| tag =~ @version_tag_regex }
        end

        def modulefile_for_tag(tag)
            modulefile_source = @git.read_file("Modulefile", tag)
            PuppetLibrary::PuppetModule::Modulefile.parse(modulefile_source)
        end

        def modulefile_for(version)
            modulefile_for_tag(tag_for(version))
        end

        def on_tag_for(version, &block)
            @git.on_tag(tag_for(version), &block)
        end

        def tag_for(version)
            version
        end
    end
end
