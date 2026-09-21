# frozen_string_literal: true
module RuntimeTools
  class Sources
    attr_reader :directory

    def initialize(directory)
      @directory = File.expand_path(directory)
      FileUtils.mkdir_p(@directory)
    end

    def fetch(name)
      RuntimeTools.source_specs(name).each do |key, source|
        path = File.join(directory, source.fetch("file"))
        unless File.file?(path)
          temporary = "#{path}.partial"
          if source["git"]
            Dir.mktmpdir("runtime-tools-git-") do |checkout|
              RuntimeTools.run("git", "init", "-q", checkout)
              RuntimeTools.run("git", "-C", checkout, "fetch", "--depth", "1", source.fetch("git"), source.fetch("commit"))
              RuntimeTools.run("git", "-C", checkout, "archive", "--format=tar", "--prefix=#{key}/", "-o", temporary, source.fetch("commit"))
            end
          else
            RuntimeTools.run("curl", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--retry", "3", "--output", temporary, source.fetch("url"))
          end
          RuntimeTools.verify(temporary, source.fetch("sha256"))
          File.rename(temporary, path)
        end
        RuntimeTools.verify(path, source.fetch("sha256"))
      end
    end

    def extract(name, destination)
      source = RuntimeTools.lock.fetch("sources").fetch(name)
      path = File.join(directory, source.fetch("file"))
      RuntimeTools.verify(path, source.fetch("sha256"))
      entries = RuntimeTools.capture("tar", "-tf", path).lines.map(&:strip)
      unless entries.all? { !_1.start_with?("/") && !_1.split("/").include?("..") }
        raise Error, "Unsafe source archive paths"
      end
      FileUtils.mkdir_p(destination)
      RuntimeTools.run("tar", "-xf", path, "--strip-components=1", "-C", destination)
    end
  end
end
